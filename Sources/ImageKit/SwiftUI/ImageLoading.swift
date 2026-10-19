import SwiftUI
import Photos

public enum ImagePhase: Sendable {
    case empty
    case success(KKImage)
    case failure(any Error)
}

public final class ImageResult: ObservableObject {
    @Published public var value: ImagePhase = .empty
    @Published public var livePhoto: PHLivePhoto?
    @Published public internal(set) var livePhotoLoading = false
    @Published public internal(set) var livePhotoError: (any Error)?

    public init() { }
}

public protocol ImageLoading {
    var request: ImageRequest { get }
    var result: ImageResult { get }
    func loadImage() async
    func cancel()
}

public extension ImageLoading {
    func cancel() { }
}

struct ImageLoadingID: Hashable {
    private let output: ImageRequest.OutputKey
    private let url: URL
    private let caches: Int
    private let placeholderHeight: CGFloat?
    private let result: ObjectIdentifier?

    init(request: ImageRequest, result: ImageResult? = nil) {
        output = request.outputKey
        url = request.url
        caches = request.caches.rawValue
        placeholderHeight = request.size.defaultHeight
        self.result = result.map(ObjectIdentifier.init)
    }
}
