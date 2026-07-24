import SwiftUI

/// Lists every macOS permission Notchless can use with live status and a
/// one-click action: request it if unset, or jump to System Settings to
/// enable/disable it. See spec §5 "Permissions + About".
struct PermissionsPane: View {
    @StateObject private var model = PermissionsModel()

    /// Spec-named permissions first, in spec order, then any working
    /// permission the spec doesn't call out (Location, Bluetooth) — kept
    /// rather than dropped.
    private var orderedPermissions: [AppPermission] {
        let named: [AppPermission] = [.accessibility, .microphone, .speechRecognition, .camera, .calendar]
        let rest = AppPermission.allCases.filter { !named.contains($0) }
        return named + rest
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            PaneHeader(section: .permissions)

            SectionLabel("Permissions")
            CardGroup {
                ForEach(Array(orderedPermissions.enumerated()), id: \.element) { index, permission in
                    if index > 0 { CardDivider() }
                    PermissionRow(
                        permission: permission,
                        state: model.states[permission] ?? .notDetermined,
                        action: { model.act(on: permission) }
                    )
                }
            }

            Footnote("macOS only lets you turn a permission off in System Settings — those buttons open the right pane.")
        }
        .onAppear { model.startAutoRefresh() }
        .onDisappear { model.stopAutoRefresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refresh()
        }
    }
}

private struct PermissionRow: View {
    let permission: AppPermission
    let state: PermissionState
    let action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            (Text(permission.title).foregroundStyle(SettingsTheme.text)
                + Text(" — \(permission.purpose)").foregroundStyle(SettingsTheme.textTertiary))
                .font(.system(size: 13))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 10)
            Circle().fill(state.dotColor).frame(width: 7, height: 7)
            Text(state.label)
                .font(.system(size: 12))
                .foregroundStyle(SettingsTheme.textSecondary)
                .frame(width: 60, alignment: .leading)
            FlatButton(title: buttonLabel, style: buttonLabel == "Enable" ? .primary : .secondary, action: action)
        }
    }

    private var buttonLabel: String {
        if permission == .accessibility { return state == .granted ? "Settings" : "Enable" }
        return state == .notDetermined ? "Enable" : "Settings"
    }
}

private extension PermissionState {
    /// Spec §5 "Status dot" tokens.
    var dotColor: Color {
        switch self {
        case .granted: return SettingsTheme.statusGranted
        case .denied: return SettingsTheme.statusDenied
        case .notDetermined: return SettingsTheme.statusUnset
        }
    }
}
