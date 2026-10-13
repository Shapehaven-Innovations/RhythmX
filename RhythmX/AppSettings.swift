//  AppSettings.swift

import SwiftUI

final class AppSettings: ObservableObject {
    // Phase colors (hex strings, default to DS token values)
    @AppStorage("phaseColor1", store: AppGroup.defaults) var phaseColor1: String = "#C97C7C"
    @AppStorage("phaseColor2", store: AppGroup.defaults) var phaseColor2: String = "#7CA68C"
    @AppStorage("phaseColor3", store: AppGroup.defaults) var phaseColor3: String = "#C9A87C"
    @AppStorage("phaseColor4", store: AppGroup.defaults) var phaseColor4: String = "#8C7CA6"

    // Notifications
    @AppStorage("notificationsEnabled") var notificationsEnabled: Bool = false
    @AppStorage("notifyDayBefore")      var notifyDayBefore: Bool = true
    @AppStorage("notifyDayOf")          var notifyDayOf: Bool = true

    // Flags
    @AppStorage("hasPromptedNotifications") var hasPromptedNotifications: Bool = false
    @AppStorage("sharerName") var sharerName: String = ""

    /// Changes whenever any phase color changes; lets views trigger a widget reload.
    var colorSignature: String { phaseColor1 + phaseColor2 + phaseColor3 + phaseColor4 }

    func phaseColor(for phase: Event.EventType) -> Color {
        let hex: String
        switch phase {
        case .menstrual:  hex = phaseColor1
        case .follicular: hex = phaseColor2
        case .ovulation:  hex = phaseColor3
        case .luteal:     hex = phaseColor4
        }
        return Color(hex: hex) ?? phase.defaultPhaseColor
    }

    func resetToDefaults() {
        phaseColor1 = "#C97C7C"
        phaseColor2 = "#7CA68C"
        phaseColor3 = "#C9A87C"
        phaseColor4 = "#8C7CA6"
    }
}
