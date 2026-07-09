//
//  MemoryCache.swift
//  ImageKit
//
//  Created by saucymqin on 2018/7/10.
//

import Foundation
import SwiftUI

public class MemoryCache {
    public static let shared = MemoryCache()
    private var multiWidths = [Int: [Int]]() // key.hash : [size.width1, size.width2]
    private let cache = NSCache<NSNumber, KKImage>()
    
    public func isValid(request: ImageRequest) -> Bool {
        request.caches.contains(.memory)
    }
    
    private func keyNumber(for request: ImageRequest, width: Int) -> NSNumber {
        NSNumber(value: request.cacheKey(width: CGFloat(width)))
    }
    
    private func cachedImage(for request: ImageRequest) -> KKImage? {
        let hashKey = request.key.hash
        let width = Int(exactly: (request.size.width ?? 0) * screenScale) ?? 0
        let key = keyNumber(for: request, width: width)
        if let image = cache.object(forKey: key) {
            return image
        }
        // Prefer a larger cached size when exact width miss
        if let sizes = multiWidths[hashKey] {
            for biggerWidth in sizes where biggerWidth > width {
                let biggerKey = keyNumber(for: request, width: biggerWidth)
                if let image = cache.object(forKey: biggerKey) {
                    return image
                }
            }
        }
        return nil
    }
}

extension MemoryCache: ImageCache {
    @MainActor public func image(for request: ImageRequest) throws -> KKImage? {
        cachedImage(for: request)
    }
    
    @MainActor public func cache(_ image: KKImage, for request: ImageRequest) {
        let hashKey = request.key.hash
        let width = Int(exactly: max(image.size.width, (request.size.width ?? 0) * screenScale)) ?? 0
        let key = keyNumber(for: request, width: width)
        cache.setObject(image, forKey: key)
        
        if var sizes = multiWidths[hashKey] {
            if !sizes.contains(width) {
                sizes.append(width)
                multiWidths[hashKey] = sizes
            }
        } else {
            multiWidths[hashKey] = [width]
        }
    }
    
    @MainActor public func clear() async {
        cache.removeAllObjects()
    }
}
