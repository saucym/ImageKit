import Foundation

extension ImageRequest {
    struct OutputKey: Hashable, Sendable {
        let resource: String
        let assetIdentifier: String?
        let width: CGFloat?
        let height: CGFloat?
        let isOriginal: Bool
        let isFill: Bool
        let animation: AnimationPolicy
        let processors: Int
        let scale: CGFloat
        let context: UUID
    }

    var outputKey: OutputKey { outputKey(width: size.width) }

    private func outputKey(width: CGFloat?) -> OutputKey {
        OutputKey(resource: key,
                  assetIdentifier: asset?.localIdentifier,
                  width: width,
                  height: size.height,
                  isOriginal: size.width == nil,
                  isFill: mode == .fill,
                  animation: animation,
                  processors: processors.rawValue,
                  scale: screenScale,
                  context: context.cacheIdentity)
    }

    func cacheKey(width: CGFloat? = nil) -> Int {
        outputKey(width: width ?? size.width).hashValue
    }
}
