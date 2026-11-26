import Foundation
import llama

/// A prompt with photos, tokenized by `mtmd` and ready to be read by a llama.cpp context.
final class PreparedVision: @unchecked Sendable {
    /// Keeps the image reader alive while its chunks are.
    private let session: VisionSession
    private let chunks: OpaquePointer
    private let bitmaps: [OpaquePointer]
    /// Positions the prompt takes in the context: text tokens plus what the photos encode to.
    let positionCount: Int
    /// The largest context that leaves room for the image reader, nil when nothing limits it.
    let contextCap: Int?

    fileprivate init(session: VisionSession, chunks: OpaquePointer, bitmaps: [OpaquePointer], contextCap: Int?) {
        self.session = session
        self.chunks = chunks
        self.bitmaps = bitmaps
        self.contextCap = contextCap
        self.positionCount = Int(mtmd_helper_get_n_pos(chunks))
    }

    deinit {
        mtmd_input_chunks_free(chunks)
        for bitmap in bitmaps { mtmd_bitmap_free(bitmap) }
    }

    /// Encodes the photos and decodes the whole prompt. Only the last position produces logits.
    func evaluate(context llamaContext: OpaquePointer, batchSize: Int) throws {
        var newPast: llama_pos = 0
        let status = mtmd_helper_eval_chunks(session.context, llamaContext, chunks, 0, 0, Int32(batchSize), true, &newPast)
        guard status == 0 else { throw GGUFError.imageEncodeFailed(status) }
    }
}

/// llama.cpp's multimodal context for one model and one projector file. Loading it reads the projector (hundreds of MB).
final class VisionSession: @unchecked Sendable {
    fileprivate let context: OpaquePointer

    init(projectorPath: String, model: OpaquePointer) throws {
        var params = mtmd_context_params_default()
        #if targetEnvironment(simulator)
        params.use_gpu = false
        #endif
        params.print_timings = false
        params.warmup = false
        params.n_threads = Int32(max(1, min(6, ProcessInfo.processInfo.activeProcessorCount - 2)))
        guard let created = mtmd_init_from_file(projectorPath, model, params) else {
            throw GGUFError.projectorLoadFailed((projectorPath as NSString).lastPathComponent)
        }
        context = created
    }

    deinit {
        mtmd_free(context)
    }

    /// Reads the photos and tokenizes `text`, which holds one `marker` per photo.
    func prepare(text: String, addSpecial: Bool, images: [Data], contextCap: Int?) throws -> PreparedVision {
        var bitmaps: [OpaquePointer] = []
        func release() { for bitmap in bitmaps { mtmd_bitmap_free(bitmap) } }
        for data in images {
            let made = data.withUnsafeBytes { raw -> mtmd_helper_bitmap_wrapper in
                mtmd_helper_bitmap_init_from_buf(
                    context, raw.bindMemory(to: UInt8.self).baseAddress, data.count, false, mtmd_helper_init_opt_default())
            }
            guard let bitmap = made.bitmap else {
                release()
                throw GGUFError.imageUnreadable
            }
            bitmaps.append(bitmap)
        }
        guard let chunks = mtmd_input_chunks_init() else {
            release()
            throw GGUFError.imageEncodeFailed(-1)
        }
        let status: Int32 = text.withCString { cString in
            var input = mtmd_input_text(
                text: cString, text_len: Int(strlen(cString)), add_special: addSpecial, parse_special: true)
            let pointers: [OpaquePointer?] = bitmaps
            return pointers.withUnsafeBufferPointer { buffer in
                mtmd_tokenize(context, chunks, &input, buffer.baseAddress, buffer.count)
            }
        }
        guard status == 0 else {
            mtmd_input_chunks_free(chunks)
            release()
            throw GGUFError.imageEncodeFailed(status)
        }
        return PreparedVision(session: self, chunks: chunks, bitmaps: bitmaps, contextCap: contextCap)
    }
}
