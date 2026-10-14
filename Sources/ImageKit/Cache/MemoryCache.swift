import Foundation

public class MemoryCache {
    public static let shared = MemoryCache()

    private final class Key: NSObject {
        let output: ImageRequest.OutputKey

        init(_ output: ImageRequest.OutputKey) {
            self.output = output
        }

        override var hash: Int { output.hashValue }

        override func isEqual(_ object: Any?) -> Bool {
            guard let other = object as? Key else { return false }
            return output == other.output
        }
    }

    private let cache = NSCache<Key, KKImage>()

    public func isValid(request: ImageRequest) -> Bool {
        request.caches.contains(.memory)
    }
}

extension MemoryCache: ImageCache {
    @MainActor public func image(for request: ImageRequest) throws -> KKImage? {
        cache.object(forKey: Key(request.outputKey))
    }

    @MainActor public func cache(_ image: KKImage, for request: ImageRequest) {
        cache.setObject(image, forKey: Key(request.outputKey))
    }

    @MainActor public func clear() async {
        cache.removeAllObjects()
    }
}
