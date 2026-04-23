import ConductorCore
import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = SessionViewModel()

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.07, green: 0.10, blue: 0.13),
                    Color(red: 0.16, green: 0.12, blue: 0.08),
                    Color(red: 0.06, green: 0.13, blue: 0.12),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            HStack(spacing: 22) {
                controlRail
                    .frame(width: 390)

                stageSurface
            }
            .padding(24)
        }
    }

    private var controlRail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                titlePanel
                routingPanel
                orchestraPanel
                trackingPanel
                instrumentPanel
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }

    private var titlePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("The Conductor")
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)

            Text("Native desktop scaffold for hand-led harmony, loop capture, and Logic routing.")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.74))

            HStack(spacing: 10) {
                statusChip(title: viewModel.performanceState.isPerforming ? "Live" : "Standby", color: .mint)
                statusChip(title: viewModel.performanceState.loopBuffer.statusLabel, color: .orange)
                statusChip(title: viewModel.routingMode.rawValue, color: .cyan)
                statusChip(title: viewModel.trackingMode.rawValue, color: .yellow)
            }
        }
        .panelStyle(fill: Color.white.opacity(0.07))
    }

    private var routingPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Routing")
                .sectionTitle()

            Picker("Mode", selection: $viewModel.routingMode) {
                ForEach(RoutingMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Picker("Key Center", selection: $viewModel.keyCenter) {
                ForEach(PitchClass.allCases) { pitch in
                    Text(pitch.displayName).tag(pitch)
                }
            }
            .pickerStyle(.menu)

            Text(viewModel.routingDescription)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.68))

            if let instrument = viewModel.selectedInstrument {
                Text("Target sound: \(instrument.name) · \(instrument.format.rawValue)")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))
            }
        }
        .panelStyle(fill: Color(red: 0.10, green: 0.17, blue: 0.16).opacity(0.55))
    }

    private var orchestraPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Orchestration")
                .sectionTitle()

            ForEach(viewModel.performanceState.layers) { layer in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(layer.name)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(layer.isEnabled ? 0.95 : 0.45))
                        Spacer()
                        Text("\(Int(layer.mix * 100))%")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.7))
                    }

                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 999, style: .continuous)
                                .fill(Color.white.opacity(0.08))

                            RoundedRectangle(cornerRadius: 999, style: .continuous)
                                .fill(layer.isEnabled ? Color.orange.gradient : Color.gray.gradient)
                                .frame(width: proxy.size.width * layer.mix)
                        }
                    }
                    .frame(height: 10)
                }
            }
        }
        .panelStyle(fill: Color(red: 0.20, green: 0.11, blue: 0.06).opacity(0.48))
    }

    private var trackingPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Tracking")
                .sectionTitle()

            Picker("Input", selection: $viewModel.trackingMode) {
                ForEach(TrackingMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if viewModel.isLiveTracking {
                liveTrackingPanel
            } else {
                simulatorPanel
            }
        }
        .panelStyle(fill: Color(red: 0.08, green: 0.14, blue: 0.22).opacity(0.56))
    }

    private var simulatorPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                actionButton("Downbeat", color: .mint, action: viewModel.pulseDownbeat)
                actionButton("Commit", color: .orange, action: viewModel.pulseCommit)
                actionButton("Loop", color: .cyan, action: viewModel.pulseLoopToggle)
                actionButton("Stop", color: .red, action: viewModel.pulseStop)
            }

            handEditor(
                title: "Left Hand",
                x: viewModel.binding(\.leftPosition.x),
                y: viewModel.binding(\.leftPosition.y),
                pinch: viewModel.binding(\.leftPinch),
                velocity: viewModel.binding(\.leftVerticalVelocity),
                openness: viewModel.binding(\.leftOpenness)
            )

            handEditor(
                title: "Right Hand",
                x: viewModel.binding(\.rightPosition.x),
                y: viewModel.binding(\.rightPosition.y),
                pinch: viewModel.binding(\.rightPinch),
                velocity: viewModel.binding(\.rightVerticalVelocity),
                openness: viewModel.binding(\.rightOpenness)
            )
        }
    }

    private var liveTrackingPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Authorization")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.72))
                Spacer()
                Text(viewModel.cameraAuthorizationStatusText)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }

            Text(viewModel.liveTrackingStatusText)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.88))

            HStack(spacing: 10) {
                actionButton("Start Camera", color: .mint, action: viewModel.startLiveTracking)
                actionButton("Stop Camera", color: .red, action: viewModel.stopLiveTracking)
            }

            Text("Live mode feeds Vision hand-pose observations into the same harmonic engine used by the simulator. Keep the simulator for deterministic tuning and use the camera path to validate real gestures.")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.64))

            Text("Gesture vocabulary")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 6) {
                liveTip("Right-hand wrist position previews chord direction.")
                liveTip("Right-hand pinch commits the previewed chord.")
                liveTip("Fast open-handed downbeat engages the ensemble.")
                liveTip("Both hands pinched toggles loop capture.")
                liveTip("Left-hand position selects interval focus.")
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.black.opacity(0.14))
        )
    }

    private var instrumentPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Instrument Targets")
                .sectionTitle()

            Picker("Instrument", selection: $viewModel.selectedInstrumentID) {
                ForEach(viewModel.availableInstruments) { instrument in
                    Text("\(instrument.name) · \(instrument.format.rawValue)").tag(instrument.id)
                }
            }
            .pickerStyle(.menu)

            ForEach(viewModel.availableInstruments) { instrument in
                HStack(alignment: .top, spacing: 12) {
                    Circle()
                        .fill(instrument.id == viewModel.selectedInstrumentID ? Color.orange : Color.white.opacity(0.22))
                        .frame(width: 10, height: 10)
                        .padding(.top, 4)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(instrument.name)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                        Text("\(instrument.format.rawValue) · \(instrument.source)")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.62))
                    }
                }
            }
        }
        .panelStyle(fill: Color(red: 0.15, green: 0.09, blue: 0.16).opacity(0.48))
    }

    private var stageSurface: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                stageStat(title: "Current Chord", value: viewModel.performanceState.currentChord.symbol)
                stageStat(title: "Preview", value: viewModel.performanceState.previewChord.symbol)
                stageStat(title: "Interval", value: viewModel.performanceState.interval.spokenName)
                stageStat(title: "Dynamics", value: "\(Int(viewModel.performanceState.dynamics * 100))%")
            }

            Text(viewModel.performanceState.activityText)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.82))
                .padding(.horizontal, 6)

            HStack(spacing: 22) {
                CirclePlotView(
                    title: "Chord Orbit",
                    subtitle: "Right hand chooses harmonic direction around the progression wheel.",
                    labels: viewModel.chordLabels,
                    point: viewModel.performanceState.chordPlot,
                    accent: Color.orange
                )

                CirclePlotView(
                    title: "Interval Orbit",
                    subtitle: "Left hand shapes interval emphasis and voicing color.",
                    labels: viewModel.intervalLabels,
                    point: viewModel.performanceState.intervalPlot,
                    accent: Color.cyan
                )
            }

            if viewModel.isLiveTracking {
                liveCameraStage
            }
        }
    }

    private var liveCameraStage: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Camera Feed")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Spacer()
                Text(viewModel.isCameraRunning ? "Running" : "Stopped")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.66))
            }

            CameraPreviewView(session: viewModel.captureSession)
                .frame(minHeight: 280, maxHeight: 320)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )
        }
    }

    private func handEditor(
        title: String,
        x: Binding<Double>,
        y: Binding<Double>,
        pinch: Binding<Double>,
        velocity: Binding<Double>,
        openness: Binding<HandOpenness>
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            sliderRow(title: "X Position", value: x, range: -1...1)
            sliderRow(title: "Y Position", value: y, range: -1...1)
            sliderRow(title: "Pinch", value: pinch, range: 0...1)
            sliderRow(title: "Vertical Velocity", value: velocity, range: -1.2...1.2)

            Picker("Openness", selection: openness) {
                ForEach(HandOpenness.allCases) { state in
                    Text(state.rawValue.capitalized).tag(state)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.black.opacity(0.14))
        )
    }

    private func sliderRow(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.72))
                Spacer()
                Text(String(format: "%.2f", value.wrappedValue))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
            }

            Slider(value: value, in: range)
                .tint(.orange)
        }
    }

    private func stageStat(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.48))
            Text(value)
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .panelStyle(fill: Color.white.opacity(0.06))
    }

    private func actionButton(_ title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.borderedProminent)
            .tint(color.opacity(0.85))
            .font(.system(size: 12, weight: .bold, design: .rounded))
    }

    private func statusChip(title: String, color: Color) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(color.opacity(0.18))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(color.opacity(0.35), lineWidth: 1)
            )
            .foregroundStyle(.white.opacity(0.92))
    }

    private func liveTip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(.white.opacity(0.74))
    }
}

struct PanelModifier: ViewModifier {
    let fill: Color

    func body(content: Content) -> some View {
        content
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
    }
}

extension View {
    func panelStyle(fill: Color) -> some View {
        modifier(PanelModifier(fill: fill))
    }
}

extension Text {
    func sectionTitle() -> some View {
        font(.system(size: 18, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
    }
}
