import CoreGraphics
import Foundation

public class MemoryCache {
    public static let shared = MemoryCache()

    public let totalCostLimit: Int
    public let countLimit: Int

    /// Limits use NSCache semantics: zero leaves that limit unrestricted.
    public init(totalCostLimit: Int = 64 * 1024 * 1024, countLimit: Int = 0) {
        self.totalCostLimit = max(totalCostLimit, 0)
        self.countLimit = max(countLimit, 0)
        cache.totalCostLimit = self.totalCostLimit
        cache.countLimit = self.countLimit
    }

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

    @MainActor static func cost(of image: KKImage) -> Int {
        #if os(iOS)
        if let frames = image.images {
            var seen = Set<ObjectIdentifier>()
            var cost = 0
            for frame in frames {
                guard let bitmap = frame.cgImage,
                      seen.insert(ObjectIdentifier(bitmap)).inserted else { continue }
                let (total, overflow) = cost.addingReportingOverflow(bitmapCost(bitmap))
                guard !overflow else { return Int.max }
                cost = total
            }
            return cost
        }
        #endif
        return image.cgImage.map(bitmapCost) ?? 0
    }

    private static func bitmapCost(_ bitmap: CGImage) -> Int {
        let (cost, overflow) = bitmap.bytesPerRow.multipliedReportingOverflow(by: bitmap.height)
        return overflow ? Int.max : cost
    }
}

extension MemoryCache: ImageCache {
    @MainActor public func image(for request: ImageRequest) throws -> KKImage? {
        cache.object(forKey: Key(request.outputKey))
    }

    @MainActor public func cache(_ image: KKImage, for request: ImageRequest) {
        cache.setObject(image, forKey: Key(request.outputKey), cost: Self.cost(of: image))
    }

    @MainActor public func clear() async {
        cache.removeAllObjects()
    }
}
