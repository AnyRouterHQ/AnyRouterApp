import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Sheet wrapper: the Extract form in its own navigation stack with a Close button.
struct ExtractSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ExtractScreen()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(role: .close) { dismiss() } }
                }
        }
    }
}

/// Typed fields out of a receipt, bill, invoice or email: each answer is linked to the words it came from.
struct ExtractScreen: View {
    @Environment(AppState.self) private var app
    @Environment(ShellModel.self) private var shell
    @State private var session = ExtractSession()
    @State private var showsPhotos = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showsFiles = false
    @State private var showsScanner = false
    @State private var showsAddField = false
    @State private var newFieldName = ""
    @State private var showsModelPicker = false

    private var isSignedIn: Bool {
        if case .signedIn = app.account.state { return true }
        return false
    }

    var body: some View {
        @Bindable var model = session
        ScrollViewReader { proxy in
            Form {
                documentSection
                fieldsSection
                if let message = session.errorMessage {
                    Section { Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
                }
                if !session.fields.isEmpty { resultSection }
                if isSignedIn { readerSection(isOn: $model.usesCloudReader) }
            }
            .onChange(of: session.selectedFieldID) {
                guard let offset = session.selectedRange?.lowerBound,
                      let line = ExtractLogic.lineID(containing: offset, in: session.lines) else { return }
                withAnimation { proxy.scrollTo(line, anchor: .center) }
            }
        }
        .navigationTitle("Extract")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { modelPill }
            if !session.fields.isEmpty {
                ToolbarItem(placement: .topBarTrailing) { ShareLink(item: ExtractLogic.exported(session.fields)) }
            }
        }
        .bottomActionBar(id: "extract-run", isEnabled: session.canExtract) {
            Task { await session.extract() }
        } label: {
            if session.phase == .extracting {
                ProgressView()
            } else {
                Label("Extract", systemImage: "text.viewfinder")
            }
        } accessory: {
            EmptyView()
        }
        .sheet(isPresented: $showsModelPicker) {
            ModelPickerSheet(currentID: session.resolvedModel?.id) { session.choose($0) }
        }
        .photosPicker(isPresented: $showsPhotos, selection: $photoItems, maxSelectionCount: 5, matching: .images)
        .onChange(of: photoItems) { _, items in loadPhotos(items) }
        .fileImporter(isPresented: $showsFiles, allowedContentTypes: [.pdf, .image]) { result in
            switch result {
            case .success(let url): Task { await session.load(file: url) }
            case .failure(let error): session.errorMessage = error.localizedDescription
            }
        }
        .fullScreenCover(isPresented: $showsScanner) {
            DocumentScanner(
                onScan: { pages in Task { await session.load(images: pages, name: "Scan") } },
                onFailure: { session.errorMessage = $0 })
                .ignoresSafeArea()
        }
        .alert("Add field", isPresented: $showsAddField) {
            TextField("Name", text: $newFieldName)
            Button("Add") {
                session.addCustomField(newFieldName)
                newFieldName = ""
            }
            Button("Cancel", role: .cancel) { newFieldName = "" }
        } message: {
            Text("What should be read from the document, for example Tip or Order number.")
        }
        .task {
            session.models = app.models
            session.cloudReader = app.cloudOCR
            if DemoData.isEnabled {
                session.ask = { _, _ in ExtractSession.demoReply }
            } else {
                session.ask = { [app] prompt, modelID in try await HeadlessChat(state: app).ask(prompt, modelID: modelID) }
            }
            if let stage = ExtractSession.demoStage {
                session.applyDemo(stage: stage)
            } else if let seed = shell.takeExtractSeed() {
                await session.load(seed)
            }
        }
    }

    // MARK: Sections

    private var documentSection: some View {
        Section {
            Menu {
                Button("Photos", systemImage: "photo") { showsPhotos = true }
                    .accessibilityIdentifier("extract-photos")
                Button("Files", systemImage: "folder") { showsFiles = true }
                    .accessibilityIdentifier("extract-files")
                Button("Scan", systemImage: "doc.viewfinder") { showsScanner = true }
                    .disabled(!DocumentScanner.isAvailable)
                    .accessibilityIdentifier("extract-scan")
            } label: {
                Label(session.text.isEmpty ? "Choose a document" : "Choose another", systemImage: "doc.badge.plus")
            }
            .accessibilityIdentifier("extract-source")
            if session.phase == .reading {
                ProgressView("Reading")
            } else if session.text.isEmpty {
                Text("A photo, PDF or scan of a receipt, bill, invoice or email. Its text is read on this device.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(session.lines) { line in
                    Text(highlighted(line))
                        .font(.callout)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 1, leading: 20, bottom: 1, trailing: 20))
                }
            }
        } header: {
            Text(session.sourceName ?? "Document")
        } footer: {
            if let note = session.cutNote { Text(note) }
        }
    }

    private var fieldsSection: some View {
        Section {
            Picker("Preset", selection: Binding(get: { session.presetID }, set: { session.choosePreset($0) })) {
                ForEach(ExtractLogic.presets) { Text($0.title).tag($0.id) }
            }
            .accessibilityIdentifier("extract-preset")
            if session.preset.isCustom {
                ForEach(session.customFields) { field in
                    Picker(field.name, selection: Binding(get: { field.kind }, set: { session.setKind($0, ofCustomField: field.name) })) {
                        ForEach(FieldSpec.Kind.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                }
                .onDelete { session.removeCustomFields(at: $0) }
                Button { showsAddField = true } label: { Label("Add field", systemImage: "plus") }
                    .accessibilityIdentifier("extract-add-field")
            }
        } header: {
            Text("Fields")
        } footer: {
            if !session.preset.isCustom { Text(session.preset.fields.map(\.name).joined(separator: ", ")) }
        }
    }

    private var resultSection: some View {
        Section("Result") {
            ForEach(session.fields) { field in
                let isSelected = session.selectedFieldID == field.id
                Button { session.select(field.id) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(field.name).font(.subheadline).foregroundStyle(.secondary)
                        Text(field.value.isEmpty ? "No value" : field.value).font(.headline)
                        if let note = ExtractLogic.note(for: field) {
                            Text(note).font(.footnote).foregroundStyle(.secondary)
                        } else {
                            Text("\u{201C}\(field.quote)\u{201D}").font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .foregroundStyle(.primary)
                .listRowBackground(isSelected ? Color.yellow.opacity(0.25) : nil)
                .accessibilityIdentifier("extract-field-\(field.name)")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }

    private func readerSection(isOn: Binding<Bool>) -> some View {
        Section {
            Toggle("Read with AnyRouter", isOn: isOn)
                .formSwitches()
                .accessibilityIdentifier("extract-cloud-reader")
        } footer: {
            Text("Off: images are read on this device. On: the image is sent to AnyRouter to be read. The chat model is chosen separately.")
        }
    }

    // MARK: Controls

    /// The model as the chat header shows it, logo and short name. It opens the chat's picker.
    private var modelPill: some View {
        let model = session.resolvedModel
        return ModelTitle(
            name: model?.shortName, isLoading: app.models.isLoading, brand: model.map(ModelBrand.resolve(_:)),
            identifier: "extract-model"
        ) { showsModelPicker = true }
    }

    // MARK: Text

    /// The line with every field's source marked, and the chosen field's source marked more.
    private func highlighted(_ line: DocumentLine) -> AttributedString {
        var result = AttributedString(line.text)
        func mark(_ ranges: [Range<Int>], with color: Color) {
            for range in ranges {
                guard let inText = ExtractLogic.stringRange(range, in: line.text),
                      let inResult = Range<AttributedString.Index>(inText, in: result) else { continue }
                result[inResult].backgroundColor = color
            }
        }
        mark(ExtractLogic.localRanges(session.sourceRanges, in: line), with: .yellow.opacity(0.3))
        mark(ExtractLogic.localRanges(session.selectedRange.map { [$0] } ?? [], in: line), with: .yellow.opacity(0.7))
        return result
    }

    private func loadPhotos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        photoItems = []
        Task {
            var images: [Data] = []
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self) { images.append(data) }
            }
            await session.load(images: images, name: items.count == 1 ? "Photo" : "\(items.count) photos")
        }
    }
}
