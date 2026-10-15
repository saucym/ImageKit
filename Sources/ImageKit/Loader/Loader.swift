//
//  Loader.swift
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
    func load(request: ImageRequest) async -> LoadResult?
    /// Used by ImageRequest to preserve errors. Returning nil tries the next matching loader.
    func loadResult(request: ImageRequest) async throws -> LoadResult?
}

public extension DataLoader {
    func loadResult(request: ImageRequest) async throws -> LoadResult? {
        try Task.checkCancellation()
        let result = await load(request: request)
        try Task.checkCancellation()
        return result
    }
}
