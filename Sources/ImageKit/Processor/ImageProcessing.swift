import CoreGraphics
import Foundation

struct ImageResizePlan {
    let thumbnailMaxPixelSize: Int
    let width: Int
    let height: Int

    var size: CGSize { CGSize(width: width, height: height) }

    init?(request: ImageRequest, sourceSize: CGSize) {
        guard sourceSize.width.isFinite, sourceSize.height.isFinite,
              sourceSize.width > 0, sourceSize.height > 0 else { return nil }

        let scale: CGFloat
        let outputSize: CGSize
        switch request.size {
        case .original:
            return nil
        case .width(let width, _):
            guard width.isFinite, width > 0 else { return nil }
            scale = min(width / sourceSize.width * screenScale, 1)
            outputSize = sourceSize * scale
        case .absolute(let target):
            guard target.width.isFinite, target.height.isFinite,
                  target.width > 0, target.height > 0 else { return nil }
            let widthScale = target.width / sourceSize.width * screenScale
            let heightScale = target.height / sourceSize.height * screenScale
            switch request.mode {
            case .fit:
                scale = min(widthScale, heightScale, 1)
                outputSize = sourceSize * scale
            case .fill:
                // ImageIO limits the longest side; retain the larger axis scale until the processor crops.
                scale = min(max(widthScale, heightScale), 1)
                // Divide before multiplying so very large finite targets still produce a bounded crop.
                let outputScale = min(screenScale, sourceSize.width / target.width, sourceSize.height / target.height)
                outputSize = target * outputScale
            }
        }

        guard let maxPixelSize = Int(exactly: ceil(max(sourceSize.width, sourceSize.height) * scale)),
              let width = Int(exactly: floor(outputSize.width)),
              let height = Int(exactly: floor(outputSize.height)),
              width <= (Int.max - 63) / 4 else { return nil }
        thumbnailMaxPixelSize = max(1, maxPixelSize)
        self.width = max(1, width)
        self.height = max(1, height)
    }
}

extension CGImage {
    var hasAlpha: Bool {
        switch alphaInfo {
        case .first, .last, .premultipliedFirst, .premultipliedLast, .alphaOnly: true
        default: false
        }
    }
}

extension KKImage {
    func processingFrames(animation: ImageRequest.AnimationPolicy, transform: (KKImage) -> KKImage) -> KKImage {
        #if os(iOS)
        if let frames = images, let first = frames.first {
            if animation == .firstFrame {
                return transform(first)
            }
            var processedFrames: [ObjectIdentifier: KKImage] = [:]
            processedFrames.reserveCapacity(frames.count)
            let output = frames.map { frame in
                let identity = ObjectIdentifier(frame)
                if let processed = processedFrames[identity] {
                    return processed
                }
                let processed = transform(frame)
                processedFrames[identity] = processed
                return processed
            }
            if zip(frames, output).allSatisfy({ $0 === $1 }) {
                return self
            }
            return KKImage.animatedImage(with: output, duration: duration) ?? self
        }
        #endif
        return transform(self)
    }
}
