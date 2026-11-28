import SwiftData
import SwiftUI

/// A skill the model proposed (agent design 4.2, unit K2): one trace row. While it waits, the row is open and shows the
/// whole text with Save and Discard, because a saved skill is guidance later runs read. Nothing is saved without Save.
struct SkillProposalRow: View {
    let proposal: SkillProposal
    let message: MessageRecord
    @Environment(\.modelContext) private var context
    @State private var isExpanded = false
    @State private var failure: String?

    private var isPending: Bool { proposal.state == .pending }
    private var isOpen: Bool { isExpanded || isPending }
    private var status: TraceStatus? { proposal.state == .saved ? .done : nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.snappy) { isExpanded.toggle() }
            } label: {
                TraceRow(symbol: "list.bullet.clipboard", status: status, isExpanded: isOpen) {
                    Text(SkillProposalLogic.title(of: proposal))
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("skill.proposal")
            if isOpen {
                VStack(alignment: .leading, spacing: 8) {
                    Text(proposal.draft.description).font(.footnote)
                    Text(proposal.draft.body).font(.footnote).foregroundStyle(.secondary).textSelection(.enabled)
                    if let failure {
                        Text(failure).font(.footnote).foregroundStyle(.red)
                    }
                    if isPending {
                        HStack(spacing: 12) {
                            Button { perform { try store.save(proposal.id) } } label: { Text("Save").prominentLabel() }
                                .buttonStyle(.borderedProminent)
                                .accessibilityIdentifier("skill.proposal.save")
                            Button("Discard", role: .destructive) { perform { try store.discard(proposal.id) } }
                                .buttonStyle(.bordered)
                                .accessibilityIdentifier("skill.proposal.discard")
                        }
                        .controlSize(.large)
                    }
                }
                .padding(.leading, TraceRowMetrics.contentInset)
                .padding(.bottom, 8)
            }
        }
    }

    private var store: SkillProposalStore { SkillProposalStore(context: context, reply: message) }

    private func perform(_ work: () throws -> Void) {
        do {
            try work()
            failure = nil
        } catch {
            failure = error.localizedDescription
        }
    }
}
