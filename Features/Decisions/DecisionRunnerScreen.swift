import SwiftUI

/// One screen for every app and the custom decision: paste, add photos, press Run, read the answer.
struct DecisionRunnerScreen: View {
    @Environment(AppState.self) private var app
    @Binding var showsRecent: Bool
    /// The one focus owner for every text input here, so Run can dismiss the keyboard.
    @FocusState private var focus: DecisionField?
    @State private var showsQuestions = false

    var body: some View {
        @Bindable var store = app.decisions
        Form {
            samplesRow(store)
            Section {
                TextField(
                    store.app?.inputHint ?? "Paste an email, a policy, an incident…", text: $store.state, axis: .vertical)
                    .lineLimit(6...14)
                    .focused($focus, equals: .state)
                    .accessibilityIdentifier("decisions-state")
            } footer: {
                if !store.state.isEmpty {
                    Text("\(store.state.count) of \(DecisionsLogic.maxStateCharacters) characters")
                }
            }
            if store.app?.id == DecisionAppsLogic.pasteAppID { PasteCard(state: store.state) }
            if store.showsImageInput || !store.images.isEmpty {
                DecisionPhotoSection(store: store)
            } else if store.app?.acceptsImages ?? true {
                Section { Label("This model reads text only. To add photos, choose another model in the model menu.", systemImage: "photo.badge.exclamationmark").foregroundStyle(.secondary) }
            }
            Section {
                DisclosureGroup("Questions", isExpanded: $showsQuestions) { questionRows($store) }
                    .accessibilityIdentifier("decisions-questions")
            }
            resultSections(store)
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(store.app?.title ?? "Custom decision")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { modelMenu($store) }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showsRecent = true } label: { Label("Recent", systemImage: "clock.arrow.circlepath") }
                    .accessibilityIdentifier("decisions-recent")
            }
        }
        .safeAreaInset(edge: .bottom) { runBar(store) }
        .onAppear { showsQuestions = store.app == nil }
        .task {
            if DemoData.addsDecisionPhoto, store.images.isEmpty, store.showsImageInput { await store.addImages([DemoData.receiptPhoto()]) }
        }
    }

    // MARK: Input

    /// One-tap samples. They sit above the field and fill it (and, for the custom decision, the questions).
    private func samplesRow(_ store: DecisionsStore) -> some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    if let current = store.app {
                        ForEach(current.samples, id: \.title) { sample in
                            Button(sample.title) { store.fill(with: sample) }
                                .accessibilityIdentifier("decisions-sample-\(sample.title)")
                        }
                    } else {
                        ForEach(DecisionsLogic.samples) { sample in
                            Button(sample.title) { store.fill(with: sample) }
                                .accessibilityIdentifier("decisions-sample-\(sample.title)")
                        }
                    }
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .padding(.horizontal)
            }
        }
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
    }

    @ViewBuilder
    private func questionRows(_ store: Bindable<DecisionsStore>) -> some View {
        if let current = store.wrappedValue.app {
            ForEach(current.questions, id: \.id) { question in
                VStack(alignment: .leading) {
                    Text(question.prompt)
                    if !question.list.isEmpty {
                        Text(question.list.joined(separator: ", ")).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
            }
        } else {
            ForEach(store.questions) { $question in QuestionRow(question: $question, focus: $focus) }
                .onDelete { store.wrappedValue.deleteQuestions(at: $0) }
            Menu {
                Button("Yes/No", systemImage: "checkmark.circle") { store.wrappedValue.addQuestion(.yesNo) }
                Button("Choice", systemImage: "list.bullet") { store.wrappedValue.addQuestion(.choice) }
                Button("Score", systemImage: "gauge.medium") { store.wrappedValue.addQuestion(.rubric) }
            } label: {
                Label("Add question", systemImage: "plus")
            }
            .accessibilityIdentifier("decisions-add-question")
        }
    }

    // MARK: Toolbar and Run

    /// The model, one tap away. Also the action when a model cannot read photos.
    private func modelMenu(_ store: Bindable<DecisionsStore>) -> some View {
        Menu {
            if store.wrappedValue.models.isEmpty {
                Text(store.wrappedValue.modelsError ?? "Loading decision models")
            } else {
                Picker("Model", selection: store.modelID) {
                    ForEach(store.wrappedValue.models) { Text($0.name).tag($0.id) }
                }
            }
        } label: {
            Label(store.wrappedValue.selectedModel?.name ?? "Model", systemImage: "cpu")
        }
        .accessibilityIdentifier("decisions-model")
    }

    private func runBar(_ store: DecisionsStore) -> some View {
        VStack(spacing: 8) {
            if let reason = store.blocker, store.phase != .running {
                Text(reason).font(.footnote).foregroundStyle(.secondary)
            }
            Button {
                focus = nil
                Task { await store.run() }
            } label: {
                Text(store.phase == .running ? "Running" : "Run").prominentLabel().frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!store.canRun)
            .accessibilityIdentifier("decisions-run")
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
        .padding(.top, 8)
        .background(.bar)
    }

    // MARK: Result

    @ViewBuilder
    private func resultSections(_ store: DecisionsStore) -> some View {
        switch store.phase {
        case .idle:
            EmptyView()
        case .running:
            Section { ProgressView("Running") }
        case .failed(let message, let canChangeModel):
            Section {
                Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                if canChangeModel { modelMenu(Bindable(store)) }
            }
        case .finished(let result):
            Section("Result") {
                Text(store.app.map { DecisionAppsLogic.resultLine($0, result: result) } ?? DecisionAppsLogic.summary(of: result))
                    .font(.title3.weight(.semibold))
                    .accessibilityIdentifier("decisions-result-line")
            }
            ForEach(result.answers) { answer in
                Section { AnswerCard(answer: answer) }
            }
            Section {
                DisclosureGroup("Details") {
                    LabeledContent("Model", value: result.model)
                    LabeledContent("Cost", value: DecisionsLogic.costText(result.cost))
                    LabeledContent("Latency", value: DecisionsLogic.latencyText(result.latency))
                    LabeledContent("Tokens", value: "\(result.inputTokens) in, \(result.outputTokens) out")
                }
            }
        }
    }
}

private enum DecisionField: Hashable {
    case state
    case prompt(QuestionDraft.ID)
    case list(QuestionDraft.ID)
}

private struct QuestionRow: View {
    @Binding var question: QuestionDraft
    var focus: FocusState<DecisionField?>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Type", selection: $question.kind) {
                ForEach(QuestionDraft.Kind.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            TextField("Question", text: $question.prompt, axis: .vertical)
                .focused(focus, equals: .prompt(question.id))
                .accessibilityIdentifier("decisions-question-prompt")
            if let hint = question.kind.listPrompt {
                TextField(hint, text: $question.list, axis: .vertical)
                    .focused(focus, equals: .list(question.id))
            }
            if !question.prompt.isEmpty, let problem = DecisionsLogic.problem(with: question) {
                Text(problem).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

/// One question's answer: a bar for each likely option, the top one in bold, or the answer in words when it has no bars.
private struct AnswerCard: View {
    let answer: DecisionAnswer

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(answer.prompt).font(.subheadline).foregroundStyle(.secondary)
            switch answer.outcome {
            case .answered(let verdict):
                let bars = DecisionAppsLogic.bars(of: verdict)
                if let line = DecisionAppsLogic.answerLine(of: verdict) { Text(line).font(.headline) }
                ForEach(bars, id: \.label) { option in
                    ProgressView(value: option.probability) {
                        Text(option.label).fontWeight(option.label == bars.first?.label ? .semibold : .regular)
                    } currentValueLabel: {
                        Text(DecisionsLogic.percent(option.probability))
                    }
                }
                if let confidence = verdict.confidence {
                    Text("Confidence \(DecisionsLogic.percent(confidence))").font(.footnote).foregroundStyle(.secondary)
                }
            case .refused(let reason):
                Label("Declined: \(reason)", systemImage: "hand.raised")
            case .unreadable:
                Label("This answer could not be read", systemImage: "questionmark.circle")
            }
            ForEach(answer.citations, id: \.self) { citation in
                if let url = URL(string: citation), url.scheme?.hasPrefix("http") == true {
                    Link(citation, destination: url).font(.footnote)
                } else {
                    Text(citation).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }
}
