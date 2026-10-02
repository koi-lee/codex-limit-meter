import AppKit

/// Book-anchored quota constellation. Shares the pet's view and drag coordinate space.
@MainActor
struct PetConstellation {
    var ambientTime: Double = 0
    var opened = false
    var progress: Double = 0
    var state: PetState?
    var messageHeadline: String?
    var isAnimating: Bool { opened ? progress < 1 : progress > 0 }
    mutating func advance(_ dt: Double, reduced: Bool) {
        if reduced { progress = opened ? 1 : 0; return }
        progress = min(1, max(0, progress + (opened ? dt / 0.72 : -dt / 0.36)))
    }
    var bounds: NSRect { NSRect(x: 222, y: 220, width: 190, height: 174) }
    func draw() {
        guard progress > 0 else { return }
        func glow(_ rect: NSRect, _ color: NSColor) {
            guard let context = NSGraphicsContext.current?.cgContext,
                  let rgb = color.usingColorSpace(.deviceRGB),
                  let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [rgb.cgColor, rgb.withAlphaComponent(rgb.alphaComponent * 0.8).cgColor, rgb.withAlphaComponent(0).cgColor] as CFArray, locations: [0, 0.62, 1]) else { return }
            context.saveGState()
            context.translateBy(x: rect.midX, y: rect.midY)
            context.scaleBy(x: rect.width / 2, y: rect.height / 2)
            context.drawRadialGradient(gradient, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: 1, options: [])
            context.restoreGState()
        }
        let p = progress, motion = PetOrbitMotion(progress: progress), eased = motion.eased
        let center = NSPoint(x: 308, y: 300)
        let origin = NSPoint(x: 181, y: 182)
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion && p < 1 {
            drawBookSmoke(phase: p * 1.3, origin: origin)
        }
        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: motion.center.x, yBy: motion.center.y)
        transform.rotate(byRadians: motion.rotation)
        transform.scale(by: motion.scale)
        transform.translateX(by: -308, yBy: -300)
        transform.concat()
        let opacity=CGFloat(eased)
        glow(bounds.insetBy(dx:-9,dy:-9), NSColor(calibratedRed:0.16,green:0.10,blue:0.22,alpha:opacity*0.9))
        // Soft drifting lobes stay behind the stable labels and inside the orbit.
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(ovalIn: NSRect(x:213,y:238,width:190,height:124)).addClip()
        for i in 0..<5 {
            let phase=ambientTime * 0.22 + Double(i)*1.7
            let x=308 + cos(phase)*46, y=300 + sin(phase*0.83)*28
            glow(NSRect(x:x-49,y:y-28,width:98,height:56),
                 NSColor(calibratedRed:0.43,green:0.27,blue:0.63,alpha:opacity*(0.09+0.035*sin(phase+1))))
        }
        NSGraphicsContext.restoreGraphicsState()
        NSGraphicsContext.saveGraphicsState()
        let orbit = NSAffineTransform()
        orbit.translateX(by: center.x, yBy: center.y)
        orbit.rotate(byRadians: 0.12)
        orbit.concat()
        NSColor(calibratedRed:0.86,green:0.73,blue:0.50,alpha:opacity*0.65).setStroke()
        let ring = NSBezierPath(ovalIn:NSRect(x:-103,y:-69,width:206,height:138))
        ring.lineWidth=0.7; ring.stroke()
        NSColor(calibratedRed:0.65,green:0.49,blue:0.85,alpha:opacity*0.25).setStroke()
        let outer = NSBezierPath(ovalIn:NSRect(x:-111,y:-74,width:222,height:148))
        outer.lineWidth=0.7; outer.stroke()
        for i in 0..<36 {
            let angle=Double(i)*Double.pi/18
            let tick=NSBezierPath()
            tick.move(to:NSPoint(x:cos(angle)*103,y:sin(angle)*69))
            tick.line(to:NSPoint(x:cos(angle)*107,y:sin(angle)*72))
            tick.lineWidth=0.7; tick.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()
        for i in 0..<65 {
            let angle=Double(i)*2.399+eased*0.52
            let radius=85+random(Double(i+45))*20
            let x=center.x+cos(angle)*radius, y=center.y+sin(angle)*radius*0.76
            let size=random(Double(i+2))*1.1+0.25
            NSColor(calibratedRed:0.925,green:0.804,blue:0.592,alpha:opacity*(0.15+random(Double(i+3))*0.55)).setFill()
            NSBezierPath(ovalIn:NSRect(x:x-size,y:y-size,width:size*2,height:size*2)).fill()
        }
        func text(_ value:String,_ rect:NSRect,_ size:CGFloat,_ color:NSColor) {
            let style=NSMutableParagraphStyle();style.alignment = .center
            let shadow=NSShadow();shadow.shadowColor=NSColor.black.withAlphaComponent(0.8);shadow.shadowBlurRadius=3;shadow.shadowOffset=NSSize(width:0,height:-1)
            (value as NSString).draw(in:rect,withAttributes:[.font:NSFont.systemFont(ofSize:size,weight:.medium),.foregroundColor:color.withAlphaComponent(opacity),.paragraphStyle:style,.shadow:shadow])
        }
        text(state?.isDemo == true ? "示例数据 · Demo" : messageHeadline != nil ? (messageHeadline == "额度足迹" ? "变化星盘" : "消息星盘") : state?.loading == true ? "读取中…" : "周额度剩余",NSRect(x:230,y:330,width:156,height:20),12,.init(calibratedRed:0.87,green:0.79,blue:0.94,alpha:1))
        text(messageHeadline ?? state?.remaining.map { "\($0)%" } ?? "未知",NSRect(x:230,y:283,width:156,height:44),32,.init(calibratedRed:0.97,green:0.87,blue:0.67,alpha:1))
        let reset: String
        if let timestamp=state?.resetsAt {
            let hours=max(0,Int((Double(timestamp)-Date().timeIntervalSince1970)/3600))
            reset=hours>=24 ? "\(hours/24)天\(hours%24)小时后恢复" : hours>0 ? "\(hours)小时后恢复" : "即将恢复"
        } else { reset="恢复时间未知" }
        text(messageHeadline != nil ? "来源与进展 →" : reset,NSRect(x:225,y:265,width:166,height:19),11,.init(calibratedRed:0.86,green:0.77,blue:0.9,alpha:1))
        
        NSGraphicsContext.restoreGraphicsState()
    }
    // Port of book-nebula-preview-v9: deterministic advected density field.
    private func random(_ i: Double) -> Double {
        let value=sin(i*127.1+311.7)*43758.5453
        return value-floor(value)
    }
    private func noise(_ x: Double, _ y: Double) -> Double {
        let i=floor(x), j=floor(y)
        let dx=x-i, dy=y-j
        let u=dx*dx*(3-2*dx), v=dy*dy*(3-2*dy)
        func hash(_ a:Double,_ b:Double)->Double { random(a*17+b*131) }
        return (hash(i,j)*(1-u)+hash(i+1,j)*u)*(1-v)+(hash(i,j+1)*(1-u)+hash(i+1,j+1)*u)*v
    }
    private func cloud(_ x:Double,_ y:Double)->Double {
        noise(x,y)*0.58+noise(x*2.1+8,y*2.1)*0.28+noise(x*4.2,y*4.2+4)*0.14
    }
    private func drawBookSmoke(phase:Double, origin:NSPoint) {
        let plume=min(1,phase), smoke=sin(Double.pi*min(1,phase/1.3))
        let width=144, height=92
        var pixels=[UInt8](repeating:0,count:width*height*4)
        for y in 0..<height { for x in 0..<width {
            let X=438+Double(x), Y=204+Double(y), u=(278-Y)/62
            guard u>=0 && u<=1 && plume*1.5-u*0.42>=0 else { continue }
            let center=466+67*u+sin(u*7-plume*3)*8*u
            let spread=5+31*u*u
            let n=cloud(Double(x)*0.09+plume*1.7,Double(y)*0.085-plume*3.8)
            let warp=(cloud(Double(x)*0.045+4,Double(y)*0.055-plume*2)-0.5)*24*u
            let d=(X-center+warp)/spread
            let envelope=exp(-d*d*1.6)*sin(Double.pi*u)*smoke
            let density=max(0,n-0.27)*envelope
            let shade=cloud(Double(x)*0.06+7,Double(y)*0.07-plume*2)
            let i=(y*width+x)*4
            pixels[i]=UInt8(174+shade*35); pixels[i+1]=UInt8(145+shade*28)
            pixels[i+2]=UInt8(201+shade*35); pixels[i+3]=UInt8(min(165,density*400))
        }}
        guard let provider=CGDataProvider(data:Data(pixels) as CFData),
              let cg=CGImage(width:width,height:height,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.last.rawValue),provider:provider,decode:nil,shouldInterpolate:true,intent:.defaultIntent) else { return }
        // Convert the reference's top-down canvas coordinates to AppKit's bottom-up space.
        NSImage(cgImage:cg,size:NSSize(width:width,height:height)).draw(in:NSRect(x:origin.x-28,y:origin.y-18,width:144,height:92))
    }

}


/// Shared by the painted constellation and native star targets, including interrupted closing.
struct PetOrbitMotion {
    let eased: Double
    init(progress: Double) {
        let p = min(1, max(0, progress))
        eased = p*p*p*(p*(p*6-15)+10)
    }
    var scale: CGFloat { 0.55 + 0.45 * eased }
    var rotation: CGFloat { -0.32 * (1-eased) }
    var center: NSPoint { NSPoint(x: 308-55*(1-eased), y: 300-65*(1-eased)) }
    func position(_ point: NSPoint) -> NSPoint {
        let x = (point.x-308)*scale, y = (point.y-300)*scale
        return NSPoint(x: center.x+x*cos(rotation)-y*sin(rotation), y: center.y+x*sin(rotation)+y*cos(rotation))
    }
    static func star(_ index: Int, progress: Double = 1) -> NSPoint {
        let travel = 1.6 * (1-PetOrbitMotion(progress: progress).eased)
        let angle = [225.0, 60.0, 335.0][index] * Double.pi / 180 - travel
        let x = cos(angle)*103, y = sin(angle)*69
        return NSPoint(x: 308+x*cos(0.12)-y*sin(0.12), y: 300+x*sin(0.12)+y*cos(0.12))
    }
}
