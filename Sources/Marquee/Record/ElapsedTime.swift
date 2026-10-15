import Foundation

/// Recording time that grows with the recording: "12s", then "4:05", then "1:04:05".
enum ElapsedTime {
    static func format(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        let hours = total / 3600, minutes = (total % 3600) / 60, seconds = total % 60
        if total < 60 { return "\(seconds)s" }
        if hours == 0 { return String(format: "%d:%02d", minutes, seconds) }
        return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    }
}
