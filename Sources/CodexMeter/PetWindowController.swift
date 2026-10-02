import AppKit
import ColorSync
import WebKit
import SwiftUI

func petAnchorOffset(frame: NSRect, surfaceOffset: CGFloat, screen: NSRect) -> NSPoint {
    NSPoint(x: frame.minX + surfaceOffset - screen.minX, y: frame.minY - screen.minY)
}

struct PetDisplayIdentity: Equatable {
    let stableUUID: String?
    let transientID: UInt32

    func matches(_ other: PetDisplayIdentity) -> Bool {
        if let stableUUID, let otherUUID = other.stableUUID {
            return stableUUID == otherUUID
        }
        return transientID == other.transientID
    }
}

func petDisplayIdentity(for screen: NSScreen) -> PetDisplayIdentity? {
    guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
    let displayID = CGDirectDisplayID(number.uint32Value)
    let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue()
    let stableUUID = uuid.map { CFUUIDCreateString(nil, $0) as String }
    return PetDisplayIdentity(stableUUID: stableUUID, transientID: displayID)
}

/// Bakes an idle loop on changes and plays cached alpha frames in a native view.
@MainActor
final class PetWindowController: NSObject, WKScriptMessageHandler, WKNavigationDelegate, NSWindowDelegate {
    let panel = FloatingWindow(contentRect: NSRect(x: 200, y: 200, width: 256, height: 286), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    private let surface = PetSurface(frame: NSRect(x: 0, y: 0, width: 256, height: 286))
    private let canvas = NSView()
    private var sizeTransition: Timer?
    private var surfaceOffset: CGFloat = 0
    private var bubble: FloatingWindow?
    private var bubbleEntryID: String?
    private var bubbleText = ""
    private var bubblePlacement: PetBubblePlacement?
    private var bubbleReturnTimer: Timer?
    private var bubbleAvoidingStars = false
    private var renderer: WKWebView?
    private var ready = false
    private var switchingCharacter = false
    let messages = PetMessageModel()
    private var journal = PetQuotaJournal()
    private var demoSession: DemoSession?
    private var resumingFromDemo = false
    func setDemo(_ session: DemoSession?) {
        let wasDemo = demoSession != nil
        demoSession = session
        messages.isDemo = session != nil
        guard let session else {
            if wasDemo {
                resumingFromDemo = true
                journal.breakContinuity()
                messages.changes = journal.changes
                messages.entries = []
                messages.selectedAnnouncementID = nil
                messages.testReminderStatus = ""
                messages.quotaUpdatedAt = nil
            }
            return
        }
        dismissBubble()
        messages.selectedAnnouncementID = nil
        messages.entries = session.entries
        messages.changes = session.changes
        messages.checkedAt = session.startedAt
        messages.quotaUpdatedAt = session.startedAt
        messages.checking = false; messages.failed = false; messages.partialSources = false
        messages.primarySourceHealthy = nil
        messages.unread = false; messages.notificationDenied = false
        messages.remindersEnabled = false; messages.remindersReady = true
        messages.reminderStatus = "演示提醒 · 不发送系统通知 / Demo only"
        messages.testingReminder = false
        messages.enableReminders = nil; messages.checkPermission = nil
        messages.testReminder = { [weak self] in
            self?.messages.testReminderStatus = "示例提醒已展示，不代表真实重置 / Sample only"
        }
        messages.refresh = { [weak self] in self?.messages.checkedAt = Date() }
    }
    private var seenMessages = Set<String>()
    private var state: PetState?
    private var lastRenderedState: PetState?
    private var decodedFrameState: PetState?
    private struct CachedFrames {
        let state: PetState
        let idle, blink, turn, reading, hover: [NSImage]
        let variants: [[NSImage]]
    }
    private var characterFrames: [PetCharacter: CachedFrames] = [:]
    private var idleFrames: [NSImage] = []
    private var idleIndex = 0
    private var idleTimer: Timer?
    private var blinkFrames: [NSImage] = []
    private var turnFrames: [NSImage] = []
    private var reactionIndex: Int?
    private var reactionElapsed = 0.0
    private var activeFrameRate = 30.0
    private var readingFrames: [NSImage] = []
    private var hoverFrames: [NSImage] = []
    private var readingVariants: [[NSImage]] = []
    private var lastReadingVariant = -1
    private var sleepPlacement: (screen: PetDisplayIdentity, offset: NSPoint)?
    private var screenRecovery: Timer?
    private var connectedPlacement: (screen: PetDisplayIdentity, offset: NSPoint)?
    private var awaitingReconnect = false

    private func display(matching identity: PetDisplayIdentity) -> NSScreen? {
        NSScreen.screens.first { candidate in
            petDisplayIdentity(for: candidate)?.matches(identity) == true
        }
    }

    private func rememberConnectedPlacement() {
        guard !awaitingReconnect, let screen = panel.screen,
              let identity = petDisplayIdentity(for: screen) else { return }
        connectedPlacement = (identity, petAnchorOffset(frame: panel.frame, surfaceOffset: surfaceOffset, screen: screen.visibleFrame))
    }


    private func rememberSleepPlacement() {
        guard sleepPlacement == nil, let screen = panel.screen,
              let identity = petDisplayIdentity(for: screen) else { return }
        sleepPlacement = (identity, petAnchorOffset(frame: panel.frame, surfaceOffset: surfaceOffset, screen: screen.visibleFrame))
    }

    private func recoverSleepPlacement() {
        guard sleepPlacement != nil else { panel.keepInsideScreen(); return }
        screenRecovery?.invalidate()
        let deadline = Date().addingTimeInterval(15)
        screenRecovery = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                // Scheduled from the main actor, this timer runs on the main run loop.
                guard let self, self.sleepPlacement != nil else { timer.invalidate(); return }
                if NSEvent.pressedMouseButtons != 0 {
                    timer.invalidate(); self.screenRecovery = nil; self.sleepPlacement = nil
                    return
                }
                self.resizeForConstellation(self.surface.constellation.opened)
                if Date() >= deadline {
                    timer.invalidate(); self.screenRecovery = nil; self.sleepPlacement = nil
                    self.panel.keepInsideScreen(); self.positionBubble(); self.onMove?()
                }
            }
        }
    }
    private var hoverWake: Timer?
    private var pointerNear = false
    private var nextHoverAt = Date.distantPast
    private var openingLead = 0.0
    private var readingTick: Int?
    private var activityTicks = 0
    private var idleWake: Timer?
    private var idleReaction = false
    private var readingReaction = false
    private var activeIdleFrames: [NSImage] = []
    private var nextReadingAt = Date().addingTimeInterval(Double.random(in: 8...12))
    private var nextIdleAt = Date().addingTimeInterval(Double.random(in: 1.5...2.5))
    private var sleeping = false
    private var displaySleeping = false
    var onLayout: (() -> Void)?
    var onMove: (() -> Void)?
    var onClick: (() -> Void)?
    var onFrame: ((Data, PetState) -> Void)?
    var onFailure: ((String) -> Void)?

    private let preferences: UserDefaults
    private(set) var character: PetCharacter
    init(preferences: UserDefaults = .standard) {
        self.preferences = preferences
        self.character = PetCharacter.selected(in: preferences)
        super.init()
        panel.hasShadow = false; panel.delegate = self; panel.contentView = canvas
        canvas.addSubview(surface)
        surface.autoresizingMask = []
        surface.installMessages(messages)
        surface.moveDetails(to: canvas)
        resizeForConstellation(false)
        surface.hoverChanged = { [weak self] near in self?.pointerProximityChanged(near) }
        surface.selectPage = { [weak self] page in self?.selectMessagePage(page) }
        messages.close = { [weak self] in self?.selectMessagePage("quota") }
        surface.dragEnded = { [weak self] in
            guard let self else { return }
            self.awaitingReconnect = false
            self.screenRecovery?.invalidate(); self.screenRecovery = nil; self.sleepPlacement = nil
            self.rememberConnectedPlacement()
            self.positionBubble()
            self.preferences.set([self.panel.frame.minX + self.surfaceOffset, self.panel.frame.minY], forKey: "pet.userOrigin.v1")
        }
        surface.clicked = { [weak self] in
            guard let self else { return }
            self.hoverWake?.invalidate(); self.hoverWake = nil
            self.surface.constellation.opened.toggle()
            // A reversal continues immediately; only a fresh summon has a short gaze lead.
            self.openingLead = self.surface.constellation.opened && self.surface.constellation.progress == 0
                && !(self.character == .archivist && self.reactionIndex != nil && !self.idleReaction)
                ? (self.character == .archivist ? 0.30 : 0.12) : 0
            // Immediate smoke seed acknowledges the click; gaze precedes expansion.
            if self.surface.constellation.opened { self.surface.constellation.progress = max(0.025, self.surface.constellation.progress) }
            if !self.surface.constellation.opened { self.selectMessagePage("quota") }
            if self.surface.constellation.opened { self.resizeForConstellation(true) }
            if self.surface.constellation.opened && !(self.character == .archivist && self.reactionIndex != nil && !self.idleReaction) {
                let rate = 30.0
                // Continue an interrupted male pose instead of jumping back to reading.
                let start = self.character == .archivist && self.reactionIndex != nil
                    ? closestPetPose(self.surface.image, in: Array(self.turnFrames.prefix(74))) : 0
                self.activeFrameRate = rate; self.reactionElapsed = Double(start) / rate
                self.reactionIndex = start; self.idleReaction = false; self.readingReaction = false
            }
            // Closing affects the constellation immediately. Let the continuous
            // response finish forward; reversing a long clip compressed its motion.
            // Reopening during that response also preserves its current playhead.

            self.refreshPlayback()
            self.onClick?()
        }
        surface.setAccessibilityElement(true); surface.setAccessibilityRole(.button)
        let notifications = NSWorkspace.shared.notificationCenter
        notifications.addObserver(self, selector: #selector(pauseForSleep), name: NSWorkspace.willSleepNotification, object: nil)
        notifications.addObserver(self, selector: #selector(resumeFromSleep), name: NSWorkspace.didWakeNotification, object: nil)
        notifications.addObserver(self, selector: #selector(refreshPlayback), name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        notifications.addObserver(self, selector: #selector(pauseForDisplaySleep), name: NSWorkspace.screensDidSleepNotification, object: nil)
        notifications.addObserver(self, selector: #selector(resumeDisplay), name: NSWorkspace.screensDidWakeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }
    func show(near rect: NSRect, allDesktops: Bool) {
        setAllDesktops(allDesktops)
        if !panel.isVisible {
            let saved = preferences.array(forKey: "pet.userOrigin.v1") as? [Double]
            let origin = savedPetOrigin(saved) ?? NSPoint(x: rect.minX, y: rect.maxY-panel.frame.height)
            panel.setFrameOrigin(origin)
            panel.keepInsideScreen()
        }
        panel.orderFrontRegardless()
        if connectedPlacement == nil { rememberConnectedPlacement() }
        if renderer == nil { loadRenderer() }
        renderIfNeeded()
        refreshPlayback()
    }
    func stop() {
        screenRecovery?.invalidate(); screenRecovery = nil; sleepPlacement = nil
        dismissBubble()
        resetRenderer()
        characterFrames.removeAll()
        surface.image = nil
        panel.orderOut(nil)
    }
    private func resetRenderer() {
        decodedFrameState = nil
        hoverWake?.invalidate(); hoverWake = nil; pointerNear = false
        hoverFrames = []; readingVariants = []; lastReadingVariant = -1; openingLead = 0
        surface.hintMotionAllowed = false
        activeIdleFrames = []
        idleWake?.invalidate(); idleWake = nil
        idleTimer?.invalidate(); idleTimer = nil; idleFrames = []; blinkFrames = []; turnFrames = []; readingFrames = []; readingTick = nil; activityTicks = 0
        reactionIndex = nil; idleIndex = 0
        renderer?.configuration.userContentController.removeScriptMessageHandler(forName: "pet")
        renderer?.stopLoading(); renderer = nil; ready = false; lastRenderedState = nil
    }
    private func resizeForConstellation(_ expanded: Bool, interpolated: (Double, Double, Double)? = nil) {
        if interpolated == nil { sizeTransition?.invalidate(); sizeTransition = nil }
        let displaySize = PetDisplaySize.selected(in: preferences)
        let scale = interpolated?.0 ?? displaySize.scale
        let details = expanded && messages.page != "quota"
        let cardWidth = interpolated?.1 ?? displaySize.detailWidth
        let cardSpan = cardWidth + 10
        // The static estimate can lag behind the card's fixed (non-scrolling)
        // content; the overflow then runs past the window's top edge and is
        // clipped flat. Measure the live SwiftUI ideal height instead and let
        // the scrolling list absorb anything above detailMaxHeight.
        let estimatedHeight = displaySize.detailHeight(page: messages.page, count: messages.page == "changes" ? messages.changes.count : messages.entries.count)
        let measuredHeight = surface.detailsFittingHeight(displaySize.detailWidth)
        let cardHeight = interpolated?.2 ?? min(displaySize.detailMaxHeight, max(estimatedHeight, measuredHeight))
        let bodyWidth = (expanded ? 440.0 : 256.0) * scale
        let bodyHeight = (expanded ? 410.0 : 286.0) * scale
        // Anchor the character, even when a detail card changes sides.
        var anchor = panel.frame.origin.x + surfaceOffset
        var originY = panel.frame.minY
        var screen = panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        if let saved = sleepPlacement {
            // External displays can disappear temporarily during wake. Do not adopt
            // the fallback window origin or its detail-card offset as the user's position.
            guard let restored = display(matching: saved.screen) else { return }
            screen = restored.visibleFrame
            anchor = screen.minX + saved.offset.x
            originY = screen.minY + saved.offset.y
        }
        let left = details && anchor + bodyWidth + cardSpan > screen.maxX && anchor - cardSpan >= screen.minX
        surfaceOffset = left ? cardSpan : 0
        let size = NSSize(width: bodyWidth + (details ? cardSpan : 0), height: max(bodyHeight, details ? cardHeight + 24 : 0))
        panel.setFrame(NSRect(x: anchor - surfaceOffset, y: originY, width: size.width, height: size.height), display: true)
        surface.frame = NSRect(x: surfaceOffset, y: 0, width: bodyWidth, height: bodyHeight)
        surface.setBoundsSize(NSSize(width: expanded ? 440 : 256, height: expanded ? 410 : 286))
        surface.layoutDetails(NSRect(x: left ? 0 : bodyWidth + 6, y: size.height - cardHeight - 12, width: cardWidth, height: cardHeight))
        panel.keepInsideScreen()
        positionBubble(animateReturn: true)
        onLayout?()
    }
    func selectDisplaySize(_ size: PetDisplaySize) {
        sizeTransition?.invalidate()
        let previous = PetDisplaySize.selected(in: preferences)
        let startScale = surface.frame.width / surface.bounds.width
        let startWidth = surface.detailFrame.width
        let startHeight = surface.detailFrame.height
        preferences.set(size.rawValue, forKey: PetDisplaySize.preferenceKey)
        guard previous != size, panel.isVisible, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            resizeForConstellation(surface.constellation.opened); return
        }
        let height = size.detailHeight(page: messages.page, count: messages.page == "changes" ? messages.changes.count : messages.entries.count)
        let began = ProcessInfo.processInfo.systemUptime
        sizeTransition = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else { timer.invalidate(); return }
                let t = min(1, (ProcessInfo.processInfo.systemUptime - began) / 0.22)
                let eased = t * t * (3 - 2 * t)
                self.resizeForConstellation(self.surface.constellation.opened, interpolated: (
                    startScale + (size.scale - startScale) * eased,
                    startWidth + (size.detailWidth - startWidth) * eased,
                    startHeight + (height - startHeight) * eased))
                self.surface.needsDisplay = true
                if t == 1 { timer.invalidate(); self.sizeTransition = nil }
            }
        }
        RunLoop.main.add(sizeTransition!, forMode: .common)
    }

    func updateAnnouncements(_ service: AnnouncementService) {
        guard demoSession == nil else { return }
        messages.notificationDenied = service.enabled && service.authorization == .denied
        messages.remindersEnabled = service.enabled
        messages.remindersReady = service.remindersReady
        messages.reminderStatus = service.reminderStatusText
        messages.testReminderStatus = service.testReminderStatus
        messages.testingReminder = service.testingReminder
        messages.testReminder = { [weak self, weak service] in
            self?.showTestBubble()
            Task { await service?.sendTestReminder() }
        }
        messages.checkPermission = { [weak service] in Task { await service?.refreshAuthorization() } }
        messages.enableReminders = { [weak service] in Task { await service?.setEnabled(true) } }
        messages.partialSources = service.partialSources
        messages.primarySourceHealthy = service.primarySourceHealthy
        messages.entries = service.entries; messages.failed = service.failed
        messages.checking = service.checking; messages.checkedAt = service.lastSuccess
        messages.refresh = { [weak service] in Task { await service?.check() } }
        if messages.page == "news" { seenMessages.formUnion(service.entries.map { "\($0.id):\($0.revision):\($0.status)" }) }
        messages.unread = !service.failed && service.entries.contains { $0.active(at: Date()) && !seenMessages.contains("\($0.id):\($0.revision):\($0.status)") }
        surface.syncControls()
        surface.constellation.messageHeadline = messages.page == "news" ? messages.headline : messages.page == "changes" ? "额度足迹" : nil
        if surface.constellation.opened { resizeForConstellation(true) }
        surface.needsDisplay = true
        // A known expiry remains authoritative even when the next fetch fails.
        if let pending = preferences.string(forKey: "pet.bubblePending.v1"),
           let cached = service.entries.first(where: { $0.id == pending }),
           !cached.active(at: Date()) {
            preferences.removeObject(forKey: "pet.bubblePending.v1")
            if bubbleEntryID == pending { dismissBubble() }
        }
        if !service.failed && !service.checking {
            if let pending = preferences.string(forKey: "pet.bubblePending.v1"),
               PetBubblePolicy.candidate(service.entries.filter { $0.id == pending }, delivered: [:], now: Date()) == nil {
                preferences.removeObject(forKey: "pet.bubblePending.v1")
                if bubbleEntryID == pending { dismissBubble() }
            }
        }
        if panel.isVisible && messages.page != "news" && !service.failed && !service.checking {
            var delivered = preferences.dictionary(forKey: "pet.bubbleDelivered.v1") as? [String: Int] ?? [:]
            if let entry = PetBubblePolicy.candidate(service.entries.filter { !seenMessages.contains("\($0.id):\($0.revision):\($0.status)") }, delivered: delivered, now: Date()) {
                preferences.set(entry.id, forKey: "pet.bubblePending.v1")
                showBubble(text: PetBubblePolicy.text(entry), id: entry.id)
                // Persist the whole current batch so an older event does not follow a newer one.
                for item in service.entries where item.active(at: Date()) { delivered[item.id] = item.revision }
                preferences.set(delivered, forKey: "pet.bubbleDelivered.v1")
            } else if let id = preferences.string(forKey: "pet.bubblePending.v1"),
                      let entry = PetBubblePolicy.candidate(service.entries.filter { $0.id == id }, delivered: [:], now: Date()),
                      bubble == nil {
                showBubble(text: PetBubblePolicy.text(entry), id: entry.id)
            }
        }
    }
    func showTestBubble() {
        showBubble(text: "这是一条气泡测试，不代表有重置预告。点击可打开消息星盘。", id: nil)
    }
    private func showBubble(text: String, id: String?) {
        dismissBubble()
        let window = FloatingWindow(contentRect: NSRect(x: 0, y: 0, width: 264, height: 142), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.hasShadow = false
        bubbleText = text
        bubble = window; bubbleEntryID = id
        panel.addChildWindow(window, ordered: .above)
        positionBubble(); window.orderFrontRegardless()
    }
    private func positionBubble(animateReturn: Bool = false) {
        guard let bubble else { return }
        let scale = surface.frame.width / surface.bounds.width
        let origin = NSPoint(x: panel.frame.minX + surfaceOffset, y: panel.frame.minY)
        let head = NSPoint(x: origin.x + 128 * scale, y: origin.y + 286 * scale)
        let screen = panel.screen?.visibleFrame ?? NSScreen.main!.visibleFrame
        let detailCard = surface.constellation.opened && messages.page != "quota"
            ? surface.detailFrame.offsetBy(dx: panel.frame.minX, dy: panel.frame.minY) : nil
        let placement = PetBubblePlacement.resolve(head: head, screen: screen, expanded: surface.constellation.opened || surface.constellation.progress > 0, scale: scale, detailCard: detailCard)
        let avoiding = surface.constellation.opened || surface.constellation.progress > 0
        let shouldAnimate = animateReturn && bubbleAvoidingStars && !avoiding
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            && NSEvent.pressedMouseButtons == 0
        bubbleAvoidingStars = avoiding
        bubbleReturnTimer?.invalidate(); bubbleReturnTimer = nil
        if shouldAnimate && bubble.frame.origin != placement.frame.origin {
            let start = bubble.frame.origin
            let target = placement.frame.origin
            let began = ProcessInfo.processInfo.systemUptime
            let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self, weak bubble] timer in
                MainActor.assumeIsolated {
                    guard let self, let bubble, self.bubble === bubble else { timer.invalidate(); return }
                    let t = min(1, (ProcessInfo.processInfo.systemUptime - began) / 0.20)
                    let eased = t * t * (3 - 2 * t)
                    bubble.setFrameOrigin(NSPoint(x: start.x + (target.x - start.x) * eased,
                                                  y: start.y + (target.y - start.y) * eased))
                    if t >= 1 { timer.invalidate(); self.bubbleReturnTimer = nil }
                }
            }
            bubbleReturnTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        } else { bubble.setFrame(placement.frame, display: true) }
        guard bubblePlacement?.tipX != placement.tipX || bubblePlacement?.showsBeads != placement.showsBeads else { return }
        bubblePlacement = placement
        bubble.contentView = NSHostingView(rootView: PetNewsBubble(text: bubbleText, tipX: placement.tipX, showsBeads: placement.showsBeads, open: { [weak self] in
            guard let self else { return }
            let id = self.bubbleEntryID
            self.preferences.removeObject(forKey: "pet.bubblePending.v1")
            self.dismissBubble()
            if let id { self.openAnnouncement(id) }
            else { self.surface.constellation.opened = true; self.selectMessagePage("news"); self.refreshPlayback() }
        }, close: { [weak self] in
            guard let self else { return }
            if self.bubbleEntryID != nil { self.preferences.removeObject(forKey: "pet.bubblePending.v1") }
            self.dismissBubble()
        }))
    }

    private func dismissBubble() {
        bubbleReturnTimer?.invalidate(); bubbleReturnTimer = nil
        bubbleAvoidingStars = false
        if let bubble { panel.removeChildWindow(bubble); bubble.orderOut(nil) }
        bubble = nil; bubbleEntryID = nil; bubblePlacement = nil
    }
    func openAnnouncement(_ id: String) {
        dismissBubble()
        messages.selectedAnnouncementID = id
        surface.constellation.opened = true
        selectMessagePage("news")
        panel.orderFrontRegardless()
        refreshPlayback()
    }
    func selectMessagePage(_ page: String) {
        if page != "news" { messages.selectedAnnouncementID = nil }
        messages.page = page
        if page == "news", demoSession == nil {
            preferences.removeObject(forKey: "pet.bubblePending.v1")
            dismissBubble()
            seenMessages.formUnion(messages.entries.map { "\($0.id):\($0.revision):\($0.status)" })
            messages.unread = false
            if !messages.checking && (messages.checkedAt.map { Date().timeIntervalSince($0) > 300 } ?? true) { messages.refresh?() }
        }
        surface.constellation.messageHeadline = page == "news" ? messages.headline : page == "changes" ? "额度足迹" : nil
        surface.syncControls()
        if surface.constellation.opened { resizeForConstellation(true) }
    }
    func setAllDesktops(_ enabled: Bool) {
        panel.collectionBehavior = enabled ? [.canJoinAllSpaces, .canJoinAllApplications] : [.moveToActiveSpace, .canJoinAllApplications]
    }
    func update(_ newState: PetState, observedAt: Date = Date()) {
        let waitingForNewFrame = ready && newState != lastRenderedState
        if demoSession == nil {
            if !resumingFromDemo || newState.remaining != nil {
                journal.observe(newState, at: observedAt)
                resumingFromDemo = false
            }
            messages.changes = journal.changes
        }
        if surface.constellation.opened && messages.page == "changes" { resizeForConstellation(true) }
        if newState.remaining != nil { messages.quotaUpdatedAt = observedAt }
        state = newState
        surface.constellation.state = newState
        surface.toolTip = newState.label
        surface.label = CommandLine.arguments.contains("--pet-preview")
            ? "阅读 · \(newState.label)" : newState.label
        if waitingForNewFrame { surface.label = "额度更新中…" }
        surface.setAccessibilityLabel(newState.label)
        renderIfNeeded()
    }
    func selectCharacter(_ selected: PetCharacter) {
        guard selected != character else { return }
        let rect = panel.frame
        let allDesktops = panel.collectionBehavior.contains(.canJoinAllSpaces)
        preferences.set([rect.minX + surfaceOffset, rect.minY], forKey: "pet.userOrigin.v1")
        preferences.set(selected.rawValue, forKey: PetCharacter.preferenceKey)
        if let rendered = decodedFrameState, !idleFrames.isEmpty {
            characterFrames[character] = CachedFrames(state: rendered, idle: idleFrames, blink: blinkFrames, turn: turnFrames, reading: readingFrames, hover: hoverFrames, variants: readingVariants)
        }
        // Keep the current silhouette visible until a replacement is decoded.
        // Never order the window out during a role switch.
        surface.prepareCharacterTransition()
        resetRenderer()
        switchingCharacter = true
        character = selected
        surface.constellation.opened = false
        surface.constellation.progress = 0
        selectMessagePage("quota")
        resizeForConstellation(false)
        nextIdleAt = Date().addingTimeInterval(2)
        nextReadingAt = Date().addingTimeInterval(10)
        if let cached = characterFrames[selected], cached.state.remaining == state?.remaining, cached.state.loading == state?.loading {
            idleFrames = cached.idle; blinkFrames = cached.blink
            turnFrames = cached.turn; readingFrames = cached.reading
            hoverFrames = cached.hover; readingVariants = cached.variants
            surface.image = cached.idle.first
            surface.animateCharacterArrival()
            switchingCharacter = false
            lastRenderedState = cached.state
            decodedFrameState = cached.state
        } else {
            surface.label = "正在切换角色…"
        }
        show(near: rect, allDesktops: allDesktops)
    }
    private func loadRenderer() {
        let url: URL?
        #if SWIFT_PACKAGE
        url = Bundle.module.url(forResource: "reader", withExtension: "html", subdirectory: "Pet/\(character.assetDirectory)")
        #else
        url = Bundle.main.url(forResource: "reader", withExtension: "html", subdirectory: "Pet/\(character.assetDirectory)")
        #endif
        guard let url else { fail("Missing bundled pet asset"); return }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.add(self, name: "pet")
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 512, height: 512), configuration: configuration)
        renderer = web; web.navigationDelegate = self
        web.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }
    private func renderIfNeeded() {
        guard ready, !sleeping, !displaySleeping, panel.isVisible, let state, state != lastRenderedState,
              let data = try? JSONEncoder().encode(state), let json = String(data: data, encoding: .utf8) else { return }
        lastRenderedState = state
        let activeRenderer = renderer
        activeRenderer?.evaluateJavaScript("void window.setPetState(\(json))") { [weak self] _, error in
            guard self?.renderer === activeRenderer else { return }
            if let error { self?.lastRenderedState = nil; self?.fail(error.localizedDescription) }
        }
    }
    private func fail(_ message: String) {
        idleWake?.invalidate(); idleWake = nil
        idleTimer?.invalidate(); idleTimer = nil; idleFrames = []; blinkFrames = []; turnFrames = []; readingFrames = []; readingTick = nil; activityTicks = 0; reactionIndex = nil
        lastRenderedState = nil; surface.image = nil; surface.label = "3D 暂不可用 · 点击查看额度"; onFailure?(message)
    }
    @objc private func pauseForSleep() {
        rememberSleepPlacement()
        surface.hintMotionAllowed = false
        sleeping = true; hoverWake?.invalidate(); hoverWake = nil; pointerNear = false; surface.breathingAllowed = false; surface.hintMotionAllowed = false; idleWake?.invalidate(); idleWake = nil; idleTimer?.invalidate(); idleTimer = nil
    }
    @objc private func resumeFromSleep() {
        sleeping = false; nextIdleAt = Date().addingTimeInterval(1.5); nextReadingAt = Date().addingTimeInterval(Double.random(in: 8...12)); recoverSleepPlacement(); refreshPlayback(); renderIfNeeded()
    }
    @objc private func screensChanged() {
        if let saved = connectedPlacement {
            let available = display(matching: saved.screen) != nil
            if !available {
                awaitingReconnect = true
                if sleepPlacement == nil { panel.keepInsideScreen(); positionBubble() }
                return
            }
            if awaitingReconnect {
                awaitingReconnect = false
                sleepPlacement = saved
                resizeForConstellation(surface.constellation.opened)
                recoverSleepPlacement()
                return
            }
        }
        if sleepPlacement == nil { panel.keepInsideScreen(); positionBubble() }
    }
    @objc private func pauseForDisplaySleep() { rememberSleepPlacement(); displaySleeping = true; refreshPlayback() }
    @objc private func resumeDisplay() { displaySleeping = false; recoverSleepPlacement(); refreshPlayback(); renderIfNeeded() }
    // Character-only dwell, never a global mouse monitor. A pass-by does nothing.
    func pointerProximityChanged(_ near: Bool) {
        pointerNear = near
        hoverWake?.invalidate(); hoverWake = nil
        guard near, Date() >= nextHoverAt else { return }
        hoverWake = Timer.scheduledTimer(withTimeInterval: character == .archivist ? 0.35 : 0.55, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.hoverWake = nil
                guard self.pointerNear, !self.sleeping, !self.displaySleeping, self.panel.isVisible,
                      !self.surface.constellation.opened, self.reactionIndex == nil,
                      !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, !self.hoverFrames.isEmpty else { return }
                self.nextHoverAt = Date().addingTimeInterval(self.character == .archivist ? 9 : 14)
                self.activeIdleFrames = self.hoverFrames
                self.activeFrameRate = self.character == .archivist ? 30 : 60
                self.idleReaction = true; self.readingReaction = true; self.reactionElapsed = 0; self.reactionIndex = 0
                self.refreshPlayback()
            }
        }
    }
    @objc private func refreshPlayback() {
        surface.hintMotionAllowed = !sleeping && !displaySleeping && panel.isVisible
        surface.breathingAllowed = surface.hintMotionAllowed && reactionIndex == nil && !surface.constellation.opened
        if sleeping || displaySleeping { hoverWake?.invalidate(); hoverWake = nil; pointerNear = false }
        idleWake?.invalidate(); idleWake = nil
        idleTimer?.invalidate(); idleTimer = nil
        guard !sleeping, !displaySleeping, panel.isVisible, !idleFrames.isEmpty else { return }
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if reduced {
            hoverWake?.invalidate(); hoverWake = nil; openingLead = 0
            surface.image = idleFrames[0]; reactionIndex = nil
            surface.constellation.advance(1, reduced: true);resizeForConstellation(surface.constellation.opened);surface.needsDisplay = true; return
        }
        if !surface.constellation.opened && surface.constellation.progress == 0 { resizeForConstellation(false) }
        guard reactionIndex != nil || surface.constellation.isAnimating else {
            surface.image = idleFrames[0]
            idleWake = Timer.scheduledTimer(withTimeInterval: max(0.1, self.nextIdleAt.timeIntervalSinceNow), repeats: false) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.readingReaction = !self.surface.constellation.opened && Date() >= self.nextReadingAt && !self.readingFrames.isEmpty
                    if self.readingReaction { self.nextReadingAt = Date().addingTimeInterval(Double.random(in: self.character == .archivist ? 9...16 : 16...26)) }
                    if self.readingReaction {
                        let candidates = self.readingVariants.indices.filter { $0 != self.lastReadingVariant }
                        if let selected = candidates.randomElement() {
                            self.lastReadingVariant = selected; self.activeIdleFrames = self.readingVariants[selected]
                        } else { self.activeIdleFrames = self.readingFrames }
                    }
                    else {
                        self.activeIdleFrames = self.blinkFrames
                        if Int.random(in: 0..<8) == 0 {
                            self.activeIdleFrames += Array(repeating: self.idleFrames[0], count: 12) + self.blinkFrames
                        }
                    }
                    self.activeFrameRate = self.character == .archivist ? 30 : (!self.readingReaction ? 60 : 30)
                    self.idleReaction = true;self.reactionElapsed = 0; self.reactionIndex = 0;self.refreshPlayback()
                }
            }
            return
        }
        var lastTick = ProcessInfo.processInfo.systemUptime
        idleTimer = Timer(timeInterval: 1.0/60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.panel.isVisible, !self.idleFrames.isEmpty else { return }
                let now = ProcessInfo.processInfo.systemUptime
                let delta = min(0.1, max(0, now - lastTick)); lastTick = now
                if self.surface.constellation.isAnimating {
                    if self.openingLead > 0 { self.openingLead -= delta }
                    else { self.surface.constellation.advance(delta, reduced: false) }
                }
                let frames = self.idleReaction ? self.activeIdleFrames : self.turnFrames
                if let index = self.reactionIndex, index < frames.count {
                    self.surface.image = frames[index]
                    self.reactionElapsed += delta
                    self.reactionIndex = Int(self.reactionElapsed * self.activeFrameRate)
                } else {
                    if self.reactionIndex != nil {
                        // Schedule once at the end of an action, not on every quota refresh.
                        self.nextIdleAt = Date().addingTimeInterval(Double.random(in: self.readingReaction ? 1.0...1.8 : 2.2...4.8))
                    }
                    self.reactionIndex = nil
                }
                if self.reactionIndex == nil && !self.surface.constellation.isAnimating { self.refreshPlayback() }
            }
        }
        idleTimer?.tolerance = 0.002
        if let idleTimer { RunLoop.main.add(idleTimer, forMode: .common) }
    }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard userContentController === renderer?.configuration.userContentController else { return }
        guard let body = message.body as? [String: Any] else { return }
        if ProcessInfo.processInfo.environment["CODEX_METER_PET_DIAGNOSTICS"] == "1", let phase = body["phase"] as? String { print("Reader: \(phase)") }
        if body["ready"] as? Bool == true { ready = true; renderIfNeeded() }
        if let error = body["error"] as? String { fail(error) }
        guard let frame = body["frame"] as? String, let encodedState = body["state"],
              let json = try? JSONSerialization.data(withJSONObject: encodedState),
              let rendered = try? JSONDecoder().decode(PetState.self, from: json), rendered == state,
              let base64 = frame.split(separator: ",", maxSplits: 1).last,
              let data = Data(base64Encoded: String(base64)), let image = NSImage(data: data) else { return }
        guard !sleeping, !displaySleeping else { lastRenderedState = nil; return }
        if body["preview"] as? Bool == true {
            if switchingCharacter {
                surface.image = image
                // A visible preview is already interactive. Constellation playback
                // must not wait for the remaining character animation frames.
                idleFrames = [image]
                surface.animateCharacterArrival()
                switchingCharacter = false
                refreshPlayback()
            }
            return
        }
        if switchingCharacter {
            surface.image = image
            surface.animateCharacterArrival()
            switchingCharacter = false
        }
        idleTimer?.invalidate()
        let wasPlaying = reactionIndex != nil
        // Keep the active idle clip intact (including double blinks and reversed
        // returns); the new quota frames take over at its natural endpoint.
        // Loops share identical end frames; retain one decoded image for duplicates.
        var decoded: [String: NSImage] = [:]
        func decodeFrames(_ name: String) -> [NSImage] { (body[name] as? [String] ?? []).compactMap { value in
            if let image = decoded[value] { return image }
            guard let encoded = value.split(separator: ",", maxSplits: 1).last,
                  let bytes = Data(base64Encoded: String(encoded)), let image = NSImage(data: bytes) else { return nil }
            decoded[value] = image
            return image
        } }
        idleFrames = decodeFrames("frames")
        decodedFrameState = rendered
        blinkFrames = decodeFrames("blinkFrames")
        turnFrames = decodeFrames("turnFrames")
        readingFrames = decodeFrames("readingFrames")
        hoverFrames = decodeFrames("hoverFrames")
        readingVariants = (body["readingVariants"] as? [[String]] ?? []).map { values in
            values.compactMap { value in decoded[value] ?? { () -> NSImage? in
                guard let encoded = value.split(separator: ",", maxSplits: 1).last,
                      let bytes = Data(base64Encoded: String(encoded)), let image = NSImage(data: bytes) else { return nil }
                decoded[value] = image
                return image
            }() }
        }.filter { !$0.isEmpty }
        readingTick = nil; activityTicks = 0
        idleIndex = 0; surface.label = rendered.label
        if wasPlaying {
            let current = idleReaction ? activeIdleFrames : turnFrames
            let index = Int(reactionElapsed * activeFrameRate)
            if index < current.count { reactionIndex = index; surface.image = current[index] }
            else { reactionIndex = nil; surface.image = image }
        } else { reactionIndex = nil; surface.image = image }
        refreshPlayback()
        onFrame?(data, rendered)
        // Explicit local verification only; contains quota display fields, never credentials.
        if let directory = ProcessInfo.processInfo.environment["CODEX_METER_PET_VERIFY_DIR"], directory.hasPrefix("/") {
            let destination = URL(fileURLWithPath: directory)
            try? data.write(to: destination.appendingPathComponent("rendered-frame.png"), options: .atomic)
            try? JSONEncoder().encode(rendered).write(to: destination.appendingPathComponent("rendered-state.json"), options: .atomic)
        }
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { fail(error.localizedDescription) }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        ready = false; lastRenderedState = nil; surface.label = "3D 正在恢复…"; webView.reload()
    }
    func windowDidMove(_ notification: Notification) {
        if sleepPlacement != nil { positionBubble(); return }
        panel.keepInsideScreen()
        positionBubble()
        onMove?()
    }
    func windowDidChangeScreen(_ notification: Notification) { if sleepPlacement != nil { return }; panel.keepInsideScreen(); positionBubble(); onMove?() }
}

@MainActor
private final class PetSurface: NSView {
    private var arrivalTimer: Timer?
    private var arrivalProgress = 1.0
    private var departingImage: NSImage?
    func prepareCharacterTransition() {
        // Preserve the currently visible identity across interrupted transitions.
        if arrivalProgress >= 0.12 / 0.44 || departingImage == nil { departingImage = image }
        arrivalTimer?.invalidate(); arrivalTimer = nil
        arrivalProgress = 1
    }
    func animateCharacterArrival() {
        arrivalTimer?.invalidate()
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            arrivalProgress = 1; departingImage = nil; needsDisplay = true; return
        }
        arrivalProgress = 0
        let start = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 1.0/60, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else { timer.invalidate(); return }
                self.arrivalProgress = min(1, (ProcessInfo.processInfo.systemUptime - start) / 0.44)
                self.setNeedsDisplay(NSRect(x: 0, y: 20, width: 256, height: 276))
                if self.arrivalProgress >= 1 { timer.invalidate(); self.arrivalTimer = nil; self.departingImage = nil }
            }
        }
        arrivalTimer = timer; RunLoop.main.add(timer, forMode: .common)
    }
    var image: NSImage? { didSet { if oldValue !== image { setNeedsDisplay(NSRect(x: 0, y: 30, width: 256, height: 256)) } } }
    var constellation = PetConstellation() {
        didSet {
            if oldValue.progress == 1 && constellation.progress == 1 && oldValue.opened == constellation.opened {
                setNeedsDisplay(NSRect(x: 185, y: 210, width: 250, height: 200))
            } else { needsDisplay = true }
            if oldValue.ambientTime != constellation.ambientTime { syncTwinkle() }
            else { syncControls() }
        }
    }
    private func syncTwinkle() {
        for (index, button) in pageButtons.enumerated() {
            (button as? PetOrbitButton)?.twinkle = 0.5 + 0.5*sin(constellation.ambientTime * (1.4 + Double(index)*0.17) + Double(index)*2.1)
        }
    }
    private var ambientTimer: Timer?
    private var messageHost: NSHostingView<PetMessageView>?
    private var messageModel: PetMessageModel?
    private var pageButtons: [NSButton] = []
    private let idleHint = PetIdleHint(frame: NSRect(x: 199, y: 209, width: 28, height: 28))
    var hintMotionAllowed = true { didSet { syncControls() } }
    var selectPage: ((String) -> Void)?
    func installMessages(_ model: PetMessageModel) {
        messageModel = model
        addSubview(idleHint)
        let host = NSHostingView(rootView: PetMessageView(model: model))
        host.frame = NSRect(x: 438, y: 24, width: 286, height: 366)
        messageHost = host; addSubview(host)
        for (index, title) in ["额度", "消息", "变化"].enumerated() {
            let button = PetOrbitButton(title: title, target: self, action: #selector(pagePressed(_:)))
            button.tag = index; button.isBordered = false
            button.contentTintColor = NSColor(calibratedRed: 0.95, green: 0.84, blue: 0.63, alpha: 1)
            button.font = .systemFont(ofSize: 12, weight: .medium)
            button.labelAbove = index == 1
            let point = PetOrbitMotion.star(index)
            button.frame = NSRect(x: point.x-34, y: point.y-(index == 1 ? 18 : 34), width: 68, height: 54)
            button.setAccessibilityLabel(title)
            button.toolTip = "查看" + title
            addSubview(button); pageButtons.append(button)
        }
        syncControls()
    }
    @objc private func pagePressed(_ sender: NSButton) { selectPage?(["quota", "news", "changes"][sender.tag]) }
    private func syncAmbientMotion() {
        let active = hintMotionAllowed && (breathingAllowed || (constellation.opened && constellation.progress >= 0.99)) && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if !active {
            ambientTimer?.invalidate(); ambientTimer = nil
            return
        }
        guard ambientTimer == nil else { return }
        var lastTick = ProcessInfo.processInfo.systemUptime
        ambientTimer = Timer(timeInterval: 1.0/15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let now = ProcessInfo.processInfo.systemUptime
                self.constellation.ambientTime += min(0.1, max(0, now-lastTick)); lastTick = now
                if self.breathingAllowed { self.setNeedsDisplay(NSRect(x: 0, y: 30, width: 256, height: 256)) }
            }
        }
        ambientTimer?.tolerance = 0.01
        if let ambientTimer { RunLoop.main.add(ambientTimer, forMode: .common) }
    }
    func syncControls() {
        syncAmbientMotion()
        idleHint.update(visible: constellation.progress == 0 && !constellation.opened && messageModel?.unread == true, moving: hintMotionAllowed && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        let visible = constellation.opened && constellation.progress > 0.92
        let motion = PetOrbitMotion(progress: constellation.progress)
        for (index, button) in pageButtons.enumerated() {
            guard let star = button as? PetOrbitButton else { continue }
            let point = motion.position(PetOrbitMotion.star(index, progress: constellation.progress))
            star.frame = NSRect(x: point.x-34*motion.scale, y: point.y-(index == 1 ? 18 : 34)*motion.scale, width: 68*motion.scale, height: 54*motion.scale)
            star.setBoundsSize(NSSize(width: 68, height: 54))
            star.alphaValue = motion.eased
            star.isHidden = constellation.progress == 0
            star.isEnabled = constellation.opened && constellation.progress >= 0.99
            star.twinkle = hintMotionAllowed && constellation.opened && constellation.progress >= 0.99 && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                ? 0.5 + 0.5*sin(constellation.ambientTime * (1.4 + Double(index)*0.17) + Double(index)*2.1) : 0.5
            star.selected = messageModel?.page == ["quota", "news", "changes"][index]
            star.unread = index == 1 && messageModel?.unread == true
        }
        messageHost?.isHidden = !visible || messageModel?.page == "quota"
    }
    func moveDetails(to parent: NSView) {
        if let host = messageHost { host.removeFromSuperview(); parent.addSubview(host) }
    }
    var detailFrame: NSRect { messageHost?.frame ?? .zero }
    func layoutDetails(_ rect: NSRect) { messageHost?.frame = rect }
    /// Ideal card height at the given width, measured from the live model so
    /// the window never clips the fixed content above the scrolling list.
    func detailsFittingHeight(_ width: CGFloat) -> CGFloat {
        guard let model = messageModel else { return 0 }
        let host = NSHostingView(rootView: PetMessageView(model: model).frame(width: width))
        return host.fittingSize.height
    }
    var label = "正在加载桌宠…" { didSet { needsDisplay = true } }
    var breathingAllowed = false { didSet { syncAmbientMotion() } }
    var hoverChanged: ((Bool) -> Void)?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect: NSRect(x: 64, y: 40, width: 128, height: 240), options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil))
    }
    override func mouseEntered(with event: NSEvent) { hoverChanged?(true) }
    override func mouseExited(with event: NSEvent) { hoverChanged?(false) }
    var clicked: (() -> Void)?
    var dragEnded: (() -> Void)?
    private var previous: NSPoint?
    private var start: NSPoint?
    private var dragged = false
    override var isOpaque: Bool { false }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        let characterRect = NSRect(x: 0, y: 30, width: 256, height: 256)
        if needsToDraw(characterRect) {
            // Less than half a point, feet anchored; no idle bouncing or walking.
            let breath = breathingAllowed && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0.35 * (0.5 + 0.5*sin(constellation.ambientTime*1.35)) : 0
            let elapsed = arrivalProgress * 0.44
            let departing = elapsed < 0.12 && departingImage != nil
            let t = departing ? elapsed / 0.12 : min(1, max(0, (elapsed - 0.12) / 0.32))
            let bounce = departing ? -0.035*t : (t < 1 ? -0.035 * exp(-5*t) * cos(3 * .pi * t) : 0)
            let width = 256 * (1 - bounce * 0.45)
            let opacity = departing ? 1-t*t : min(1, t*4)
            (departing ? departingImage : image)?.draw(in: NSRect(x: (256-width)/2, y: 30, width: width, height: (256 + breath) * (1 + bounce)), from: .zero, operation: .sourceOver, fraction: opacity)

        }
        if image == nil {
            (label as NSString).draw(in: NSRect(x: 45, y: 150, width: 180, height: 50), withAttributes: [.font:NSFont.systemFont(ofSize:12),.foregroundColor:NSColor.secondaryLabelColor])
        }
        if needsToDraw(NSRect(x: 170, y: 150, width: 270, height: 260)) { constellation.draw() }
    }
    private func screenPoint(_ event: NSEvent) -> NSPoint {
        window?.convertPoint(toScreen: event.locationInWindow) ?? event.locationInWindow
    }
    override func mouseDown(with event: NSEvent) { hoverChanged?(false); previous = screenPoint(event); start = previous; dragged = false }
    override func mouseDragged(with event: NSEvent) {
        let current = screenPoint(event)
        guard let window, let previous, let start else { return }
        if petGestureIsDrag(from: start, to: current) { dragged = true }
        if dragged, let screen = NSScreen.screens.first(where: { $0.frame.contains(current) }) ?? window.screen {
            window.setFrame(floatingDragFrame(window.frame, from: previous, to: current, visibleFrame: screen.visibleFrame), display: true)
        }
        self.previous = current
    }
    override func mouseUp(with event: NSEvent) {
        let moved = start.map { petGestureIsDrag(from: $0, to: screenPoint(event)) } ?? true
        if dragged { dragEnded?() }
        if !dragged && !moved { clicked?() }
        previous = nil; start = nil
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 && constellation.opened { clicked?() }
        else if event.keyCode == 36 || event.keyCode == 49 { clicked?() } else { super.keyDown(with: event) }
    }
    override func accessibilityPerformPress() -> Bool { clicked?(); return true }
}

func petGestureIsDrag(from start: NSPoint, to end: NSPoint) -> Bool {
    hypot(end.x-start.x, end.y-start.y) > 4
}


/// Fixed orbital targets: the visible star is small, its native hit area is 68 × 54 pt.
@MainActor private final class PetOrbitButton: NSButton {
    override var isFlipped: Bool { false }
    var twinkle: Double = 0.5 { didSet { if oldValue != twinkle { needsDisplay = true } } }
    var labelAbove = false
    var selected = false { didSet { if oldValue != selected { needsDisplay = true } } }
    var unread = false { didSet {
        if oldValue != unread {
            needsDisplay = true
            if unread && !isHidden && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                alphaValue = 0.65
                NSAnimationContext.runAnimationGroup { context in context.duration = 0.8; animator().alphaValue = 1 }
            }
        }
    } }
    private var hovered = false
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }
    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        let center = NSPoint(x: 34, y: labelAbove ? 18 : 34)
        let gold = NSColor(calibratedRed: 0.98, green: 0.86, blue: 0.6, alpha: 1)
        let bright = selected || hovered || isHighlighted || unread
        if let context = NSGraphicsContext.current?.cgContext,
           let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [gold.withAlphaComponent((bright ? 0.22 : 0.12) + twinkle*0.25).cgColor, gold.withAlphaComponent(0).cgColor] as CFArray, locations: [0, 1]) {
            context.saveGState()
            context.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: (bright ? 15 : 11) + twinkle*4, options: [])
            context.restoreGState()
        }
        NSColor(calibratedRed: 0.17, green: 0.11, blue: 0.25, alpha: 0.95).setFill()
        NSBezierPath(ovalIn: NSRect(x: center.x-7, y: center.y-7, width: 14, height: 14)).fill()
        let star = NSBezierPath(), radius: CGFloat = bright ? 8 : 6
        for i in 0..<8 {
            let angle = CGFloat(i) * .pi/4
            let r = i % 2 == 0 ? radius : 2
            let point = NSPoint(x: center.x + sin(angle)*r, y: center.y + cos(angle)*r)
            if i == 0 { star.move(to: point) } else { star.line(to: point) }
        }
        star.close(); gold.withAlphaComponent((bright ? 0.82 : 0.65) + twinkle*0.18).setFill(); star.fill()
        if selected || window?.firstResponder === self {
            gold.withAlphaComponent(selected ? 1 : 0.7).setStroke()
            let orbit = NSBezierPath(ovalIn: NSRect(x: center.x-11, y: center.y-11, width: 22, height: 22));orbit.lineWidth = selected ? 1.8 : 0.7;orbit.stroke()
        }
        let label = NSRect(x: 11, y: labelAbove ? 36 : 2, width: 46, height: 17)
        let purple = NSColor(calibratedRed: 0.17, green: 0.11, blue: 0.25, alpha: 1)
        (selected ? gold : purple.withAlphaComponent(0.9)).setFill()
        NSBezierPath(roundedRect: label, xRadius: 8, yRadius: 8).fill()
        let style = NSMutableParagraphStyle();style.alignment = .center
        (title as NSString).draw(in: label, withAttributes: [.font: NSFont.systemFont(ofSize: 11, weight: selected ? .semibold : .regular), .foregroundColor: selected ? purple : gold, .paragraphStyle: style])
    }
}

/// A compositor-only unread hint; it never starts the actor frame timer or captures clicks.
@MainActor
private final class PetIdleHint: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    func update(visible: Bool, moving: Bool) {
        isHidden = !visible
        guard visible && moving else { layer?.removeAllAnimations(); return }
        guard layer?.animation(forKey: "idleFloat") == nil else { return }
        let float = CABasicAnimation(keyPath: "transform.translation.y")
        float.fromValue = -2.0; float.toValue = 2.0
        float.duration = 1.8; float.autoreverses = true; float.repeatCount = .infinity
        float.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer?.add(float, forKey: "idleFloat")
        let glow = CABasicAnimation(keyPath: "opacity")
        glow.fromValue = 0.58; glow.toValue = 1.0
        glow.duration = 1.8; glow.autoreverses = true; glow.repeatCount = .infinity
        glow.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer?.add(glow, forKey: "idleGlow")
    }
    override func draw(_ dirtyRect: NSRect) {
        ("✦" as NSString).draw(at: NSPoint(x: 5, y: 4), withAttributes: [.font: NSFont.systemFont(ofSize: 16), .foregroundColor: NSColor.systemYellow])
    }
}

func savedPetOrigin(_ values: [Double]?) -> NSPoint? {
    guard let values, values.count == 2, values.allSatisfy({ $0.isFinite }) else { return nil }
    return NSPoint(x: values[0], y: values[1])
}


// Small premultiplied thumbnails match interrupted poses without restarting a clip.
func closestPetPose(_ current: NSImage?, in candidates: [NSImage]) -> Int {
    func thumbnail(_ image: NSImage) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 24 * 24 * 4)
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return bytes }
        bytes.withUnsafeMutableBytes { buffer in
            if let context = CGContext(data: buffer.baseAddress, width: 24, height: 24, bitsPerComponent: 8, bytesPerRow: 96,
                                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
                context.draw(cg, in: CGRect(x: 0, y: 0, width: 24, height: 24))
            }
        }
        return bytes
    }
    guard let current, !candidates.isEmpty else { return 0 }
    let source = thumbnail(current)
    return candidates.indices.min { a, b in
        func distance(_ index: Int) -> Int {
            zip(source, thumbnail(candidates[index])).reduce(0) { sum, pair in
                let d = Int(pair.0) - Int(pair.1); return sum + d*d
            }
        }
        return distance(a) < distance(b)
    } ?? 0
}
