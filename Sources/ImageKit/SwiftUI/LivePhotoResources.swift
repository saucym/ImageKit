import Foundation
import Photos
import ObjectiveC

final class LivePhotoResources {
    let urls: [URL]
    private let directory: URL
    private static var associationKey: UInt8 = 0

    static func prepare(image: ImageRequest, video: ImageRequest) async throws -> LivePhotoResources {
        try Task.checkCancellation()
        let data = try await withThrowingTaskGroup(of: (Int, Data).self) { group in
            group.addTask { (0, try await originalData(for: image)) }
            group.addTask { (1, try await originalData(for: video)) }
            var values = [(Int, Data)]()
            for try await value in group {
                values.append(value)
            }
            return values.sorted { $0.0 < $1.0 }.map(\.1)
        }
        try Task.checkCancellation()
        return try LivePhotoResources(image: image, imageData: data[0], video: video, videoData: data[1])
    }

    static func cached(image: ImageRequest, video: ImageRequest) throws -> LivePhotoResources? {
        guard let imageData = try cachedData(for: image),
              let videoData = try cachedData(for: video) else { return nil }
        return try LivePhotoResources(image: image, imageData: imageData, video: video, videoData: videoData)
    }

    @MainActor func retain(for livePhoto: PHLivePhoto) {
        // Keep source files valid for playback, independently of cache eviction and loader cancellation.
        objc_setAssociatedObject(livePhoto, &Self.associationKey, self, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    private init(image: ImageRequest, imageData: Data, video: ImageRequest, videoData: Data) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("ImageKit-LivePhoto-\(UUID().uuidString)", isDirectory: true)
        urls = [
            directory.appendingPathComponent("image").appendingPathExtension(image.url.pathExtension.isEmpty ? "jpg" : image.url.pathExtension),
            directory.appendingPathComponent("video").appendingPathExtension(video.url.pathExtension.isEmpty ? "mov" : video.url.pathExtension)
        ]
        do {
            try Task.checkCancellation()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try imageData.write(to: urls[0], options: .atomic)
            try Task.checkCancellation()
            try videoData.write(to: urls[1], options: .atomic)
            try Task.checkCancellation()
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    private static func originalData(for request: ImageRequest) async throws -> Data {
        let result = try await request.load()
        try Task.checkCancellation()
        guard case .data(let data) = result else {
            throw LivePhotoResourceError.originalDataRequired(request.url)
        }
        return data
    }

    private static func cachedData(for request: ImageRequest) throws -> Data? {
        if request.url.isFileURL {
            return try Data(contentsOf: request.url)
        }
        guard request.context.disk.isEnabled(for: request),
              case .data(let data) = request.context.disk.load(request) else { return nil }
        return data
    }
}

enum LivePhotoResourceError: LocalizedError {
    case originalDataRequired(URL)
    case assetUnavailable
    case photoUnavailable

    var errorDescription: String? {
        switch self {
        case .originalDataRequired(let url):
            return "Live Photo requires original resource data for \(url.lastPathComponent)."
        case .assetUnavailable:
            return "The requested Live Photo asset is unavailable."
        case .photoUnavailable:
            return "Photos could not create a Live Photo from these resources."
        }
    }
}
