//
//  DataLoader.swift
//  ImageKit
//

import Foundation

public enum LoadResult {
    case image(KKImage)
    case data(Data)
}

struct LoadedResource {
    let result: LoadResult
    let invalidateCachedData: (() -> Void)?
    let reload: (() async throws -> LoadedResource)?

    init(result: LoadResult,
         invalidateCachedData: (() -> Void)? = nil,
         reload: (() async throws -> LoadedResource)? = nil) {
        self.result = result
        self.invalidateCachedData = invalidateCachedData
        self.reload = reload
    }
}

protocol ResourceLoader: DataLoader {
    func loadResource(request: ImageRequest) async throws -> LoadedResource?
}

public protocol DataLoader {
    func isValid(request: ImageRequest) -> Bool
    func load(request: ImageRequest) async throws -> LoadResult?
    /// Compatibility hook for loaders that report errors separately from `load(request:)`.
    func loadResult(request: ImageRequest) async throws -> LoadResult?
}

public extension DataLoader {
    func loadResult(request: ImageRequest) async throws -> LoadResult? {
        try Task.checkCancellation()
        let result = try await load(request: request)
        try Task.checkCancellation()
        return result
    }
}
