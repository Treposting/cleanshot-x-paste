import Foundation

/// Runs `work` on the main actor after `seconds`. Used instead of
/// `DispatchQueue.main.asyncAfter` so actor isolation is explicit.
@MainActor
func runAfter(_ seconds: Double, _ work: @escaping @MainActor () -> Void) {
    Task { @MainActor in
        if seconds > 0 {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        }
        work()
    }
}
