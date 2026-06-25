import Foundation

enum TimerDurationInput {
    static let maximumSeconds = 24 * 60 * 60

    static func limitedClockText(_ text: String) -> String {
        var groups = [""]

        for character in text where character.isNumber || character == ":" {
            if character == ":" {
                guard groups.count < 3 else { continue }
                groups.append("")
            } else if groups[groups.count - 1].count < 2 {
                groups[groups.count - 1].append(character)
            }
        }

        return groups.joined(separator: ":")
    }

    /// Plain numbers are minutes. A colon-separated value is minutes:seconds.
    static func parseSeconds(_ text: String) -> Int? {
        let components = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: ":", omittingEmptySubsequences: false)

        switch components.count {
        case 1:
            guard let minutes = Int(components[0]), minutes >= 0 else {
                return nil
            }
            return min(minutes, maximumSeconds / 60) * 60

        case 2:
            guard
                let minutes = Int(components[0]),
                let seconds = Int(components[1]),
                minutes >= 0,
                (0..<60).contains(seconds)
            else {
                return nil
            }

            guard minutes < maximumSeconds / 60 else {
                return maximumSeconds
            }
            return min(minutes * 60 + seconds, maximumSeconds)

        case 3:
            guard
                let hours = Int(components[0]),
                let minutes = Int(components[1]),
                let seconds = Int(components[2]),
                hours >= 0,
                (0..<60).contains(minutes),
                (0..<60).contains(seconds)
            else {
                return nil
            }

            return min(hours * 3_600 + minutes * 60 + seconds, maximumSeconds)

        default:
            return nil
        }
    }
}
