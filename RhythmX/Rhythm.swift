//
//  AppEntry.swift
//

import SwiftUI

@main
struct AppEntry: App {
    @StateObject var myEvents          = EventStore(preview: false)
    @StateObject var archivedDataStore = ArchivedDataStore()
    @StateObject var appSettings       = AppSettings()
    @StateObject var fertileStore      = FertileStore()

    @AppStorage("didFinishOnboarding") var didFinishOnboarding = false

    @State private var showSplash = true

    init() { AppGroup.migrateIfNeeded() }

    var body: some Scene {
        WindowGroup {
            ZStack {
                content
                if showSplash {
                    SplashView { withAnimation(.easeOut(duration: 0.45)) { showSplash = false } }
                        .environmentObject(appSettings)
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        Group {
            if didFinishOnboarding {
                StartTabView()
                    .environmentObject(myEvents)
                    .environmentObject(archivedDataStore)
                    .environmentObject(appSettings)
                    .environmentObject(fertileStore)
            } else {
                OnboardingView()
                    .environmentObject(myEvents)
                    .environmentObject(archivedDataStore)
                    .environmentObject(appSettings)
            }
        }
    }
}
