import UIKit

/// Site icons for the reply footer and the sources list, kept in memory for the session. AsyncImage keeps nothing
/// between appearances, so a row that scrolled back into view fetched its icons again and flashed the letter first.
/// A site without an icon is remembered too, so it is asked once.
@MainActor
final class FaviconCache {
    static let shared = FaviconCache()

    private let images = NSCache<NSURL, UIImage>()
    private var missing: Set<URL> = []
    private var loads: [URL: Task<UIImage?, Never>] = [:]

    func cached(_ url: URL) -> UIImage? { images.object(forKey: url as NSURL) }

    func image(for url: URL) async -> UIImage? {
        if let image = cached(url) { return image }
        if missing.contains(url) { return nil }
        if let load = loads[url] { return await load.value }
        let load = Task<UIImage?, Never> {
            guard let (data, response) = try? await URLSession.shared.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return UIImage(data: data)
        }
        loads[url] = load
        let image = await load.value
        loads[url] = nil
        if let image { images.setObject(image, forKey: url as NSURL) } else { missing.insert(url) }
        return image
    }
}
