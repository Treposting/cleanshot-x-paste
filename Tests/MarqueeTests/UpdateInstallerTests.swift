import XCTest
@testable import Marquee

final class UpdateInstallerTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        // Spaces and an apostrophe, like "Nahid's Mac", are where shell quoting breaks.
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("Marquee update test's folder \(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeApp(_ name: String, version: String) throws -> URL {
        let app = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        try version.write(to: app.appendingPathComponent("version"), atomically: true, encoding: .utf8)
        return app
    }

    private func run(_ script: String) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    private func version(at app: URL) throws -> String {
        try String(contentsOf: app.appendingPathComponent("version"), encoding: .utf8)
    }

    func testReplacesAnExistingCopy() throws {
        let installed = try makeApp("Applications's/Marquee.app", version: "old")
        let staged = try makeApp("staged update/Marquee.app", version: "new")
        XCTAssertEqual(try run(UpdateInstaller.swapScript(destination: installed, staged: staged)), 0)
        XCTAssertEqual(try version(at: installed), "new")
        XCTAssertFalse(FileManager.default.fileExists(atPath: installed.path + ".previous"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: staged.path))
    }

    func testInstallsWhereNoCopyExistsYet() throws {
        // Opened from the disk image: nothing in Applications yet.
        let folder = root.appendingPathComponent("Applications")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appendingPathComponent("Marquee.app")
        let staged = try makeApp("staged/Marquee.app", version: "new")
        XCTAssertEqual(try run(UpdateInstaller.swapScript(destination: destination, staged: staged)), 0)
        XCTAssertEqual(try version(at: destination), "new")
    }

    func testQuotingSurvivesApostrophes() {
        XCTAssertEqual(UpdateInstaller.quoted("Nahid's Mac"), "'Nahid'\\''s Mac'")
    }

    func testWaitsForProcessesToExit() throws {
        let sleeper = Process()
        sleeper.executableURL = URL(fileURLWithPath: "/bin/sleep")
        sleeper.arguments = ["0.6"]
        try sleeper.run()
        let start = Date()
        XCTAssertEqual(try run(UpdateInstaller.waitScript(for: [sleeper.processIdentifier])), 0)
        XCTAssertGreaterThan(Date().timeIntervalSince(start), 0.4, "waited for the process to quit")
        XCTAssertFalse(sleeper.isRunning)
    }

    func testDiskImageAndTranslocatedCopiesInstallToApplications() {
        let translocated = URL(fileURLWithPath: "/private/var/folders/x/AppTranslocation/ABC/d/Marquee.app")
        XCTAssertEqual(UpdateInstaller.installDestination(for: translocated).path, "/Applications/Marquee.app")
        let normal = FileManager.default.temporaryDirectory.appendingPathComponent("Marquee.app")
        XCTAssertEqual(UpdateInstaller.installDestination(for: normal), normal)
    }

    func testAdminPromptScriptCompiles() throws {
        let script = root.appendingPathComponent("Nahid's \"update\"/install.sh")
        let source = UpdateInstaller.adminAppleScript(running: script)
        let compiled = root.appendingPathComponent("check.scpt")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osacompile")
        process.arguments = ["-o", compiled.path, "-e", source]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, source)
    }
}
