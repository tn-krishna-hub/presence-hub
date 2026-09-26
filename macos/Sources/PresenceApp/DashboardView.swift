import SwiftUI
import PresenceCore

struct DashboardView: View {
    @EnvironmentObject private var model: PresenceModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            toggles
            Divider()
            recentTimeline
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 320)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(model.state == .home ? Color.green : Color.orange)
                .frame(width: 12, height: 12)
            Text(model.state == .home ? "In range" : "Away")
                .font(.headline)
            Spacer()
            Text(detailText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var detailText: String {
        switch model.btState {
        case .poweredOn:
            if let rssi = model.lastRssi { return "\(rssi) dBm" }
            return "scanning…"
        case .unknown, .resetting, .unsupported:
            return "bluetooth…"
        case .unauthorized:
            return "bluetooth denied"
        case .poweredOff:
            return "bluetooth off"
        @unknown default:
            return "bluetooth…"
        }
    }

    private var toggles: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Lock screen when away", isOn: $model.autoLockEnabled)
                .toggleStyle(.switch)
            Toggle("Notify when phone returns", isOn: $model.notifyOnReturn)
                .toggleStyle(.switch)
            Button("Test lock now") { model.lockNow() }
                .controlSize(.small)
        }
    }

    private var recentTimeline: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Timeline")
                .font(.caption)
                .foregroundStyle(.secondary)
            if model.timeline.isEmpty {
                Text("No events recorded yet.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(model.timeline.suffix(6).reversed()) { event in
                    HStack {
                        Image(systemName: event.state == .home ? "arrow.left.and.line.vertical" : "arrow.right.and.line.vertical")
                            .foregroundStyle(event.state == .home ? Color.green : Color.orange)
                        Text(event.state == .home ? "Arrived" : "Left")
                        Spacer()
                        Text(event.timestamp.formatted(date: .omitted, time: .shortened))
                            .foregroundStyle(.secondary)
                        if let rssi = event.rssi {
                            Text("\(rssi) dBm")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .font(.callout)
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Settings…") { openSettings() }
                .controlSize(.small)
            Spacer()
            Button("Quit") { model.quit() }
                .controlSize(.small)
        }
    }

    private func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}

#Preview {
    DashboardView().environmentObject(PresenceModel())
}