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
    var body: some View {
        TabView {
            PracticeView()
                .tabItem { Label("Practice", systemImage: "figure.golf") }
            StrokeChartView()
                .tabItem { Label("Chart", systemImage: "ruler") }
            ProgressScreen()
                .tabItem { Label("Progress", systemImage: "chart.line.uptrend.xyaxis") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}

enum Palette {
    /// The one interactive color: a deep fairway green in light mode, a
    /// brighter one in dark mode so it holds contrast on black.
    static let tint = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.36, green: 0.80, blue: 0.58, alpha: 1)
            : UIColor(red: 0.04, green: 0.42, blue: 0.27, alpha: 1)
    })
}
