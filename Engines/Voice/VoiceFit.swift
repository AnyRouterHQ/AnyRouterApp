import Foundation

/// Whether a voice model fits this device, from the same memory budget as chat models (`DeviceClass`, `DeviceMemory`).
/// A voice model shares RAM with the chat model, so "runs well" asks for half the budget at most.
enum VoiceFit {
    enum Verdict: Equatable, Sendable {
        case system
        case runsWell
        case tight
        case wontFit

        var title: String {
            switch self {
            case .system: "Built in"
            case .runsWell: "Runs well"
            case .tight: "Tight on this device"
            case .wontFit: "Will not fit"
            }
        }
    }

    /// Core ML models are compiled and mapped into memory, and the encoder and decoder run side by side.
    /// 2.2 is an estimate, to be replaced by the device measurement in PLAN.md (Voice roadmap, on-device eval list).
    static let residentMultiplier = 2.2
    static let runsWellShare = 0.5
    static let tightShare = 0.75

    static func residentBytes(_ model: VoiceModel) -> Int64 {
        model.residentBytes ?? Int64(Double(model.sizeBytes) * residentMultiplier)
    }

    static func verdict(_ model: VoiceModel, memory: DeviceMemory) -> Verdict {
        if model.isSystem { return .system }
        let resident = Double(residentBytes(model))
        let budget = Double(memory.budgetBytes)
        if resident <= budget * runsWellShare { return .runsWell }
        return resident <= budget * tightShare ? .tight : .wontFit
    }

    /// The largest model of a kind that runs well, by catalog `order`. Nil when none does: the System engine stays the default.
    static func recommended(_ models: [VoiceModel], kind: VoiceModelKind, memory: DeviceMemory) -> VoiceModel? {
        models
            .filter { $0.kind == kind && !$0.isSystem && verdict($0, memory: memory) == .runsWell }
            .max { ($0.order ?? 0) < ($1.order ?? 0) }
    }
}
