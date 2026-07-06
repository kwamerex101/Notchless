import SwiftUI

/// Lists every macOS permission Notchless can use with live status and a
/// one-click action: request it if unset, or jump to System Settings to
/// enable/disable it.
struct PermissionsPane: View {
    @StateObject private var model = PermissionsModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            PaneHeader(section: .permissions)

            SectionLabel("Permissions")
            CardGroup {
                ForEach(Array(AppPermission.allCases.enumerated()), id: \.element) { index, permission in
                    if index > 0 { Divider() }
                    PermissionRow(
                        permission: permission,
                        state: model.states[permission] ?? .notDetermined,
                        action: { model.act(on: permission) }
                    )
                }
            }

            Text("macOS only lets you turn a permission off in System Settings — those buttons open the right pane. Newly-granted permissions may need Notchless to relaunch to take effect.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
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
        HStack(spacing: 12) {
            Image(systemName: permission.systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 7).fill(state.color.gradient))
            VStack(alignment: .leading, spacing: 2) {
                Text(permission.title).font(.callout.weight(.medium))
                Text(permission.purpose).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 4) {
                Circle().fill(state.color).frame(width: 7, height: 7)
                Text(state.label).font(.caption).foregroundStyle(.secondary)
            }
            .frame(width: 78, alignment: .leading)
            Button(buttonLabel, action: action)
        }
    }

    private var buttonLabel: String {
        if permission == .accessibility { return state == .granted ? "Settings" : "Enable" }
        return state == .notDetermined ? "Enable" : "Settings"
    }
}
