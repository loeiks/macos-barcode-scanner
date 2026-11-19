import SwiftUI

struct PopoverView: View {
    @ObservedObject var model: ScannerAppModel
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)
            ScrollView {
                VStack(spacing: 14) {
                    preview
                    modeSection
                    settingsCard
                    if model.needsAccessibility {
                        accessibilityCard
                    }
                    if let loginError = model.loginError {
                        Text(loginError)
                            .font(.system(size: 10))
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(16)
            }
            .scrollIndicators(.never)
            Divider().opacity(0.5)
            footer
        }
        .frame(width: 340, height: 600)
    }

    private var header: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.18, green: 0.40, blue: 0.96), Color(red: 0.51, green: 0.30, blue: 0.94)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 32, height: 32)
                .overlay(
                    Image(systemName: "barcode")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                )

            VStack(alignment: .leading, spacing: 1) {
                Text("Barcode Scanner")
                    .font(.system(size: 13, weight: .semibold))
                HStack(spacing: 5) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 5, height: 5)
                    Text(model.status.title)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            Spacer(minLength: 4)

            Button {
                model.toggleScanning()
            } label: {
                Image(systemName: model.isAwake ? "moon.fill" : "sun.max.fill")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help(model.isAwake ? "Sleep" : "Wake (⌥⌘B)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }

    private var preview: some View {
        ZStack {
            CameraPreview(session: model.session)

            switch model.status {
            case .scanning:
                EmptyView()
            case .starting:
                overlayContent(icon: nil, title: "Starting camera…", detail: nil, actionTitle: nil) {}
            case .sleeping:
                overlayContent(
                    icon: "moon.zzz.fill",
                    title: "Sleeping",
                    detail: "Press ⌥⌘B to wake",
                    actionTitle: "Wake"
                ) {
                    model.wake()
                }
            case .permissionDenied:
                overlayContent(
                    icon: "video.slash.fill",
                    title: "Camera access needed",
                    detail: "Allow camera access in System Settings",
                    actionTitle: "Open Settings"
                ) {
                    model.openCameraSettings()
                }
            case .noCamera:
                overlayContent(
                    icon: "video.slash.fill",
                    title: "No camera found",
                    detail: "Connect a camera or iPhone",
                    actionTitle: "Retry"
                ) {
                    model.wake()
                }
            case .failed(let message):
                overlayContent(
                    icon: "exclamationmark.triangle.fill",
                    title: "Camera stopped",
                    detail: message,
                    actionTitle: "Retry"
                ) {
                    model.wake()
                }
            }
        }
        .frame(height: 158)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
        )
    }

    private func overlayContent(
        icon: String?,
        title: String,
        detail: String?,
        actionTitle: String?,
        action: @escaping () -> Void
    ) -> some View {
        ZStack {
            Color.black.opacity(0.55)
            VStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(.white.opacity(0.9))
                } else {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                }
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                if let detail {
                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.65))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
                if let actionTitle {
                    Button(actionTitle, action: action)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .tint(.white.opacity(0.9))
                        .foregroundStyle(.black)
                        .padding(.top, 2)
                }
            }
            .padding(12)
        }
    }

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Output mode", selection: $settings.mode) {
                ForEach(OutputMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Text(settings.mode.detail)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var settingsCard: some View {
        VStack(spacing: 0) {
            settingsRow(icon: "speaker.wave.2", title: "Sound") {
                Toggle("", isOn: $settings.soundEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
            }

            rowDivider

            settingsRow(icon: "moon", title: "Sleep after") {
                Picker("Sleep after", selection: $settings.sleepInterval) {
                    ForEach(SleepInterval.allCases) { interval in
                        Text(interval.title).tag(interval)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                .frame(width: 104)
            }

            rowDivider

            settingsRow(icon: "video", title: "Camera") {
                Picker("Camera", selection: cameraSelection) {
                    Text("Automatic").tag(String?.none)
                    ForEach(model.devices) { device in
                        Text(device.name).tag(Optional(device.id))
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                .frame(maxWidth: 150)
            }

            rowDivider

            settingsRow(icon: "arrow.up.right.square", title: "Launch at login") {
                Toggle("", isOn: launchAtLoginBinding)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
            }
        }
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(0.045))
        )
    }

    private var accessibilityCard: some View {
        Button {
            model.requestAccessibility()
        } label: {
            HStack(spacing: 9) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Accessibility needed for paste")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.primary)
                    Text("System Settings › Privacy & Security › Accessibility")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 2)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.orange.opacity(0.10))
            )
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        HStack(spacing: 5) {
            Text("⌥⌘B")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
            Text(model.hotkeyAvailable ? "toggle scanning" : "shortcut unavailable")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Spacer()
            Button("Quit") {
                NSApp.terminate(nil)
            }
            .buttonStyle(.borderless)
            .font(.system(size: 11))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }

    private var statusColor: Color {
        switch model.status {
        case .scanning: return .green
        case .starting: return .orange
        case .sleeping: return .secondary
        case .permissionDenied, .noCamera, .failed: return .red
        }
    }

    private var cameraSelection: Binding<String?> {
        Binding(
            get: { settings.preferredCameraID },
            set: { model.selectCamera(id: $0) }
        )
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { model.launchAtLogin },
            set: { model.setLaunchAtLogin($0) }
        )
    }

    private var rowDivider: some View {
        Divider()
            .opacity(0.5)
            .padding(.leading, 30)
    }

    private func settingsRow<Content: View>(
        icon: String,
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(title)
                .font(.system(size: 12))
            Spacer(minLength: 8)
            content()
        }
        .padding(.horizontal, 10)
        .frame(height: 33)
    }
}
