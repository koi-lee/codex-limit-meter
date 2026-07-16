import Foundation
import Testing
@testable import CodexLimitMeter

@Test func detectsAppsRunningFromMountedDiskImages() {
    #expect(isRunningFromMountedDiskImage(bundlePath: "/Volumes/Codex Limit Meter/CodexLimitMeter.app"))
    #expect(isRunningFromMountedDiskImage(bundlePath: "/Volumes/Codex Limit Meter 1/CodexLimitMeter.app"))
    #expect(!isRunningFromMountedDiskImage(bundlePath: "/Applications/CodexLimitMeter.app"))
}

@Test func findsCodexBundledWithChatGPTApp() throws {
    let temporaryHome = try makeTemporaryHome()
    defer { try? FileManager.default.removeItem(at: temporaryHome) }

    let applications = temporaryHome.appendingPathComponent("Applications", isDirectory: true)
    let binary = applications.appendingPathComponent("ChatGPT.app/Contents/Resources/codex")
    try createFile(at: binary)

    #expect(
        locateCodexBinary(
            homeDirectory: temporaryHome.path,
            environmentPath: "",
            applicationDirectories: [applications.path],
            systemBinaryPaths: []
        ) == binary.path
    )
}

@Test func findsCodexInstalledByNVM() throws {
    let temporaryHome = try makeTemporaryHome()
    defer { try? FileManager.default.removeItem(at: temporaryHome) }

    let binary = temporaryHome.appendingPathComponent(".nvm/versions/node/v22.0.0/bin/codex")
    try createFile(at: binary)

    #expect(
        locateCodexBinary(
            homeDirectory: temporaryHome.path,
            environmentPath: "",
            applicationDirectories: [],
            systemBinaryPaths: []
        ) == binary.path
    )
}

@Test func findsCodexBundledWithVSCodeExtension() throws {
    let temporaryHome = try makeTemporaryHome()
    defer { try? FileManager.default.removeItem(at: temporaryHome) }

    let binary = temporaryHome.appendingPathComponent(
        ".vscode/extensions/openai.chatgpt-1.2.3-darwin-arm64/bin/macos-aarch64/codex"
    )
    try createFile(at: binary)

    #expect(
        locateCodexBinary(
            homeDirectory: temporaryHome.path,
            environmentPath: "",
            applicationDirectories: [],
            systemBinaryPaths: []
        ) == binary.path
    )
}

private func makeTemporaryHome() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func createFile(at url: URL) throws {
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    #expect(FileManager.default.createFile(atPath: url.path, contents: Data()))
}
