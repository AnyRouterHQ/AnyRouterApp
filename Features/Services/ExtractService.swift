import Foundation

/// What the Extract screen and an agent tool both call: a document text, the fields to read and a model id in, typed
/// fields with their source offsets out. Value types only; no view, no view model.
@MainActor
struct ExtractService {
    /// One prompt in, the model's reply out, for the model with the given id (nil: the default).
    var ask: @MainActor (String, String?) async throws -> String
    /// How much of the document the model gets, by model id.
    var characterLimit: @MainActor (String?) -> Int

    func extract(text: String, fields: [FieldSpec], modelID: String? = nil) async throws -> [ExtractedField] {
        guard ExtractLogic.canExtract(text: text, fields: fields) else { throw ExtractError.noText }
        let sent = ExtractLogic.clipped(text, limit: characterLimit(modelID)).text
        let reply = try await ask(ExtractLogic.prompt(fields: fields, text: sent), modelID)
        return try ExtractLogic.parse(reply, fields: fields, in: text)
    }

    /// Any chat model the app has, through the same one-prompt path the Shortcuts actions use.
    static func make(chat: HeadlessChat) -> ExtractService {
        ExtractService(
            ask: { try await chat.ask($0, modelID: $1) },
            characterLimit: { id in
                let model = id.flatMap { id in chat.models.models.first { $0.id == id } } ?? chat.models.selected
                return ExtractLogic.characterLimit(for: model?.source ?? .apple)
            })
    }
}
