import Foundation

/// Row text and search for the model lists. Pure, so it is tested without UI.
/// Sorting and filtering of families live in `FamilyLogic`.
enum HubListOptions {
    /// A family matches a search by name, publisher, summary or tag.
    static func matches(_ family: LocalModelFamily, _ needle: String) -> Bool {
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        return family.name.range(of: needle, options: options) != nil
            || family.publisher.range(of: needle, options: options) != nil
            || family.summary.range(of: needle, options: options) != nil
            || family.tags.contains { $0.range(of: needle, options: options) != nil }
    }

    static func engineName(_ source: ModelSource) -> String {
        switch source {
        case .gguf: "GGUF"
        case .mlx: "MLX"
        case .apple: "Apple"
        case .anyrouter: "AnyRouter"
        }
    }

    /// "GGUF · 4B · Q4_K_M · 2.5 GB · Uses ~3.1 GB": format, parameters, quantization, file size, memory.
    static func detailLine(_ entry: LocalModelEntry) -> String {
        var parts = [engineName(entry.descriptor.source)]
        parts += [entry.parameters, entry.quantization].compactMap { $0 }
        if let size = HubLogic.sizeText(entry.descriptor.sizeBytes) { parts.append(size) }
        if let detail = entry.fitDetail { parts.append("Uses ~\(FitFormat.gigabytes(detail.neededBytes))") }
        return parts.joined(separator: " · ")
    }

    /// Short fit status for a row, or nil when nothing is known. `device` is "iPhone" or "iPad".
    static func fitStatus(_ entry: LocalModelEntry, device: String) -> String? {
        if let reason = entry.unavailableReason { return reason }
        if let detail = entry.fitDetail, let badge = FitText.badge(detail, device: device) { return badge }
        switch entry.fit {
        case .fits: return "Runs well"
        case .tight: return "May be slow"
        case .wontFit: return "Too big for this \(device)"
        case .unknown: return nil
        }
    }

    /// The fit line of a list row: nothing when the model runs well, so only a warning stands out. The model's own page
    /// still says "Runs well" (`fitStatus`).
    static func rowStatus(_ entry: LocalModelEntry, device: String) -> String? {
        let runsWell = entry.unavailableReason == nil && (entry.fitDetail?.verdict ?? entry.fit) == .fits
        return runsWell ? nil : fitStatus(entry, device: device)
    }

    static func storageSummary(usedBytes: Int64, freeBytes: Int64?) -> String {
        var text = "Models use \(FitFormat.gigabytes(usedBytes))"
        if let freeBytes { text += " · \(FitFormat.gigabytes(freeBytes)) free" }
        return text
    }
}
