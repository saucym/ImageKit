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
}
