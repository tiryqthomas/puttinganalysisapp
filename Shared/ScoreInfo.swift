import Foundation

/// Plain-language explanations of each consistency score, shown behind the
/// info buttons on the phone and the watch.
enum ScoreInfo: String, CaseIterable, Identifiable {
    case tempo, rhythm, proportion, distance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tempo: "Tempo"
        case .rhythm: "Rhythm"
        case .proportion: "Proportion"
        case .distance: "Distance control"
        }
    }

    /// What is measured on each stroke.
    var measures: String {
        switch self {
        case .tempo:
            "Backswing time divided by downswing time (top of the backswing to impact). 0.60 s back and 0.30 s down is 2.0 : 1. Many good putters sit near 2 : 1."
        case .rhythm:
            "Total time from takeaway to impact. Good putters take about the same time for a 5 ft putt as a 40 ft putt; only the length changes."
        case .proportion:
            "Follow-through length compared with backswing length. 120% means you swing through a little farther than you take it back."
        case .distance:
            "How close each roll came to what your stroke chart predicts for that backswing."
        }
    }

    /// What the 0–100 score means.
    var scoring: String {
        switch self {
        case .distance:
            "100 means every roll matched your chart. It needs at least 4 putts with a roll distance."
        default:
            "The score shows how steady this stays from stroke to stroke. 100 means every stroke matched; it needs at least 3 strokes."
        }
    }
}
