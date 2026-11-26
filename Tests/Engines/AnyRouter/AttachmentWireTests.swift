import Foundation
import Testing
@testable import AnyRouter

struct AttachmentWireTests {
    private func photo(_ temp: TempAttachments, bytes: String = "JPEGDATA") throws -> Attachment {
        let id = UUID()
        let path = try temp.store.write(Data(bytes.utf8), id: id, fileExtension: "jpg")
        return Attachment(id: id, kind: .image, filename: "cat.jpg", utType: "public.jpeg", byteCount: 8,
                          relativePath: path, extractedText: "WORDS", isOCR: true)
    }

    @Test func aVisionModelGetsTextAndAPhotoAsContentParts() throws {
        let temp = TempAttachments()
        defer { temp.cleanup() }
        let image = try photo(temp)
        let file = sampleAttachment(.text, name: "n.txt", text: "file body")
        let wire = AnyRouterEngine.wireMessage(
            ChatMessage(role: .user, content: "What is this?", attachments: [image, file]), sendsImages: true, store: temp.store)
        let parts = try #require(wire["content"] as? [[String: Any]])
        #expect(parts.count == 2)
        #expect(parts[0]["type"] as? String == "text")
        let text = try #require(parts[0]["text"] as? String)
        #expect(text.contains("What is this?") && text.contains("file body") && !text.contains("WORDS"))
        #expect(parts[1]["type"] as? String == "image_url")
        let url = try #require((parts[1]["image_url"] as? [String: Any])?["url"] as? String)
        #expect(url == "data:image/jpeg;base64,\(Data("JPEGDATA".utf8).base64EncodedString())")
    }

    @Test func aPhotoOnlyMessageHasNoEmptyTextPart() throws {
        let temp = TempAttachments()
        defer { temp.cleanup() }
        let wire = AnyRouterEngine.wireMessage(
            ChatMessage(role: .user, content: "", attachments: [try photo(temp)]), sendsImages: true, store: temp.store)
        let parts = try #require(wire["content"] as? [[String: Any]])
        #expect(parts.map { $0["type"] as? String } == ["image_url"])
    }

    @Test func aMissingPhotoFileIsReportedInsteadOfDropped() throws {
        let temp = TempAttachments()
        defer { temp.cleanup() }
        let image = try photo(temp)
        temp.store.remove(image)
        let wire = AnyRouterEngine.wireMessage(ChatMessage(role: .user, content: "Hi", attachments: [image]), sendsImages: true, store: temp.store)
        let parts = try #require(wire["content"] as? [[String: Any]])
        #expect((parts.last?["text"] as? String)?.contains("The file is missing") == true)
    }

    @Test func aTextOnlyModelGetsOneStringWithTheTextFoundInThePhoto() throws {
        let temp = TempAttachments()
        defer { temp.cleanup() }
        let wire = AnyRouterEngine.wireMessage(
            ChatMessage(role: .user, content: "Read it", attachments: [try photo(temp)]), sendsImages: false, store: temp.store)
        let content = try #require(wire["content"] as? String)
        #expect(content.contains("Read it") && content.contains("WORDS") && content.contains("text read from the image"))
        #expect(wire["role"] as? String == "user")
    }

    @Test func assistantAndPlainMessagesStayStrings() {
        let reply = AnyRouterEngine.wireMessage(ChatMessage(role: .assistant, content: "Sure"), sendsImages: true, store: .shared)
        #expect(reply["content"] as? String == "Sure" && reply["role"] as? String == "assistant")
    }

    @Test func theChatRequestSendsPhotosToVisionModelsOnly() throws {
        let temp = TempAttachments()
        defer { temp.cleanup() }
        let engine = AnyRouterEngine(tokens: FakeTokens("sk-ar-1"), attachments: temp.store)
        let message = ChatMessage(role: .user, content: "Hi", attachments: [try photo(temp)])
        func content(_ capabilities: Set<String>) throws -> Any? {
            let model = ModelDescriptor(id: "anyrouter/x/y", source: .anyrouter, displayName: "y", contextLength: nil,
                                        capabilities: capabilities, sizeBytes: nil, isInstalled: true)
            let request = try engine.makeChatRequest(key: "k", model: model, messages: [message], params: GenerationParams())
            let data = try #require(request.httpBody)
            let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let messages = try #require(body["messages"] as? [[String: Any]])
            return messages.last?["content"]
        }
        #expect(try content(["chat", "vision"]) is [Any])
        #expect(try content(["chat"]) is String)
    }

    @Test func aCatalogEntryThatTakesImagesIsTaggedVision() throws {
        let json = #"{"data":[{"id":"a/b","category":"multimodal","capabilities":["chat"],"architecture":{"input_modalities":["text","image"],"output_modalities":["text"]}},{"id":"a/c","category":"text","capabilities":["chat"],"architecture":{"input_modalities":["text"],"output_modalities":["text"]}}]}"#
        let models = try JSONDecoder().decode(ModelsResponse.self, from: Data(json.utf8)).descriptors(usable: true)
        #expect(models[0].capabilities.contains("vision") && models[0].supportsVision)
        #expect(!models[1].supportsVision)
    }
}

struct AttachmentOnDeviceTests {
    @Test func appleAndLocalModelsReadFilesAsTextInTheLastTurn() throws {
        let message = ChatMessage(role: .user, content: "Summarise", attachments: [sampleAttachment(text: "Pick up the keys.")])
        let built = try ApplePrompt.build(messages: [message], params: GenerationParams())
        #expect(built.prompt.contains("Summarise") && built.prompt.contains("[Attachment: notes.txt]") && built.prompt.contains("Pick up the keys."))
        let local = PromptBuilder.promptMessages(from: [message], systemPrompt: nil)
        #expect(local.first?.content == AttachmentPrompt.text(for: message, sendsImages: false))
    }

    @Test func aPhotoReachesAnOnDeviceModelAsTheTextFoundInIt() throws {
        let photo = sampleAttachment(.image, name: "sign.jpg", text: "OPEN 9 TO 5", ocr: true)
        let built = try ApplePrompt.build(messages: [ChatMessage(role: .user, content: "", attachments: [photo])], params: GenerationParams())
        #expect(built.prompt.contains("OPEN 9 TO 5"))
    }
}
