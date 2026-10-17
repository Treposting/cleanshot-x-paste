import AppKit
import Security

enum UpdateError: LocalizedError {
    case badResponse
    case noDownload
    case downloadFailed
    case unpackFailed
    case wrongApp
    case badSignature
    case cannotStartInstaller

    var errorDescription: String? {
        switch self {
        case .badResponse: return "GitHub didn't return release information. Check your connection and try again."
        case .noDownload: return "This release has no in-app update file. Download it from the releases page instead."
        case .downloadFailed: return "The download didn't finish. Check your connection and try again."
        case .unpackFailed: return "The downloaded update couldn't be unpacked."
        case .wrongApp: return "The downloaded file isn't the expected Marquee version, so it wasn't installed."
        case .badSignature: return "The update's code signature didn't verify, so it wasn't installed."
        case .cannotStartInstaller:
            return "Marquee couldn't start installing the update. Download it from the releases page instead."
        }
    }
}

/// Downloads a file with progress. URLSession keeps its delegate alive until the task ends.
final class UpdateDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private var continuation: CheckedContinuation<URL, Error>?
    private let onProgress: @Sendable (Double) -> Void

    private init(onProgress: @escaping @Sendable (Double) -> Void) {
        self.onProgress = onProgress
    }

    static func download(_ url: URL, onProgress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let downloader = UpdateDownloader(onProgress: onProgress)
        let session = URLSession(configuration: .ephemeral, delegate: downloader, delegateQueue: nil)
        return try await withCheckedThrowingContinuation { continuation in
            downloader.continuation = continuation
            session.downloadTask(with: url).resume()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        onProgress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        defer { session.finishTasksAndInvalidate() }
        guard let continuation else { return }
        self.continuation = nil
        guard (downloadTask.response as? HTTPURLResponse)?.statusCode == 200 else {
            continuation.resume(throwing: UpdateError.downloadFailed)
            return
        }
        // The system deletes `location` when this method returns, so move it first.
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("Marquee-update-\(UUID().uuidString).zip")
        do {
            try FileManager.default.moveItem(at: location, to: destination)
            continuation.resume(returning: destination)
        } catch {
            continuation.resume(throwing: UpdateError.downloadFailed)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(throwing: error ?? UpdateError.downloadFailed)
        session.finishTasksAndInvalidate()
    }
}

/// Unpacks, verifies and installs a downloaded update.
enum UpdateInstaller {
    /// Unzips the update and checks it before anything is replaced. Returns the staged app.
    static func stage(zip: URL, expectedVersion: AppVersion?) async throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Marquee-update-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try await run("/usr/bin/ditto", ["-x", "-k", zip.path, directory.path])
        try? FileManager.default.removeItem(at: zip)

        let app = directory.appendingPathComponent("Marquee.app")
        guard let bundle = Bundle(url: app),
              bundle.bundleIdentifier == Bundle.main.bundleIdentifier else {
            throw UpdateError.wrongApp
        }
        if let expectedVersion {
            let version = AppVersion(bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
            guard version == expectedVersion else { throw UpdateError.wrongApp }
        }
        try verifySignature(of: app)
        return app
    }

    /// Starts a small helper that waits for every running copy of Marquee to quit, puts the new
    /// version in place and opens it. The caller quits the app right after this returns.
    ///
    /// The update goes where Marquee runs now. When that can't be written (opened from the disk
    /// image, or a translocated copy), it goes to /Applications instead. When the folder needs
    /// an administrator (a standard account), macOS asks for a password.
    @MainActor
    static func replaceAndRelaunch(with staged: URL) throws {
        let current = Bundle.main.bundleURL
        let destination = installDestination(for: current)
        let needsAdmin = !FileManager.default.isWritableFile(atPath: destination.deletingLastPathComponent().path)
        let pids = [ProcessInfo.processInfo.processIdentifier] + quitOtherCopies()

        let swap = swapScript(destination: destination, staged: staged)
        let folder = staged.deletingLastPathComponent()
        let swapScript = folder.appendingPathComponent("install.sh")
        try swap.write(to: swapScript, atomically: true, encoding: .utf8)

        // The swap runs as the user, or through the administrator prompt; opening the app
        // always runs as the user.
        let runSwap = needsAdmin
            ? "/usr/bin/osascript -e \(quoted(adminAppleScript(running: swapScript)))"
            : "/bin/sh \(quoted(swapScript.path))"
        let helper = """
        \(waitScript(for: pids))
        \(runSwap)
        if [ -d \(quoted(destination.path)) ]; then
          /usr/bin/open \(quoted(destination.path))
        else
          /usr/bin/open \(quoted(current.path))
        fi
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", helper]
        do {
            try process.run()
        } catch {
            throw UpdateError.cannotStartInstaller
        }
    }

    /// Shell script that puts `staged` at `destination`, keeping the old copy until the new one
    /// is in place and restoring it if the move fails.
    static func swapScript(destination: URL, staged: URL) -> String {
        """
        OLD=\(quoted(destination.path))
        NEW=\(quoted(staged.path))
        /bin/rm -rf "$OLD.previous"
        if [ -e "$OLD" ]; then
          if /bin/mv "$OLD" "$OLD.previous" && /bin/mv "$NEW" "$OLD"; then
            /bin/rm -rf "$OLD.previous"
          elif [ -d "$OLD.previous" ] && [ ! -d "$OLD" ]; then
            /bin/mv "$OLD.previous" "$OLD"
          fi
        else
          /bin/mv "$NEW" "$OLD"
        fi
        /usr/bin/xattr -dr com.apple.quarantine "$OLD" 2>/dev/null
        exit 0
        """
    }

    /// Where the new version goes: the running copy's place, unless that can't be replaced.
    static func installDestination(for current: URL) -> URL {
        let readOnly = (try? current.resourceValues(forKeys: [.volumeIsReadOnlyKey]).volumeIsReadOnly) ?? false
        if current.path.contains("/AppTranslocation/") || readOnly {
            return URL(fileURLWithPath: "/Applications/Marquee.app")
        }
        return current
    }

    /// Asks every other running copy of Marquee (another build, a copy elsewhere) to quit, so
    /// the new version opens instead of macOS bringing an old copy forward. Returns their PIDs.
    @MainActor
    static func quitOtherCopies() -> [pid_t] {
        guard let bundleID = Bundle.main.bundleIdentifier else { return [] }
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        others.forEach { $0.terminate() }
        return others.map(\.processIdentifier)
    }

    /// Shell lines that wait for each process to exit, force-quitting one that takes over 10 s.
    static func waitScript(for pids: [pid_t]) -> String {
        """
        for P in \(pids.map(String.init).joined(separator: " ")); do
          n=0
          while /bin/kill -0 "$P" 2>/dev/null; do
            /bin/sleep 0.2
            n=$((n + 1))
            if [ "$n" -eq 50 ]; then /bin/kill -9 "$P" 2>/dev/null; fi
          done
        done
        """
    }

    /// AppleScript that runs a shell script with the administrator password prompt.
    static func adminAppleScript(running script: URL) -> String {
        "do shell script \"/bin/sh \" & quoted form of \(appleScriptString(script.path)) with administrator privileges"
    }

    /// A shell single-quoted literal.
    static func quoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// An AppleScript string literal.
    private static func appleScriptString(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    // MARK: - Signature checks

    /// The update must have a valid signature. When the running app is signed with a real
    /// identity, the update must also satisfy the running app's designated requirement,
    /// i.e. come from the same signer. Ad-hoc builds can only be checked for validity.
    static func verifySignature(of app: URL) throws {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &staticCode) == errSecSuccess,
              let staticCode else { throw UpdateError.badSignature }

        var requirement: SecRequirement?
        if let current = currentStaticCode(), !isAdHoc(current) {
            SecCodeCopyDesignatedRequirement(current, [], &requirement)
        }
        let checkAllArchitectures = SecCSFlags(rawValue: 1 << 0) // kSecCSCheckAllArchitectures
        guard SecStaticCodeCheckValidity(staticCode, checkAllArchitectures, requirement) == errSecSuccess else {
            throw UpdateError.badSignature
        }
    }

    private static func currentStaticCode() -> SecStaticCode? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess else { return nil }
        return staticCode
    }

    private static func isAdHoc(_ code: SecStaticCode) -> Bool {
        var info: CFDictionary?
        let signingInformation = SecCSFlags(rawValue: 1 << 1) // kSecCSSigningInformation
        guard SecCodeCopySigningInformation(code, signingInformation, &info) == errSecSuccess,
              let dict = info as? [String: Any] else { return true }
        let flags = (dict[kSecCodeInfoFlags as String] as? NSNumber)?.uint32Value ?? 0
        return flags & 0x0002 != 0 // kSecCodeSignatureAdhoc
    }

    private static func run(_ tool: String, _ arguments: [String]) async throws {
        try await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: tool)
            process.arguments = arguments
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { throw UpdateError.unpackFailed }
        }.value
    }
}
