import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// The Putting card as the Lock Screen widget shows it: the backswing for
/// each roll at one green speed. The phone app works it out from the stroke
/// chart and leaves it in the shared App Group, so the widget needs no math.
struct PuttingCardData: Codable, Equatable {
    struct Row: Codable, Equatable, Hashable {
        /// Like "4".
        var paces: String
        /// Like "10.4 in".
        var backswing: String
    }

    /// Like "Medium".
    var speed: String
    var rows: [Row]
    var updated: Date

    static let appGroup = "group.com.tiryqthomas.putting"
    private static let key = "puttingCard"

    static var stored: PuttingCardData? {
        guard let data = UserDefaults(suiteName: appGroup)?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(PuttingCardData.self, from: data)
    }

    /// Saves the card (nil clears it) and asks the widget to redraw if it changed.
    static func save(_ card: PuttingCardData?) {
        guard let defaults = UserDefaults(suiteName: appGroup) else { return }
        let old = stored
        if var card {
            if let old, old.speed == card.speed, old.rows == card.rows { return }
            card.updated = Date()
            defaults.set(try? JSONEncoder().encode(card), forKey: key)
        } else {
            guard old != nil else { return }
            defaults.removeObject(forKey: key)
        }
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    static let example = PuttingCardData(
        speed: "Medium",
        rows: [.init(paces: "2", backswing: "7.0 in"), .init(paces: "4", backswing: "10.4 in"),
               .init(paces: "6", backswing: "13.0 in"), .init(paces: "8", backswing: "15.2 in")],
        updated: Date()
    )
}
