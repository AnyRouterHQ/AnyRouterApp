import Foundation
import SwiftData
import Testing
@testable import AnyRouter

func sampleAttachment(
    _ kind: ChatAttachment.Kind = .text, name: String = "notes.txt", text: String? = "hello",
    ocr: Bool = false, truncated: Bool = false, utType: String = "public.plain-text", path: String = "t/a.txt"
) -> ChatAttachment {
    ChatAttachment(id: UUID(), kind: kind, filename: name, utType: utType, byteCount: 5, relativePath: path,
               extractedText: text, isOCR: ocr, isTruncated: truncated)
}

struct AttachmentPromptTests {
    private func message(_ content: String, _ attachments: [ChatAttachment]) -> ChatMessage {
        ChatMessage(role: .user, content: content, attachments: attachments)
    }

    @Test func aMessageWithoutFilesIsUnchanged() {
        #expect(AttachmentPrompt.text(for: message("Hi", []), sendsImages: false) == "Hi")
        #expect(ChatMessage(role: .user, content: "x").attachments.isEmpty)
    }

    @Test func extractedTextFollowsTheMessageInsideMarkers() {
        let text = AttachmentPrompt.text(for: message("Summarise", [sampleAttachment(text: "Pick up the keys.")]), sendsImages: false)
        #expect(text == "Summarise\n\n[Attachment: notes.txt]\nPick up the keys.\n[End of attachment]")
    }

    @Test func aFileOnlyMessageStartsWithTheAttachment() {
        let text = AttachmentPrompt.text(for: message("", [sampleAttachment(text: "body")]), sendsImages: false)
        #expect(text.hasPrefix("[Attachment: notes.txt]"))
    }

    @Test func textReadFromAnImageSaysSoAndACutIsReported() {
        let ocr = sampleAttachment(.image, name: "scan.jpg", text: "Total 42", ocr: true, truncated: true)
        let text = AttachmentPrompt.text(for: message("", [ocr]), sendsImages: false)
        #expect(text.contains("[Attachment: scan.jpg (text read from the image)]"))
        #expect(text.contains("[Text cut at 100000 characters]"))
    }

    @Test func aModelThatSendsImagesGetsNoTextForThemButStillGetsFiles() {
        let image = sampleAttachment(.image, name: "a.jpg", text: "ocr", ocr: true)
        let pdf = sampleAttachment(.pdf, name: "a.pdf", text: "pdf text")
        let text = AttachmentPrompt.text(for: message("Look", [image, pdf]), sendsImages: true)
        #expect(!text.contains("a.jpg"))
        #expect(text.contains("pdf text"))
        #expect(AttachmentPrompt.text(for: message("Look", [image]), sendsImages: true) == "Look")
    }

    @Test func aFileWithNoTextSaysWhatIsMissing() {
        func text(_ kind: ChatAttachment.Kind, _ value: String?) -> String {
            AttachmentPrompt.text(for: message("", [sampleAttachment(kind, name: "f", text: value)]), sendsImages: false)
        }
        #expect(text(.image, nil) == "[Image: f. This model cannot see images and no text was found in it.]")
        #expect(text(.pdf, "") == "[PDF: f. No text could be read from it.]")
        #expect(text(.text, nil) == "[File: f. It is empty.]")
        #expect(text(.audio, nil) == "[Audio: f. Audio is not transcribed.]")
    }

    @Test func pathsResolveUnderTheRootAndTypesGiveAMimeType() {
        let root = URL(filePath: "/tmp/root", directoryHint: .isDirectory)
        #expect(sampleAttachment(path: "t/a.txt").url(in: root).path == "/tmp/root/t/a.txt")
        #expect(sampleAttachment(utType: "public.jpeg").mimeType == "image/jpeg")
        #expect(sampleAttachment(utType: "not.a.type").mimeType == "application/octet-stream")
    }
}

@MainActor
struct MessageRecordAttachmentTests {
    @Test func attachmentsRoundTripThroughTheRecordAndIntoTheChatMessage() {
        let record = MessageRecord(role: .user, content: "hi")
        #expect(record.attachments.isEmpty && record.attachmentsData == nil)
        let attachment = sampleAttachment()
        record.attachments = [attachment]
        #expect(record.attachments == [attachment])
        #expect(record.chatMessage.attachments == [attachment])
        record.attachments = []
        #expect(record.attachmentsData == nil)
    }

    @Test func unreadableAttachmentDataReadsAsNoAttachments() {
        let record = MessageRecord(role: .user, content: "hi")
        record.attachmentsData = Data("garbage".utf8)
        #expect(record.attachments.isEmpty)
    }

    @Test func copyingAMessageKeepsItsAttachments() {
        let message = ChatMessage(role: .user, content: "x", attachments: [sampleAttachment()])
        #expect(MessageRecord(message).attachments == message.attachments)
    }
}
