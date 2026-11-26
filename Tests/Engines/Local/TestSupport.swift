import Foundation
@testable import AnyRouter

struct FakeHTTP: HTTPFetching {
    let handler: @Sendable (URLRequest) throws -> (Data, Int)

    init(status: Int = 200, body: String = "") {
        handler = { _ in (Data(body.utf8), status) }
    }

    init(handler: @escaping @Sendable (URLRequest) throws -> (Data, Int)) {
        self.handler = handler
    }

    func fetch(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, status) = try handler(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (data, response)
    }
}

func makeTempDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "anyrouter-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func sampleGGUF(repo: String = "org/model-GGUF", file: String = "model-Q4_K_M.gguf", order: Int? = nil, title: String = "Model") -> CatalogEntry {
    CatalogEntry(repo: repo, format: .gguf, file: file, title: title, sizeBytes: 1_000, order: order)
}

func sampleMLX(repo: String = "org/model-4bit", order: Int? = nil, title: String = "Model MLX") -> CatalogEntry {
    CatalogEntry(repo: repo, format: .mlx, title: title, sizeBytes: 2_000, order: order)
}
