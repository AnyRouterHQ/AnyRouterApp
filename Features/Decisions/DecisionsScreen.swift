import SwiftData
import SwiftUI

/// Sheet wrapper: the Decisions form in its own navigation stack with a Close button.
struct DecisionsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            DecisionsScreen()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(role: .close) { dismiss() } }
                }
        }
    }
}

/// Typed questions about a text, answered by a decision model (`POST /api/v1/decisions`). Not a chat.
struct DecisionsScreen: View {
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Query(sort: \DecisionRunRecord.createdAt, order: .reverse) private var recent: [DecisionRunRecord]
    /// The one focus owner for every text input here, so Run can dismiss the keyboard.
    @FocusState private var focus: DecisionField?

    var body: some View {
        @Bindable var store = app.decisions
        Form {
            Section("Model") {
                if store.models.isEmpty {
                    Text(store.modelsError ?? "Loading decision models")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Model", selection: $store.modelID) {
                        ForEach(store.models) {
                            ModelLabel(name: $0.name, brand: .asset(ModelBrand.anyRouterMark), style: .row).tag($0.id)
                        }
                    }
                    .accessibilityIdentifier("decisions-model")
                }
            }
            Section {
                TextEditor(text: $store.state)
                    .focused($focus, equals: .state)
                    .frame(minHeight: 120)
                    .accessibilityIdentifier("decisions-state")
            } header: {
                Text("State")
            } footer: {
                Text("The text to judge. \(store.state.count) of \(DecisionsLogic.maxStateCharacters) characters.")
            }
            Section("Questions") {
                ForEach($store.questions) { $question in QuestionRow(question: $question, focus: $focus) }
                    .onDelete { store.deleteQuestions(at: $0) }
                    .onMove { store.moveQuestions(from: $0, to: $1) }
                Button { store.addQuestion() } label: { Label("Add question", systemImage: "plus") }
                    .accessibilityIdentifier("decisions-add-question")
            }
            ResultSections(phase: store.phase)
            if !recent.isEmpty {
                Section("Recent runs") {
                    ForEach(recent.prefix(DecisionsLogic.recentLimit)) { record in
                        Button { store.restore(record) } label: {
                            VStack(alignment: .leading) {
                                Text(DecisionsLogic.title(forState: record.state)).lineLimit(1)
                                Text(record.createdAt, style: .relative)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Decisions")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { EditButton() }
            ToolbarItem(placement: .primaryAction) {
                Button("Run") {
                    focus = nil
                    Task { await store.run() }
                }
                    .disabled(!store.canRun)
                    .accessibilityIdentifier("decisions-run")
            }
        }
        .task {
            store.attach(context)
            await store.loadModels()
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

private struct ResultSections: View {
    let phase: DecisionsStore.Phase

    var body: some View {
        switch phase {
        case .idle:
            EmptyView()
        case .running:
            Section { ProgressView("Running") }
        case .failed(let message):
            Section { Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
        case .finished(let result):
            Section("Result") {
                if let refusal = result.refusal {
                    Label("Declined: \(refusal)", systemImage: "hand.raised")
                }
                ForEach(result.answers) { AnswerRow(answer: $0) }
            }
            Section("Run details") {
                LabeledContent("Model", value: result.model)
                LabeledContent("Cost", value: DecisionsLogic.costText(result.cost))
                LabeledContent("Latency", value: DecisionsLogic.latencyText(result.latency))
                LabeledContent("Tokens", value: "\(result.inputTokens) in, \(result.outputTokens) out")
            }
        }
    }
}

private struct AnswerRow: View {
    let answer: DecisionAnswer

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(answer.prompt).font(.subheadline).foregroundStyle(.secondary)
            switch answer.outcome {
            case .answered(let verdict):
                Text(verdict.headline).font(.headline)
                if let probability = verdict.probability {
                    ProgressView(value: probability) { EmptyView() } currentValueLabel: {
                        Text(DecisionsLogic.percent(probability))
                    }
                }
                if let score = verdict.score, let maxScore = verdict.maxScore {
                    Gauge(value: min(score, maxScore), in: 0...maxScore) { EmptyView() } currentValueLabel: {
                        Text("\(verdict.headline) of \(Int(maxScore))")
                    }
                }
                if let note = verdict.note { Text(note).font(.footnote).foregroundStyle(.secondary) }
                if let confidence = verdict.confidence {
                    Text("Confidence \(DecisionsLogic.percent(confidence))").font(.footnote).foregroundStyle(.secondary)
                }
                if verdict.options.count > 1 {
                    DisclosureGroup("All options") {
                        ForEach(verdict.options, id: \.label) {
                            LabeledContent($0.label, value: DecisionsLogic.percent($0.probability))
                        }
                    }
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
