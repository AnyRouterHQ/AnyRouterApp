import Testing
@testable import AnyRouter

struct ModelStatusColorTests {
    private func entry(fit: ModelFit, unavailable: String? = nil) -> LocalModelEntry {
        LocalModelEntry(descriptor: testModel(id: "m", source: .gguf), summary: "", tags: [], fit: fit, isUserAdded: false,
                        unavailableReason: unavailable, parameters: nil, quantization: nil)
    }

    /// Colour text fails 4.5:1, so only a real warning gets a coloured symbol; a model that runs well stays plain.
    @Test func onlyTightAndWontFitRaiseAnAlert() {
        #expect(ModelStatusColor.alert(entry(fit: .fits)) == nil)
        #expect(ModelStatusColor.alert(entry(fit: .unknown)) == nil)
        #expect(ModelStatusColor.alert(entry(fit: .tight)) == .orange)
        #expect(ModelStatusColor.alert(entry(fit: .wontFit)) == .red)
    }

    @Test func anUnavailableModelRaisesNoFitAlert() {
        #expect(ModelStatusColor.alert(entry(fit: .wontFit, unavailable: "Needs iOS 27")) == nil)
    }
}
