import Foundation
import ImageIO
import Testing
import UIKit
import UniformTypeIdentifiers
@testable import AnyRouter

struct DecisionImageTests {
    private func photo(_ bytes: Int = 3, type: String = "image/jpeg") -> DecisionImage {
        DecisionImage(mediaType: type, data: Data(count: bytes))
    }

    private func draft() -> QuestionDraft { QuestionDraft(kind: .yesNo, prompt: "Is it real?") }

    @Test func aPhotoShrinksDownTheLadderUntilItFits() {
        let seen = LockedBox<[Int]>([])
        let result = DecisionsLogic.fit(Data([9]), budget: 100, sides: [2000, 1000, 500]) { _, side in
            seen.value.append(side)
            return Data(count: side == 500 ? 80 : 400)
        }
        #expect(seen.value == [2000, 1000, 500])
        #expect(result == .success(DecisionImage(mediaType: "image/jpeg", data: Data(count: 80))))
    }

    @Test func aPhotoThatNeverFitsOrCannotBeReadIsReportedAsSuch() {
        #expect(DecisionsLogic.fit(Data(), budget: 10, sides: [9, 8]) { _, _ in Data(count: 50) } == .failure(.tooLarge))
        #expect(DecisionsLogic.fit(Data(), budget: 10, sides: [9, 8]) { _, _ in nil } == .failure(.unreadable))
        #expect(DecisionsLogic.imageBudget == 2 * 1024 * 1024)
    }

    @Test func slotsStopAtFourPhotos() {
        #expect(DecisionsLogic.slots(adding: 3, held: 0) == 3)
        #expect(DecisionsLogic.slots(adding: 3, held: 2) == 2)
        #expect(DecisionsLogic.slots(adding: 1, held: 4) == 0)
        #expect(DecisionsLogic.slots(adding: 1, held: 9) == 0)
    }

    @Test func theServersPhotoLimitsAreChecked() {
        #expect(DecisionsLogic.imageProblem([]) == nil)
        #expect(DecisionsLogic.imageProblem(Array(repeating: photo(), count: 4)) == nil)
        #expect(DecisionsLogic.imageProblem(Array(repeating: photo(), count: 5)) == "Add at most 4 photos.")
        #expect(DecisionsLogic.imageProblem([photo(type: "image/heic")]) == "Photos must be PNG, JPEG or WebP.")
        #expect(DecisionsLogic.imageProblem([photo(4 * 1024 * 1024)]) == nil)
        #expect(DecisionsLogic.imageProblem([photo(4 * 1024 * 1024 + 1)]) == "The photos are too large.")
        let three = Array(repeating: photo(3 * 1024 * 1024), count: 3)
        #expect(DecisionsLogic.imageProblem(three) == "The photos are too large.")
        #expect(DecisionsLogic.imageProblem(Array(three.prefix(2))) == nil)
    }

    @Test func aPhotoAloneIsEnoughToRunAndSendsAFixedText() throws {
        let images = [photo()]
        #expect(!DecisionsLogic.canRun(model: "m", state: " ", questions: [draft()]))
        #expect(DecisionsLogic.canRun(model: "m", state: " ", questions: [draft()], images: images))
        let request = try #require(DecisionsLogic.request(model: "m", state: "", questions: [draft()], images: images))
        #expect(request.state == DecisionsLogic.photoOnlyState && request.images == images)
        #expect(DecisionsLogic.wireState("  hi \n", images: images) == "hi")
    }

    @Test func eachBlockerReadsAsAShortReason() {
        func reason(model: String = "m", state: String = "t", images: [DecisionImage] = [], questions: String? = nil) -> String? {
            DecisionsLogic.blocker(model: model, state: state, images: images, questionProblem: questions)
        }
        #expect(reason() == nil)
        #expect(reason(model: "") == "Choose a model.")
        #expect(reason(state: "") == "Add something to judge.")
        #expect(reason(state: String(repeating: "x", count: 12_001)) == "The text is over 12000 characters.")
        #expect(reason(images: Array(repeating: photo(), count: 5)) == "Add at most 4 photos.")
        #expect(reason(questions: "Add a question.") == "Add a question.")
        #expect(DecisionsLogic.questionProblem([]) == "Add a question.")
        #expect(DecisionsLogic.questionProblem([draft(), QuestionDraft(kind: .choice, prompt: "Which?")]) == "Add at least two options.")
    }

    // MARK: On-device encoding

    /// A noisy JPEG (it does not compress) with a GPS dictionary, like a photo from the camera roll.
    private func locatedJPEG(side: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        for index in bytes.indices { bytes[index] = UInt8.random(in: 0...255) }
        let image = try #require(CGImage(
            width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: side * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: try #require(CGDataProvider(data: Data(bytes) as CFData)), decode: nil, shouldInterpolate: false,
            intent: .defaultIntent))
        let output = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil))
        let gps: [CFString: Any] = [kCGImagePropertyGPSLatitude: 1.5, kCGImagePropertyGPSLongitude: 2.5]
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyGPSDictionary: gps] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return output as Data
    }

    private func properties(_ data: Data) throws -> [CFString: Any] {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        return try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
    }

    @Test func theDeviceEncoderDropsLocationAndShrinksToTheBudget() throws {
        let source = try locatedJPEG(side: 900)
        #expect(try properties(source)[kCGImagePropertyGPSDictionary] != nil)

        let small = try #require(ImageProcessing.jpeg(from: source, maxSide: 300))
        let budget = small.count + 1
        let fitted = try DecisionsLogic.fit(source, budget: budget, sides: [900, 600, 300]) {
            ImageProcessing.jpeg(from: $0, maxSide: $1)
        }.get()
        #expect(fitted.data.count <= budget)
        #expect(ImageProcessing.pixelSize(of: fitted.data)?.width == 300)
        #expect(try properties(fitted.data)[kCGImagePropertyGPSDictionary] == nil)
    }
}
