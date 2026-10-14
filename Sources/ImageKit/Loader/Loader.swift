//
//  Loader.swift
//  ImageKit
//

import Foundation

public enum LoadResult {
    case image(KKImage)
    case data(Data)
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
