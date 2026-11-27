import Foundation
import Testing
@testable import AnyRouter

@MainActor
struct ExtractServiceTests {
    private func service(limit: Int = 100, reply: String, seen: LockedBox<[String]>) -> ExtractService {
        ExtractService(
            ask: { prompt, id in
                seen.value += [prompt, id ?? "default"]
                return reply
            },
            characterLimit: { _ in limit })
    }

    @Test func textFieldsAndAModelInTypedFieldsWithSourcesOut() async throws {
        let seen = LockedBox<[String]>([])
        let reply = ##"[{"name":"Total","value":"5.00","quote":"Total 5.00"}]"##
        let fields = try await service(reply: reply, seen: seen)
            .extract(text: "Cafe\nTotal 5.00", fields: [FieldSpec("Total", .money)], modelID: "m1")
        #expect(fields == [ExtractedField(name: "Total", kind: .money, value: "5.00", quote: "Total 5.00", source: 5..<15)])
        #expect(seen.value.last == "m1")
        #expect(seen.value.first?.hasSuffix("Cafe\nTotal 5.00") == true)
    }

    @Test func theModelOnlyGetsWhatFitsAndAnEmptyTextIsRefused() async throws {
        let seen = LockedBox<[String]>([])
        _ = try await service(limit: 4, reply: "[]", seen: seen).extract(text: "abcdefgh", fields: [FieldSpec("A")])
        #expect(seen.value.first?.hasSuffix("Document:\nabcd") == true)
        #expect(seen.value.last == "default")
        await #expect(throws: ExtractError.noText) {
            try await service(reply: "[]", seen: seen).extract(text: " ", fields: [FieldSpec("A")])
        }
    }

    @Test func theHeadlessServiceSizesTheCutByTheModelAndAsksThroughTheChat() async throws {
        let registry = EngineRegistry()
        registry.register(ScriptedEngine(chunks: ["[]"]))
        let models = ModelStore(registry: registry, defaults: testDefaults())
        await models.refresh()
        models.select(try #require(models.models.first))
        let presets = PresetStore(
            fileURL: FileManager.default.temporaryDirectory.appending(path: "presets-\(UUID().uuidString).json"), builtIns: [])
        let service = ExtractService.make(chat: HeadlessChat(registry: registry, models: models, presets: presets))
        #expect(service.characterLimit(nil) == 6_000)
        #expect(service.characterLimit("apple/foundation") == 6_000)
        #expect(service.characterLimit("unknown") == 6_000)
        let fields = try await service.extract(text: "Total 5", fields: [FieldSpec("Total")])
        #expect(fields.map(\.value) == [""])
    }
}
