import Charts
import PuttCore
import SwiftData
import SwiftUI

@main
struct PuttPhoneApp: App {
    private let container: ModelContainer
    @State private var settings: AppSettings
    @State private var inbox: StrokeInbox
    @State private var faker = StrokeFaker()

    @MainActor
    init() {
        let container = try! ModelContainer(for: PracticeSession.self, PuttStroke.self)
        let settings = AppSettings()
        self.container = container
        _settings = State(initialValue: settings)
        _inbox = State(initialValue: StrokeInbox(context: container.mainContext, settings: settings))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .environment(inbox)
                .environment(faker)
                .tint(Palette.tint)
        }
        .modelContainer(container)
    }
}

struct RootView: View {
    enum Tab: Hashable { case practice, chart, progress, settings }

    @Environment(StrokeInbox.self) private var inbox
    @Environment(\.modelContext) private var context
    @State private var tab: Tab = .practice

    var body: some View {
        TabView(selection: $tab) {
            PracticeView()
                .tabItem { Label("Practice", systemImage: "figure.golf") }
                .tag(Tab.practice)
            StrokeChartView()
                .tabItem { Label("Chart", systemImage: "ruler") }
                .tag(Tab.chart)
            ProgressScreen()
                .tabItem { Label("Progress", systemImage: "chart.line.uptrend.xyaxis") }
                .tag(Tab.progress)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(Tab.settings)
        }
        // When the player taps End on the watch, show how the session went.
        .sheet(item: endedSession) { session in
            RecapView(session: session) { tab = .chart }
        }
    }

    private var endedSession: Binding<PracticeSession?> {
        Binding(
            get: {
                guard let id = inbox.endedSessionID else { return nil }
                return try? context.fetch(FetchDescriptor<PracticeSession>(predicate: #Predicate { $0.id == id })).first
            },
            set: { if $0 == nil { inbox.endedSessionID = nil } }
        )
    }
}

enum Palette {
    struct SpeedSeries {
        let name: String
        let color: Color
        let symbol: BasicChartSymbolShape
    }

    /// Green speeds are ordered, so they share one hue stepped light to dark
    /// (dark to light in dark mode), each with its own marker shape so the
    /// chart never relies on color alone.
    static let speedSeries: [SpeedSeries] = [
        SpeedSeries(name: GreenSpeed.verySlow.shortTitle, color: dynamic(light: 0x5FB38A, dark: 0x2A6E4E), symbol: .circle),
        SpeedSeries(name: GreenSpeed.slow.shortTitle, color: dynamic(light: 0x3E9A6E, dark: 0x3F9268), symbol: .square),
        SpeedSeries(name: GreenSpeed.medium.shortTitle, color: dynamic(light: 0x23825A, dark: 0x5DB487), symbol: .pentagon),
        SpeedSeries(name: GreenSpeed.fast.shortTitle, color: dynamic(light: 0x116243, dark: 0x8ED5AE), symbol: .triangle),
        SpeedSeries(name: GreenSpeed.veryFast.shortTitle, color: dynamic(light: 0x0A3F2A, dark: 0xC8F0DA), symbol: .diamond),
        SpeedSeries(name: "Speed not set", color: Color(.systemGray), symbol: .cross),
    ]

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        func ui(_ hex: UInt32) -> UIColor {
            UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }
        return Color(UIColor { $0.userInterfaceStyle == .dark ? ui(dark) : ui(light) })
    }

    /// The one interactive color: a deep fairway green in light mode, a
    /// brighter one in dark mode so it holds contrast on black.
    static let tint = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.36, green: 0.80, blue: 0.58, alpha: 1)
            : UIColor(red: 0.04, green: 0.42, blue: 0.27, alpha: 1)
    })
}
