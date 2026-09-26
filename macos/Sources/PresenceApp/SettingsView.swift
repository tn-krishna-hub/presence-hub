import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: PresenceModel

    var body: some View {
        TabView {
            identityTab
                .tabItem { Label("Identity", systemImage: "antenna.radiowaves.left.and.right") }
            behaviorTab
                .tabItem { Label("Behavior", systemImage: "shield.checkered") }
            tuningTab
                .tabItem { Label("Tuning", systemImage: "slider.horizontal.3") }
            dataTab
                .tabItem { Label("Data", systemImage: "chart.xyaxis.line") }
        }
        .padding(20)
        .frame(width: 460, height: 360)
    }

    private var identityTab: some View {
        Form {
            Section {
                TextField("Phone beacon UUID", text: $model.identityUUIDString)
                    .font(.system(.body, design: .monospaced))
                Text("This is the identity the phone's beacon advertises. Open the Android app → Settings, and paste its shown UUID here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Lock screen when phone goes away", isOn: $model.autoLockEnabled)
                    .toggleStyle(.switch)
                Toggle("Notify when phone returns", isOn: $model.notifyOnReturn)
                    .toggleStyle(.switch)
            }
        }
        .formStyle(.grouped)
    }

    private var behaviorTab: some View {
        Form {
            Section {
                Toggle("Lock when away", isOn: $model.autoLockEnabled)
                    .toggleStyle(.switch)
                Text("Nothing ever unlocks automatically — returning to the room only produces a notification. Screen lock still requires your password.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Lock mechanism") {
                HStack {
                    Label(
                        model.accessibilityTrusted ? "Full screen lock active" : "Using screen-saver lock",
                        systemImage: model.accessibilityTrusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(model.accessibilityTrusted ? Color.green : Color.orange)
                    Spacer()
                    Button("Check") { model.refreshAccessibilityStatus() }
                        .controlSize(.small)
                }
                if !model.accessibilityTrusted {
                    Text("""
                    Grant Accessibility: System Settings → Privacy & Security → Accessibility → enable Presence. \
                    Then locking uses the real Lock Screen instead of sleeping the display.
                    """)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { model.refreshAccessibilityStatus() }
    }

    private var tuningTab: some View {
        Form {
            Section("Signal threshold") {
                HStack {
                    Text("Lock-below \(model.signalThreshold) dBm")
                    Spacer()
                }
                Slider(value: thresholdBinding, in: -110 ... -50)
                    .accessibilityLabel("Signal threshold")
                if let headroom = model.headroom {
                    Text(headroomLine(headroom))
                        .font(.caption)
                        .foregroundStyle(headroom >= 10 ? .green : headroom >= 0 ? .orange : .red)
                }
            }
            Section("Short-range boundary") {
                Button("Set boundary where I'm sitting now") { model.setBoundaryHere() }
                    .controlSize(.small)
                Text("Anchors the lock line ~10 dB under your current signal. Stand up / leave the desk by more than that and it locks; sit back down and it sees you again.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Confirmations") {
                Stepper(value: $model.awayConfirmations, in: 2 ... 20) {
                    Text("Away confirmations: \(model.awayConfirmations)")
                }
                Stepper(value: $model.homeConfirmations, in: 1 ... 10) {
                    Text("Home confirmations: \(model.homeConfirmations)")
                }
                Stepper(value: staleBinding, in: 5 ... 60, step: 1) {
                    Text("Stale timeout: \(Int(model.staleTimeout))s")
                }
            }
            Section("Calibrate (recommended)") {
                HStack {
                    Button("Sample: at my desk") { model.sampleHere() }
                        .controlSize(.small)
                    Button("Sample: far away") { model.sampleFar() }
                        .controlSize(.small)
                }
                if model.calHere != nil || model.calFar != nil {
                    Text([
                        model.calHere.map { "here \($0) dBm" },
                        model.calFar.map { "far \($0) dBm" }
                    ].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(model.calMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Live signal: \(model.averageRssi.map { "\($0) dBm" } ?? "—")")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
            Section {
                Text("Higher confirmations = rarer false locks, slower reaction. Use the CLI to find real RSSI values near/away from your Mac, then set the threshold between them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var dataTab: some View {
        Form {
            Section("Timeline") {
                Text(model.timelineFileURL.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([model.timelineFileURL])
                }
            }
            Section("Signal log") {
                if let url = model.signalLogFileURL {
                    Text("Every RSSI sample + away-streak, for diagnosing failed runs.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Reveal signal.log in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                }
            }
            Section {
                ForEach(model.timeline.suffix(8).reversed()) { event in
                    HStack {
                        Text(event.state == .home ? "Arrived" : "Left")
                        Spacer()
                        Text(event.timestamp.formatted(date: .abbreviated, time: .shortened))
                            .foregroundStyle(.secondary)
                    }
                    .font(.callout)
                }
            } header: {
                Text("Recent events")
            }
        }
        .formStyle(.grouped)
    }

    private func headroomLine(_ headroom: Int) -> String {
        if headroom >= 10 {
            return "Headroom +\(headroom) dB — safely in range. A drop of \(headroom) dB+ from here trips the lock."
        } else if headroom >= 0 {
            return "Headroom +\(headroom) dB — close to the line; small movements may trip it."
        } else {
            return "Headroom \(headroom) dB — you're at/past the line right now; a lock is imminent even while seated."
        }
    }

    private var thresholdBinding: Binding<Double> {
        Binding(
            get: { Double(model.signalThreshold) },
            set: { model.signalThreshold = Int($0) }
        )
    }

    private var staleBinding: Binding<Int> {
        Binding(
            get: { Int(model.staleTimeout) },
            set: { model.staleTimeout = TimeInterval($0) }
        )
    }
}

#Preview {
    SettingsView().environmentObject(PresenceModel())
}