import ConductorCore
import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: SessionViewModel
    @ObservedObject var workspace: WorkspaceState
    @ObservedObject var preferences: AppPreferences

    private var activeSection: WorkspaceSection {
        workspace.selectedSection ?? preferences.launchSection
    }

    private var editedLayerName: String {
        if let selectedLayerName = workspace.selectedLayerName,
           PerformanceLayerPlanner.layerNames.contains(selectedLayerName) {
            return selectedLayerName
        }
        return PerformanceLayerPlanner.layerNames.first ?? ""
    }

    private var selectedLayerState: LayerState? {
        viewModel.effectiveLayers.first { $0.name == editedLayerName }
    }

    private var selectedInstrumentBinding: Binding<String?> {
        Binding(
            get: { viewModel.selectedInstrumentID.isEmpty ? nil : viewModel.selectedInstrumentID },
            set: { viewModel.selectedInstrumentID = $0 ?? "" }
        )
    }

    private var selectedSceneBinding: Binding<String?> {
        Binding(
            get: { viewModel.selectedScenePresetID.isEmpty ? nil : viewModel.selectedScenePresetID },
            set: { viewModel.selectScenePreset(id: $0 ?? "") }
        )
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            HSplitView {
                detailColumn
                    .frame(minWidth: 860, maxWidth: .infinity, maxHeight: .infinity)

                inspectorColumn
                    .frame(
                        minWidth: preferences.compactInspector ? 240 : 280,
                        idealWidth: preferences.compactInspector ? 280 : 320,
                        maxWidth: preferences.compactInspector ? 320 : 360,
                        maxHeight: .infinity
                    )
                    .background(Color(nsColor: .underPageBackgroundColor))
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    viewModel.saveNewScenePreset()
                } label: {
                    Label("Save Scene", systemImage: "square.and.arrow.down")
                }

                Button {
                    if viewModel.routingMode == .logicBridge {
                        viewModel.silenceMIDINotes()
                    } else {
                        viewModel.silenceStandaloneNotes()
                    }
                } label: {
                    Label("Panic", systemImage: "speaker.slash")
                }
            }
        }
        .onAppear { workspace.selectFirstLayerIfNeeded() }
        .onChange(of: preferences.showCalibrationByDefault) {
            workspace.showsCalibration = preferences.showCalibrationByDefault
        }
        .onChange(of: preferences.showGestureGuideByDefault) {
            workspace.showsGestureGuide = preferences.showGestureGuideByDefault
        }
        .onChange(of: preferences.showMIDISummaryByDefault) {
            workspace.showsMIDISummary = preferences.showMIDISummaryByDefault
        }
        .onChange(of: preferences.showSignalPathsByDefault) {
            workspace.showsSignalPaths = preferences.showSignalPathsByDefault
        }
    }

    private var sidebar: some View {
        List(selection: $workspace.selectedSection) {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("The Conductor")
                        .font(.title3.weight(.semibold))
                    Text("Hand-led harmony for standalone performance and Logic sessions.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }

            Section("Perform") {
                sidebarItem(.dashboard)
                sidebarItem(.loop)
                sidebarItem(.scenes)
            }

            Section("Configure") {
                sidebarItem(.sound)
                sidebarItem(.layers)
                sidebarItem(.tracking)
                sidebarItem(.library)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("The Conductor")
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                Divider()
                Label(viewModel.routingMode.rawValue, systemImage: "cable.connector")
                    .font(.caption.weight(.semibold))
                Label(viewModel.trackingMode.rawValue, systemImage: "hand.raised")
                    .font(.caption.weight(.semibold))
                Text(viewModel.performanceState.loopBuffer.statusLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(.bar)
        }
    }

    private func sidebarItem(_ section: WorkspaceSection) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(section.title, systemImage: section.systemImage)
            Text(sidebarDetail(for: section))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .tag(section as WorkspaceSection?)
    }

    private var detailColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                detailHeader
                performanceStageCard
                sectionContent
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var detailHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(activeSection.title)
                .font(.largeTitle.weight(.semibold))

            Text(activeSection.subtitle)
                .font(.body)
                .foregroundStyle(.secondary)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    infoBadge(text: viewModel.routingMode.rawValue, systemImage: "cable.connector")
                    infoBadge(text: viewModel.trackingMode.rawValue, systemImage: "hand.raised")
                    infoBadge(text: viewModel.performanceState.loopBuffer.statusLabel, systemImage: "repeat")
                    infoBadge(text: viewModel.performanceState.isPerforming ? "Live" : "Standby", systemImage: "waveform")
                }

                VStack(alignment: .leading, spacing: 8) {
                    infoBadge(text: viewModel.routingMode.rawValue, systemImage: "cable.connector")
                    infoBadge(text: viewModel.trackingMode.rawValue, systemImage: "hand.raised")
                    infoBadge(text: viewModel.performanceState.loopBuffer.statusLabel, systemImage: "repeat")
                    infoBadge(text: viewModel.performanceState.isPerforming ? "Live" : "Standby", systemImage: "waveform")
                }
            }
        }
    }

    private var performanceStageCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Performance", systemImage: "dial.medium")
                .font(.headline)

            Text(viewModel.performanceState.activityText)
                .font(.headline)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 160), spacing: 12)],
                alignment: .leading,
                spacing: 12
            ) {
                overviewMetric(title: "Current Chord", value: viewModel.performanceState.currentChord.symbol)
                overviewMetric(title: "Preview", value: viewModel.performanceState.previewChord.symbol)
                overviewMetric(title: "Interval", value: viewModel.performanceState.interval.spokenName)
                overviewMetric(title: "Dynamics", value: "\(Int(viewModel.performanceState.dynamics * 100))%")
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    CirclePlotView(
                        title: "Chord Orbit",
                        subtitle: "Right hand steers harmonic direction.",
                        labels: viewModel.chordLabels,
                        point: viewModel.performanceState.chordPlot,
                        accent: .orange
                    )

                    CirclePlotView(
                        title: "Interval Orbit",
                        subtitle: "Left hand shapes interval color.",
                        labels: viewModel.intervalLabels,
                        point: viewModel.performanceState.intervalPlot,
                        accent: .blue
                    )
                }

                VStack(spacing: 16) {
                    CirclePlotView(
                        title: "Chord Orbit",
                        subtitle: "Right hand steers harmonic direction.",
                        labels: viewModel.chordLabels,
                        point: viewModel.performanceState.chordPlot,
                        accent: .orange
                    )

                    CirclePlotView(
                        title: "Interval Orbit",
                        subtitle: "Left hand shapes interval color.",
                        labels: viewModel.intervalLabels,
                        point: viewModel.performanceState.intervalPlot,
                        accent: .blue
                    )
                }
            }
        }
        .conductorCardStyle()
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch activeSection {
        case .dashboard:
            dashboardSection
        case .sound:
            soundSection
        case .layers:
            layersSection
        case .tracking:
            trackingSection
        case .library:
            librarySection
        case .scenes:
            scenesSection
        case .loop:
            loopSection
        }
    }

    private var dashboardSection: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 280), spacing: 16)],
            alignment: .leading,
            spacing: 16
        ) {
            GroupBox("Session Overview") {
                VStack(alignment: .leading, spacing: 10) {
                    LabeledContent("Routing", value: viewModel.routingMode.rawValue)
                    LabeledContent("Tracking", value: viewModel.trackingMode.rawValue)
                    LabeledContent("Key Center", value: viewModel.keyCenter.displayName)
                    LabeledContent("Selected Target", value: viewModel.selectedInstrument?.name ?? "None")
                    LabeledContent("Loop", value: viewModel.loopTransportStatusText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("Quick Actions") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Use the sidebar to stay focused on one job at a time. The performance canvas remains visible, while deeper controls move into task-specific sections.")
                        .foregroundStyle(.secondary)

                    HStack {
                        actionButton("Save Scene", systemImage: "square.and.arrow.down", prominent: true, action: viewModel.saveNewScenePreset)
                        actionButton("Export MIDI", systemImage: "square.and.arrow.up", action: viewModel.exportLoopAsMIDI)
                    }

                    HStack {
                        actionButton("Refresh Library", systemImage: "arrow.clockwise", action: viewModel.refreshStandaloneInstruments)
                        if viewModel.routingMode == .logicBridge {
                            actionButton("Refresh MIDI", systemImage: "arrow.triangle.2.circlepath", action: viewModel.refreshMIDIDestinations)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("Current Focus") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("The interface now follows a macOS split-view pattern: navigation in the sidebar, the two-circle performance surface in the center, and a compact inspector for state and quick actions.")
                    Text("Advanced controls like calibration, signal paths, and MIDI channel summaries are now hidden until they’re relevant.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var soundSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox("Routing") {
                VStack(alignment: .leading, spacing: 14) {
                    Picker("Mode", selection: $viewModel.routingMode) {
                        ForEach(RoutingMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    HStack(alignment: .firstTextBaseline) {
                        Picker("Key Center", selection: $viewModel.keyCenter) {
                            ForEach(PitchClass.allCases) { pitch in
                                Text(pitch.displayName).tag(pitch)
                            }
                        }
                        .pickerStyle(.menu)

                        Spacer()
                    }

                    Text(viewModel.routingDescription)
                        .foregroundStyle(.secondary)
                }
            }

            if viewModel.routingMode == .standaloneHost {
                GroupBox("Standalone Host") {
                    VStack(alignment: .leading, spacing: 12) {
                        LabeledContent("Engine", value: viewModel.isStandaloneEngineRunning ? "Running" : "Stopped")
                        LabeledContent("Layer Loading", value: viewModel.isStandaloneInstrumentLoaded ? "Ready" : "Discovery only")
                        if let loadedInstrumentName = viewModel.standaloneLoadedInstrumentName {
                            LabeledContent("Current Assignment", value: loadedInstrumentName)
                        }

                        Text(viewModel.standaloneHostStatusText)
                            .foregroundStyle(.secondary)
                        Text(viewModel.standaloneSupportText)
                            .foregroundStyle(.secondary)
                            .foregroundColor(viewModel.isStandaloneInstrumentLoaded ? nil : .orange)

                        HStack {
                            actionButton("Assign Selected to All", systemImage: "arrowshape.right.circle", action: viewModel.assignSelectedInstrumentToAllLayers)
                            actionButton("Clear Layers", systemImage: "xmark.circle", action: viewModel.clearLayerAssignments)
                        }

                        HStack {
                            actionButton("Unload", systemImage: "tray.and.arrow.down", action: viewModel.unloadStandaloneAssignments)
                            actionButton("Panic", systemImage: "speaker.slash", role: .destructive, action: viewModel.silenceStandaloneNotes)
                        }

                        if viewModel.standaloneLoadedLayerSummary.isEmpty == false {
                            DisclosureGroup("Loaded Signal Paths", isExpanded: $workspace.showsSignalPaths) {
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(viewModel.standaloneLoadedLayerSummary, id: \.self) { line in
                                        Text(line)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 8)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                GroupBox("Logic Bridge") {
                    VStack(alignment: .leading, spacing: 12) {
                        LabeledContent("Virtual Source", value: viewModel.virtualMIDISourceName)

                        Toggle("Publish virtual MIDI source", isOn: $viewModel.sendToVirtualMIDISource)

                        Picker("Direct Destination", selection: $viewModel.selectedMIDIDestinationID) {
                            Text("None").tag(LogicMIDIBridgeService.noDestinationID)
                            ForEach(viewModel.midiDestinations) { destination in
                                Text(destination.isLikelyLogicInput ? "\(destination.name) · Logic" : destination.name)
                                    .tag(destination.id)
                            }
                        }
                        .pickerStyle(.menu)

                        Text(viewModel.midiStatusText)
                            .foregroundStyle(.secondary)

                        HStack {
                            actionButton("Refresh MIDI", systemImage: "arrow.clockwise", action: viewModel.refreshMIDIDestinations)
                            actionButton("Reset Layer MIDI", systemImage: "slider.horizontal.3", action: viewModel.resetLayerMIDIRoutingSettings)
                            actionButton("All Notes Off", systemImage: "speaker.slash", role: .destructive, action: viewModel.silenceMIDINotes)
                        }

                        DisclosureGroup("Layer Channel Summary", isExpanded: $workspace.showsMIDISummary) {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(viewModel.midiChannelMapDescription, id: \.self) { line in
                                    Text(line)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 8)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var layersSection: some View {
        HSplitView {
            GroupBox("Layers") {
                List(selection: $workspace.selectedLayerName) {
                    ForEach(viewModel.effectiveLayers) { layer in
                        VStack(alignment: .leading, spacing: 4) {
                            Label(layer.name, systemImage: layer.isEnabled ? "speaker.wave.2" : "speaker.slash")
                            Text(layer.mixDescription)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(layer.name as String?)
                    }
                }
                .frame(minWidth: 220, idealWidth: 240, minHeight: 520)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    GroupBox("Mix") {
                        VStack(alignment: .leading, spacing: 12) {
                            if let selectedLayerState {
                                LabeledContent("Current Mix", value: "\(Int(selectedLayerState.mix * 100))%")
                            }

                            Toggle("Enable Layer", isOn: viewModel.layerEnabledBinding(for: editedLayerName))

                            Slider(value: viewModel.layerGainBinding(for: editedLayerName), in: 0...1.5)

                            Text(mixSummaryText(for: editedLayerName))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    GroupBox("Performance") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(viewModel.layerPerformanceSummary(for: editedLayerName))
                                .foregroundStyle(.secondary)

                            Picker("Articulation", selection: viewModel.layerArticulationBinding(for: editedLayerName)) {
                                ForEach(LayerArticulationStyle.allCases) { articulation in
                                    Text("\(articulation.rawValue) · \(articulation.summaryText)").tag(articulation)
                                }
                            }
                            .pickerStyle(.menu)

                            compactStepperRow(
                                title: "Register",
                                value: viewModel.layerPerformanceIntBinding(for: editedLayerName, keyPath: \.octaveShift),
                                range: -2...2,
                                valueText: { value in
                                    value == 0 ? "0 oct" : "\(value > 0 ? "+" : "")\(value) oct"
                                }
                            )

                            compactStepperRow(
                                title: "Voices",
                                value: viewModel.layerPerformanceIntBinding(for: editedLayerName, keyPath: \.maxVoices),
                                range: 1...5,
                                valueText: { value in "\(value)" }
                            )

                            sliderRow(
                                title: "Velocity Bias",
                                value: viewModel.layerPerformanceDoubleBinding(for: editedLayerName, keyPath: \.velocityBias),
                                range: -24...24
                            )

                            sliderRow(
                                title: "Length Scale",
                                value: viewModel.layerPerformanceDoubleBinding(for: editedLayerName, keyPath: \.holdScale),
                                range: 0.25...1.8
                            )
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if viewModel.routingMode == .standaloneHost {
                        layerAssignmentEditor(for: editedLayerName)
                    } else {
                        layerMIDIRoutingEditor(for: editedLayerName)
                    }

                    GroupBox("Output") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(viewModel.layerOutputSummary(for: editedLayerName))
                                .foregroundStyle(.secondary)

                            Picker("Bus", selection: viewModel.layerOutputBusBinding(for: editedLayerName)) {
                                ForEach(LayerOutputBus.allCases) { bus in
                                    Text("\(bus.rawValue) · \(bus.summaryText)").tag(bus)
                                }
                            }
                            .pickerStyle(.menu)

                            sliderRow(
                                title: "Pan",
                                value: viewModel.layerOutputScalarBinding(for: editedLayerName, keyPath: \.pan),
                                range: -1...1
                            )
                            sliderRow(
                                title: "Space",
                                value: viewModel.layerOutputScalarBinding(for: editedLayerName, keyPath: \.reverbMix),
                                range: 0...100
                            )
                            sliderRow(
                                title: "Echo",
                                value: viewModel.layerOutputScalarBinding(for: editedLayerName, keyPath: \.delayMix),
                                range: 0...100
                            )
                            sliderRow(
                                title: "Echo Time",
                                value: viewModel.layerOutputScalarBinding(for: editedLayerName, keyPath: \.delayTime),
                                range: 0.05...0.65
                            )
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.leading, 4)
                .padding(.bottom, 4)
            }
            .frame(minWidth: 500, minHeight: 520)
        }
        .frame(minHeight: 560)
    }

    private var trackingSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox("Tracking Source") {
                VStack(alignment: .leading, spacing: 14) {
                    Picker("Input", selection: $viewModel.trackingMode) {
                        ForEach(TrackingMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    if viewModel.isLiveTracking {
                        liveTrackingSection
                    } else {
                        simulatorSection
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            DisclosureGroup("Calibration", isExpanded: $workspace.showsCalibration) {
                VStack(alignment: .leading, spacing: 12) {
                    sliderRow(title: "Center X", value: viewModel.calibrationBinding(\.centerX), range: -0.4...0.4)
                    sliderRow(title: "Center Y", value: viewModel.calibrationBinding(\.centerY), range: -0.4...0.4)
                    sliderRow(title: "Horizontal Reach", value: viewModel.calibrationBinding(\.horizontalReach), range: 0.45...1.4)
                    sliderRow(title: "Vertical Reach", value: viewModel.calibrationBinding(\.verticalReach), range: 0.45...1.4)
                    sliderRow(title: "Pinch Floor", value: viewModel.calibrationBinding(\.pinchFloor), range: 0...0.5)
                    sliderRow(title: "Pinch Ceiling", value: viewModel.calibrationBinding(\.pinchCeiling), range: 0.45...1.0)
                    sliderRow(title: "Velocity Scale", value: viewModel.calibrationBinding(\.velocityScale), range: 0.45...1.75)

                    actionButton("Reset Calibration", systemImage: "arrow.uturn.backward", action: viewModel.resetCalibration)

                    Text("Calibration is treated as an advanced tool so it doesn’t crowd the primary workflow.")
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 12)
            }
            .conductorCardStyle()

            DisclosureGroup("Gesture Vocabulary", isExpanded: $workspace.showsGestureGuide) {
                VStack(alignment: .leading, spacing: 8) {
                    gestureGuideLine("Right-hand wrist position previews chord direction.")
                    gestureGuideLine("Right-hand pinch commits the previewed chord.")
                    gestureGuideLine("Fast open-handed downbeat engages the ensemble.")
                    gestureGuideLine("Both hands pinched toggles loop capture.")
                    gestureGuideLine("Left-hand position selects interval focus.")
                    gestureGuideLine("Hand spread and roll shape dynamics and orchestration density.")
                }
                .padding(.top, 12)
            }
            .conductorCardStyle()
        }
    }

    private var librarySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox("Instrument Browser") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        TextField("Search instruments, makers, formats, hostability", text: $viewModel.instrumentSearchText)
                        actionButton("Refresh", systemImage: "arrow.clockwise", action: viewModel.refreshStandaloneInstruments)
                    }

                    HSplitView {
                        List(selection: selectedInstrumentBinding) {
                            ForEach(viewModel.filteredInstruments) { instrument in
                                VStack(alignment: .leading, spacing: 4) {
                                    Label(instrument.name, systemImage: instrumentSymbol(for: instrument.format))
                                    Text(viewModel.instrumentCatalogLine(for: instrument))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .tag(instrument.id as String?)
                            }
                        }
                        .frame(minWidth: 340, idealWidth: 380, minHeight: 320)

                        VStack(alignment: .leading, spacing: 12) {
                            if let instrument = viewModel.selectedInstrument {
                                Text(instrument.name)
                                    .font(.title3.weight(.semibold))
                                LabeledContent("Format", value: instrument.format.rawValue)
                                LabeledContent("Source", value: instrument.source)
                                LabeledContent("Hostability", value: viewModel.isSelectedInstrumentHostableNow ? "Playable now" : "Discovery only")
                                Text(viewModel.instrumentCatalogLine(for: instrument))
                                    .foregroundStyle(.secondary)

                                if viewModel.routingMode == .standaloneHost {
                                    actionButton("Assign Selected to All Layers", systemImage: "arrowshape.right.circle", prominent: true, action: viewModel.assignSelectedInstrumentToAllLayers)
                                }
                            } else {
                                Text("Select an instrument to inspect its route and capability details.")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(.leading, 16)
                    }

                    Text(viewModel.instrumentCatalogStatusText)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("Library Folders") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        actionButton("Add Folder", systemImage: "plus", prominent: true, action: viewModel.addLibraryFolder)
                        Spacer()
                    }

                    if viewModel.libraryFolders.isEmpty {
                        Text("No library folders added yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        List {
                            ForEach(viewModel.libraryFolders) { folder in
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(folder.displayName)
                                            .font(.headline)
                                        Text(folder.summaryText)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text(folder.path)
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                    Spacer()
                                    Button("Remove") {
                                        viewModel.removeLibraryFolder(id: folder.id)
                                    }
                                }
                            }
                        }
                        .frame(minHeight: 180)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var scenesSection: some View {
        HSplitView {
            GroupBox("Saved Scenes") {
                if viewModel.scenePresets.isEmpty {
                    ContentUnavailableView(
                        "No Saved Scenes",
                        systemImage: "square.stack",
                        description: Text("Save the current setup to reuse routing, calibration, layers, and scene state.")
                    )
                    .frame(minWidth: 260, minHeight: 320)
                } else {
                    List(selection: selectedSceneBinding) {
                        ForEach(viewModel.scenePresets) { preset in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(preset.name)
                                Text(preset.summaryText)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(preset.updatedAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            .tag(preset.id.uuidString as String?)
                        }
                    }
                    .frame(minWidth: 280, idealWidth: 320, minHeight: 360)
                }
            }

            VStack(alignment: .leading, spacing: 16) {
                GroupBox("Scene Details") {
                    VStack(alignment: .leading, spacing: 12) {
                        TextField("Scene Name", text: $viewModel.scenePresetName)

                        if let selectedPreset = viewModel.selectedScenePreset {
                            LabeledContent("Selected", value: selectedPreset.name)
                            Text(selectedPreset.summaryText)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("No scene selected.")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("Actions") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            actionButton("Save New", systemImage: "plus", prominent: true, action: viewModel.saveNewScenePreset)
                            actionButton("Load", systemImage: "arrow.down.circle", action: viewModel.loadSelectedScenePreset)
                        }

                        HStack {
                            actionButton("Update", systemImage: "square.and.pencil", action: viewModel.updateSelectedScenePreset)
                            actionButton("Delete", systemImage: "trash", role: .destructive, action: viewModel.deleteSelectedScenePreset)
                        }

                        Text("Scenes capture the full local setup, so they now live in their own focused section rather than being mixed into the main control rail.")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(minWidth: 360, maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(minHeight: 420)
    }

    private var loopSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox("Loop Transport") {
                VStack(alignment: .leading, spacing: 12) {
                    Text(viewModel.loopTransportStatusText)
                        .font(.headline)

                    Text("Playback follows captured event timing instead of an evenly divided bar.")
                        .foregroundStyle(.secondary)

                    HStack {
                        actionButton("Restart", systemImage: "gobackward", prominent: true, action: viewModel.restartLoopPlayback)
                        actionButton("Pause", systemImage: "pause", action: viewModel.pauseLoopPlayback)
                        actionButton("Clear", systemImage: "trash", role: .destructive, action: viewModel.clearLoop)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("MIDI Export") {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Clip Name", text: viewModel.exportOptionsBinding(\.clipName))

                    sliderRow(
                        title: "Tempo",
                        value: viewModel.exportOptionsBinding(\.tempoBPM),
                        range: 60...180
                    )

                    Stepper(value: viewModel.exportOptionsBinding(\.repeatCount), in: 1...8) {
                        Text("Repeat Count: \(viewModel.exportOptions.repeatCount)x")
                    }

                    Text(viewModel.exportStatusText)
                        .foregroundStyle(.secondary)

                    actionButton("Export MIDI", systemImage: "square.and.arrow.up", prominent: true, action: viewModel.exportLoopAsMIDI)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var liveTrackingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabeledContent("Authorization", value: viewModel.cameraAuthorizationStatusText)

            Text(viewModel.liveTrackingStatusText)
                .foregroundStyle(.secondary)

            HStack {
                actionButton("Start Camera", systemImage: "play.fill", prominent: true, action: viewModel.startLiveTracking)
                actionButton("Stop Camera", systemImage: "stop.fill", role: .destructive, action: viewModel.stopLiveTracking)
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 120), spacing: 12)],
                alignment: .leading,
                spacing: 12
            ) {
                overviewMetric(title: "Beat", value: "\(Int(viewModel.liveBeatConfidence * 100))%")
                overviewMetric(title: "Velocity", value: String(format: "%.2f", viewModel.liveRightHandVelocity))
                overviewMetric(title: "Pinch", value: "\(Int(viewModel.liveRightHandPinch * 100))%")
                overviewMetric(title: "Spread", value: "\(Int(viewModel.liveRightHandSpread * 100))%")
            }

            Text(viewModel.liveGestureIntentText)
                .font(.headline)

            CameraPreviewView(session: viewModel.captureSession)
                .frame(minHeight: 280, maxHeight: 340)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                )
        }
    }

    private var simulatorSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                actionButton("Downbeat", systemImage: "metronome", prominent: true, action: viewModel.pulseDownbeat)
                actionButton("Commit", systemImage: "checkmark.circle", action: viewModel.pulseCommit)
                actionButton("Loop", systemImage: "repeat", action: viewModel.pulseLoopToggle)
                actionButton("Stop", systemImage: "stop.circle", role: .destructive, action: viewModel.pulseStop)
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) {
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

                VStack(spacing: 16) {
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
        }
    }

    private var inspectorColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox("Session") {
                    VStack(alignment: .leading, spacing: 10) {
                        LabeledContent("Section", value: activeSection.title)
                        LabeledContent("Routing", value: viewModel.routingMode.rawValue)
                        LabeledContent("Tracking", value: viewModel.trackingMode.rawValue)
                        LabeledContent("Key Center", value: viewModel.keyCenter.displayName)
                        LabeledContent("Target", value: viewModel.selectedInstrument?.name ?? "None")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("Current Performance") {
                    VStack(alignment: .leading, spacing: 12) {
                        overviewMetric(title: "Chord", value: viewModel.performanceState.currentChord.symbol)
                        overviewMetric(title: "Preview", value: viewModel.performanceState.previewChord.symbol)
                        overviewMetric(title: "Interval", value: viewModel.performanceState.interval.spokenName)
                        overviewMetric(title: "Dynamics", value: "\(Int(viewModel.performanceState.dynamics * 100))%")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if viewModel.isLiveTracking {
                    GroupBox("Live Metrics") {
                        VStack(alignment: .leading, spacing: 10) {
                            LabeledContent("Beat", value: "\(Int(viewModel.liveBeatConfidence * 100))%")
                            LabeledContent("Velocity", value: String(format: "%.2f", viewModel.liveRightHandVelocity))
                            LabeledContent("Pinch", value: "\(Int(viewModel.liveRightHandPinch * 100))%")
                            LabeledContent("Spread", value: "\(Int(viewModel.liveRightHandSpread * 100))%")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                GroupBox("Quick Actions") {
                    VStack(alignment: .leading, spacing: 10) {
                        actionButton("Save Scene", systemImage: "square.and.arrow.down", action: viewModel.saveNewScenePreset)
                        actionButton("Export MIDI", systemImage: "square.and.arrow.up", action: viewModel.exportLoopAsMIDI)

                        if viewModel.routingMode == .logicBridge {
                            actionButton("All Notes Off", systemImage: "speaker.slash", role: .destructive, action: viewModel.silenceMIDINotes)
                        } else {
                            actionButton("Panic", systemImage: "speaker.slash", role: .destructive, action: viewModel.silenceStandaloneNotes)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(20)
        }
        .controlSize(.small)
    }

    private func layerAssignmentEditor(for layerName: String) -> some View {
        GroupBox("Standalone Assignment") {
            VStack(alignment: .leading, spacing: 12) {
                Text(viewModel.layerAssignmentSummary(for: layerName))
                    .foregroundStyle(.secondary)
                    .foregroundColor(viewModel.isLayerAssignmentHostable(layerName) ? nil : .orange)

                Picker("Instrument", selection: viewModel.layerInstrumentBinding(for: layerName)) {
                    Text("Unassigned").tag("")
                    ForEach(viewModel.layerInstrumentOptions(for: layerName)) { instrument in
                        Text("\(instrument.name) · \(instrument.format.rawValue)").tag(instrument.id)
                    }
                }
                .pickerStyle(.menu)

                let libraryTargets = viewModel.layerLibraryTargetOptions(for: layerName)
                if libraryTargets.isEmpty == false {
                    Toggle("Follow Layer Articulation", isOn: viewModel.layerLibraryFollowBinding(for: layerName))

                    if viewModel.isLayerLibraryFollowingArticulation(layerName) {
                        if let selectedTarget = viewModel.selectedLayerLibraryTarget(for: layerName) {
                            Text("Auto target: \(selectedTarget.displayName) · \(selectedTarget.articulationFamily.displayName)")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Picker("Library Voice", selection: viewModel.layerLibraryTargetBinding(for: layerName)) {
                            ForEach(libraryTargets) { target in
                                Text("\(target.displayName) · \(target.articulationFamily.displayName)").tag(target.id)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    if let targetSummary = viewModel.layerLibraryTargetSummary(for: layerName) {
                        Text(targetSummary)
                            .foregroundStyle(.secondary)
                    }
                }

                if let topology = viewModel.loadedLayerTopologyText(for: layerName) {
                    Text(topology)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func layerMIDIRoutingEditor(for layerName: String) -> some View {
        GroupBox("MIDI Routing") {
            VStack(alignment: .leading, spacing: 12) {
                Text(viewModel.layerMIDIRoutingSummary(for: layerName))
                    .foregroundStyle(.secondary)

                compactStepperRow(
                    title: "MIDI Channel",
                    value: viewModel.layerMIDIIntBinding(for: layerName, keyPath: \.channelNumber),
                    range: 1...16,
                    valueText: { value in "Ch \(value)" }
                )

                sliderRow(
                    title: "Expression CC11",
                    value: viewModel.layerMIDIDoubleBinding(for: layerName, keyPath: \.expressionDepth),
                    range: 0...1
                )

                sliderRow(
                    title: "Mod Wheel CC1",
                    value: viewModel.layerMIDIDoubleBinding(for: layerName, keyPath: \.modulationDepth),
                    range: 0...1
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
                .font(.headline)

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
        .conductorCardStyle()
    }

    private func sliderRow(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.2f", value.wrappedValue))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
            }
            .font(.subheadline.weight(.medium))

            Slider(value: value, in: range)
        }
    }

    private func compactStepperRow(
        title: String,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        valueText: @escaping (Int) -> String
    ) -> some View {
        HStack(alignment: .center) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Stepper(value: value, in: range) {
                Text(valueText(value.wrappedValue))
                    .monospacedDigit()
            }
            .fixedSize()
        }
        .font(.subheadline.weight(.medium))
    }

    private func overviewMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private func infoBadge(text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
    }

    private func gestureGuideLine(_ text: String) -> some View {
        Label(text, systemImage: "hand.point.up.left.fill")
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func actionButton(
        _ title: String,
        systemImage: String,
        prominent: Bool = false,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        let button = Button(role: role, action: action) {
            Label(title, systemImage: systemImage)
        }
        if prominent {
            button.buttonStyle(.borderedProminent)
        } else {
            button.buttonStyle(.bordered)
        }
    }

    private func sidebarDetail(for section: WorkspaceSection) -> String {
        switch section {
        case .dashboard:
            return viewModel.performanceState.activityText
        case .sound:
            return viewModel.routingMode.rawValue
        case .layers:
            return "\(viewModel.effectiveLayers.count) orchestration layers"
        case .tracking:
            return viewModel.trackingMode.rawValue
        case .library:
            return "\(viewModel.filteredInstruments.count) visible targets"
        case .scenes:
            return viewModel.scenePresets.isEmpty ? "No saved scenes" : "\(viewModel.scenePresets.count) saved scenes"
        case .loop:
            return viewModel.performanceState.loopBuffer.statusLabel
        }
    }

    private func mixSummaryText(for layerName: String) -> String {
        guard let effectiveLayer = viewModel.performanceState.layers.first(where: { $0.name == layerName }) else {
            return "Manual trim applies on top of the generated orchestration mix."
        }
        return "Automatic mix \(Int(effectiveLayer.mix * 100))% with manual output trim applied on top."
    }

    private func instrumentSymbol(for format: InstrumentFormat) -> String {
        switch format {
        case .audioUnit:
            return "pianokeys"
        case .vst3:
            return "shippingbox"
        case .sampleLibrary:
            return "folder"
        }
    }
}

private struct ConductorCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.thinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.4), lineWidth: 1)
            )
    }
}

extension View {
    func conductorCardStyle() -> some View {
        modifier(ConductorCardModifier())
    }
}

private extension LayerState {
    var mixDescription: String {
        "\(Int(mix * 100))% mix · \(isEnabled ? "Enabled" : "Muted")"
    }
}
