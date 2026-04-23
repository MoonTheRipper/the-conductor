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
                if viewModel.routingMode == .standaloneHost {
                    standaloneHostPanel
                }
                if viewModel.routingMode == .logicBridge {
                    logicBridgePanel
                }
                loopTransportPanel
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
                Text("Browse target: \(instrument.name) · \(instrument.format.rawValue)")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))
            }
        }
        .panelStyle(fill: Color(red: 0.10, green: 0.17, blue: 0.16).opacity(0.55))
    }

    private var standaloneHostPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Standalone Host")
                    .sectionTitle()
                Spacer()
                actionButton("Assign Selected", color: .cyan, action: viewModel.assignSelectedInstrumentToAllLayers)
                actionButton("Clear Layers", color: .orange, action: viewModel.clearLayerAssignments)
                actionButton("Unload", color: .purple, action: viewModel.unloadStandaloneAssignments)
                actionButton("Panic", color: .red, action: viewModel.silenceStandaloneNotes)
            }

            HStack(spacing: 10) {
                statusChip(title: viewModel.isStandaloneEngineRunning ? "Engine Running" : "Engine Stopped", color: .mint)
                statusChip(title: viewModel.isStandaloneInstrumentLoaded ? "Layers Loaded" : "Discovery Only", color: .orange)
            }

            if let loadedInstrumentName = viewModel.standaloneLoadedInstrumentName {
                Text("Loaded assignments: \(loadedInstrumentName)")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))
            }

            Text(viewModel.standaloneHostStatusText)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.72))

            Text(viewModel.standaloneSupportText)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(viewModel.isStandaloneInstrumentLoaded ? .mint : .yellow)

            ForEach(PerformanceLayerPlanner.layerNames, id: \.self) { layerName in
                layerAssignmentRow(layerName: layerName)
            }

            if viewModel.standaloneLoadedLayerSummary.isEmpty == false {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Signal Paths")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.58))

                    ForEach(viewModel.standaloneLoadedLayerSummary, id: \.self) { line in
                        Text(line)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.72))
                    }
                }
            }

            Text("Standalone playback now hosts Audio Units and playable library folders directly. VST/VST3 entries remain discoverable, but they are not yet instantiated by the host.")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.62))
        }
        .panelStyle(fill: Color(red: 0.10, green: 0.09, blue: 0.20).opacity(0.56))
    }

    private var logicBridgePanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Logic Bridge")
                    .sectionTitle()
                Spacer()
                actionButton("Refresh MIDI", color: .cyan, action: viewModel.refreshMIDIDestinations)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Virtual Source")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.58))
                Text(viewModel.virtualMIDISourceName)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }

            Toggle(isOn: $viewModel.sendToVirtualMIDISource) {
                Text("Publish virtual MIDI source")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .toggleStyle(.switch)

            Picker("Direct Destination", selection: $viewModel.selectedMIDIDestinationID) {
                Text("None").tag(LogicMIDIBridgeService.noDestinationID)
                ForEach(viewModel.midiDestinations) { destination in
                    Text(destination.isLikelyLogicInput ? "\(destination.name) · Logic" : destination.name)
                        .tag(destination.id)
                }
            }
            .pickerStyle(.menu)

            Text(viewModel.midiStatusText)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.72))

            VStack(alignment: .leading, spacing: 6) {
                Text("Layer channels")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.58))

                ForEach(viewModel.midiChannelMapDescription, id: \.self) { line in
                    Text(line)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.72))
                }
            }

            actionButton("All Notes Off", color: .red, action: viewModel.silenceMIDINotes)
        }
        .panelStyle(fill: Color(red: 0.12, green: 0.08, blue: 0.17).opacity(0.56))
    }

    private var orchestraPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Orchestration")
                    .sectionTitle()
                Spacer()
                actionButton("Reset FX", color: .purple, action: viewModel.resetLayerOutputRouting)
                Text("Manual trims")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.46))
            }

            ForEach(viewModel.effectiveLayers) { layer in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(layer.name)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white.opacity(layer.isEnabled ? 0.95 : 0.45))
                            if let automaticLayer = viewModel.performanceState.layers.first(where: { $0.name == layer.name }) {
                                Text("Auto \(Int(automaticLayer.mix * 100))% -> Output \(Int(layer.mix * 100))%")
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.52))
                            }
                        }
                        Spacer()
                        Toggle("", isOn: viewModel.layerEnabledBinding(for: layer.name))
                            .toggleStyle(.switch)
                            .labelsHidden()
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

                    Slider(value: viewModel.layerGainBinding(for: layer.name), in: 0...1.5)
                        .tint(layer.isEnabled ? .orange : .gray)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Route")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.58))
                            Spacer()
                            Text(viewModel.layerOutputSummary(for: layer.name))
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.52))
                        }

                        Picker("\(layer.name) Bus", selection: viewModel.layerOutputBusBinding(for: layer.name)) {
                            ForEach(LayerOutputBus.allCases) { bus in
                                Text("\(bus.rawValue) · \(bus.summaryText)").tag(bus)
                            }
                        }
                        .pickerStyle(.menu)

                        sliderRow(
                            title: "Pan",
                            value: viewModel.layerOutputScalarBinding(for: layer.name, keyPath: \.pan),
                            range: -1...1
                        )
                        sliderRow(
                            title: "Space",
                            value: viewModel.layerOutputScalarBinding(for: layer.name, keyPath: \.reverbMix),
                            range: 0...100
                        )
                        sliderRow(
                            title: "Echo",
                            value: viewModel.layerOutputScalarBinding(for: layer.name, keyPath: \.delayMix),
                            range: 0...100
                        )
                        sliderRow(
                            title: "Echo Time",
                            value: viewModel.layerOutputScalarBinding(for: layer.name, keyPath: \.delayTime),
                            range: 0.05...0.65
                        )
                    }
                    .padding(.top, 2)
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

            calibrationPanel
        }
        .panelStyle(fill: Color(red: 0.08, green: 0.14, blue: 0.22).opacity(0.56))
    }

    private var loopTransportPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Loop Transport")
                    .sectionTitle()
                Spacer()
                actionButton("Export MIDI", color: .cyan, action: viewModel.exportLoopAsMIDI)
            }

            Text(viewModel.loopTransportStatusText)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.88))

            Text(viewModel.exportStatusText)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.62))

            TextField("Clip Name", text: viewModel.exportOptionsBinding(\.clipName))
                .textFieldStyle(.roundedBorder)

            sliderRow(
                title: "Tempo",
                value: viewModel.exportOptionsBinding(\.tempoBPM),
                range: 60...180
            )

            Stepper(value: viewModel.exportOptionsBinding(\.repeatCount), in: 1...8) {
                Text("Repeat Count: \(viewModel.exportOptions.repeatCount)x")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.82))
            }

            HStack(spacing: 10) {
                actionButton("Restart", color: .mint, action: viewModel.restartLoopPlayback)
                actionButton("Pause", color: .orange, action: viewModel.pauseLoopPlayback)
                actionButton("Clear", color: .red, action: viewModel.clearLoop)
            }

            Text("Loop playback now follows the recorded event timing instead of dividing the phrase evenly. Export writes the current loop as a multi-track MIDI clip with one musical track per layer.")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.62))
        }
        .panelStyle(fill: Color(red: 0.08, green: 0.19, blue: 0.15).opacity(0.54))
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

            HStack(spacing: 10) {
                liveMetricCard(title: "Beat", value: "\(Int(viewModel.liveBeatConfidence * 100))%")
                liveMetricCard(title: "Velocity", value: String(format: "%.2f", viewModel.liveRightHandVelocity))
                liveMetricCard(title: "Pinch", value: "\(Int(viewModel.liveRightHandPinch * 100))%")
                liveMetricCard(title: "Spread", value: "\(Int(viewModel.liveRightHandSpread * 100))%")
            }

            Text(viewModel.liveGestureIntentText)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.cyan.opacity(0.9))

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
                liveTip("Hand spread and roll now feed dynamics and orchestration shape.")
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.black.opacity(0.14))
        )
    }

    private var calibrationPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Calibration")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Spacer()
                actionButton("Reset", color: .red, action: viewModel.resetCalibration)
            }

            sliderRow(title: "Center X", value: viewModel.calibrationBinding(\.centerX), range: -0.4...0.4)
            sliderRow(title: "Center Y", value: viewModel.calibrationBinding(\.centerY), range: -0.4...0.4)
            sliderRow(title: "Horizontal Reach", value: viewModel.calibrationBinding(\.horizontalReach), range: 0.45...1.4)
            sliderRow(title: "Vertical Reach", value: viewModel.calibrationBinding(\.verticalReach), range: 0.45...1.4)
            sliderRow(title: "Pinch Floor", value: viewModel.calibrationBinding(\.pinchFloor), range: 0...0.5)
            sliderRow(title: "Pinch Ceiling", value: viewModel.calibrationBinding(\.pinchCeiling), range: 0.45...1.0)
            sliderRow(title: "Velocity Scale", value: viewModel.calibrationBinding(\.velocityScale), range: 0.45...1.75)

            Text("Calibration remaps the incoming camera gesture values before the harmonic engine sees them. Use it to compensate for camera placement and pinch sensitivity.")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.58))
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.black.opacity(0.14))
        )
    }

    private var instrumentPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Instrument Targets")
                    .sectionTitle()
                Spacer()
                actionButton("Refresh", color: .cyan, action: viewModel.refreshStandaloneInstruments)
            }

            TextField("Search instruments, makers, formats, hostability", text: $viewModel.instrumentSearchText)
                .textFieldStyle(.roundedBorder)

            Picker("Instrument", selection: $viewModel.selectedInstrumentID) {
                ForEach(viewModel.browseInstrumentOptions) { instrument in
                    Text("\(instrument.name) · \(instrument.format.rawValue)").tag(instrument.id)
                }
            }
            .pickerStyle(.menu)

            Text(viewModel.instrumentCatalogStatusText)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.68))

            if viewModel.filteredInstruments.isEmpty {
                Text("No instruments match the current search.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.56))
            } else {
                ForEach(viewModel.filteredInstruments) { instrument in
                    HStack(alignment: .top, spacing: 12) {
                        Circle()
                            .fill(instrument.id == viewModel.selectedInstrumentID ? Color.orange : Color.white.opacity(0.22))
                            .frame(width: 10, height: 10)
                            .padding(.top, 4)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(instrument.name)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white)
                            Text(viewModel.instrumentCatalogLine(for: instrument))
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.62))
                        }
                    }
                }
            }

            Divider()
                .overlay(Color.white.opacity(0.08))

            HStack {
                Text("Library Folders")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Spacer()
                actionButton("Add Folder", color: .mint, action: viewModel.addLibraryFolder)
            }

            if viewModel.libraryFolders.isEmpty {
                Text("No library folders added yet.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.56))
            } else {
                ForEach(viewModel.libraryFolders) { folder in
                    HStack(alignment: .top, spacing: 12) {
                        Circle()
                            .fill(Color.cyan.opacity(0.8))
                            .frame(width: 10, height: 10)
                            .padding(.top, 4)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(folder.displayName)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white)
                            Text(folder.summaryText)
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.66))
                            Text(folder.path)
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.56))
                        }

                        Spacer()

                        Button("Remove") {
                            viewModel.removeLibraryFolder(id: folder.id)
                        }
                        .buttonStyle(.borderless)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.red.opacity(0.88))
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

    private func layerAssignmentRow(layerName: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(layerName)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(viewModel.layerAssignmentSummary(for: layerName))
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(viewModel.isLayerAssignmentHostable(layerName) ? .mint : .white.opacity(0.58))
                }
                Spacer()
                if let loadedName = viewModel.standaloneLoadedLayerNames[layerName] {
                    Text(loadedName)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.76))
                }
            }

            Picker("\(layerName) Instrument", selection: viewModel.layerInstrumentBinding(for: layerName)) {
                Text("Unassigned").tag("")
                ForEach(viewModel.layerInstrumentOptions(for: layerName)) { instrument in
                    Text("\(instrument.name) · \(instrument.format.rawValue)").tag(instrument.id)
                }
            }
            .pickerStyle(.menu)

            let libraryTargets = viewModel.layerLibraryTargetOptions(for: layerName)
            if libraryTargets.isEmpty == false {
                Picker("\(layerName) Library Voice", selection: viewModel.layerLibraryTargetBinding(for: layerName)) {
                    ForEach(libraryTargets) { target in
                        Text(target.displayName).tag(target.id)
                    }
                }
                .pickerStyle(.menu)

                if let targetSummary = viewModel.layerLibraryTargetSummary(for: layerName) {
                    Text(targetSummary)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.cyan.opacity(0.82))
                }
            }

            if let topology = viewModel.loadedLayerTopologyText(for: layerName) {
                Text(topology)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.58))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black.opacity(0.14))
        )
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

    private func liveMetricCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.48))
            Text(value)
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
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
