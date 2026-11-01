import SwiftUI

@main struct BlackBoxApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            RootView(model: model, rdc: model.rdc, audio: model.audio)
                .preferredColorScheme(.dark)
                .tint(Color(red: 0.26, green: 0.58, blue: 1))
                .task { await model.resume() }
                .onChange(of: phase) { _, value in
                    if value == .background { model.suspend() }
                    if value == .active { Task { await model.resume() } }
                }
        }
    }
}
