//
//  Cache.swift
//  ImageKit
//

import Foundation

@MainActor
public protocol ImageCache {
    func isValid(request: ImageRequest) -> Bool
    func image(for request: ImageRequest) throws -> KKImage?
    func cache(_ image: KKImage, for request: ImageRequest)
    func clear() async
}
