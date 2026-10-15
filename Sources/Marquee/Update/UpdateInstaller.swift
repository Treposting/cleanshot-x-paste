import AppKit
import Security

enum UpdateError: LocalizedError {
    case badResponse
    case noDownload
    case downloadFailed
    case unpackFailed
    case wrongApp
    case badSignature
    case notWritable

    var errorDescription: String? {
        switch self {
        case .badResponse: return "GitHub didn't return release information. Check your connection and try again."
        case .noDownload: return "This release has no in-app update file. Download it from the releases page instead."
        case .downloadFailed: return "The download didn't finish. Check your connection and try again."
        case .unpackFailed: return "The downloaded update couldn't be unpacked."
        case .wrongApp: return "The downloaded file isn't the expected Marquee version, so it wasn't installed."
        case .badSignature: return "The update's code signature didn't verify, so it wasn't installed."
        case .notWritable:
            return "Marquee can't replace itself where it's running from. Move Marquee to your Applications folder, open it from there, and try again."
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

    /// Starts a small shell helper that waits for Marquee to quit, swaps the app bundle,
    /// and opens the new version. The caller quits the app right after this returns.
    static func replaceAndRelaunch(with staged: URL) throws {
        let current = Bundle.main.bundleURL
        let parent = current.deletingLastPathComponent()
        guard !current.path.contains("/AppTranslocation/"),
              FileManager.default.isWritableFile(atPath: parent.path) else {
            throw UpdateError.notWritable
        }
        let script = """
        while /bin/kill -0 "$PID" 2>/dev/null; do /bin/sleep 0.2; done
        /bin/rm -rf "$OLD.previous"
        if /bin/mv "$OLD" "$OLD.previous" && /bin/mv "$NEW" "$OLD"; then
          /bin/rm -rf "$OLD.previous"
        elif [ -d "$OLD.previous" ] && [ ! -d "$OLD" ]; then
          /bin/mv "$OLD.previous" "$OLD"
        fi
        /usr/bin/xattr -dr com.apple.quarantine "$OLD" 2>/dev/null
        /usr/bin/open "$OLD"
        """
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/sh")
        helper.arguments = ["-c", script]
        helper.environment = [
            "PID": String(ProcessInfo.processInfo.processIdentifier),
            "OLD": current.path,
            "NEW": staged.path,
        ]
        try helper.run()
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
