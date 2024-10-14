//
//  MemoryCache.swift
//  ImageKit
//
//  Created by saucymqin on 2018/7/10.
//

import Foundation
import SwiftUI

public protocol CacheProtocol {
    func isValid(request: ImageRequest) -> Bool
    func imageFor(request: ImageRequest) throws -> KKImage?
    func cache(image: KKImage, for request: ImageRequest)
    func clear() async
}

public class MemoryCache {
    public static let shared = MemoryCache()
    var multiWidths = [Int: [Int]]()// key.hash : [size.width1, size.width2]
    let cache = NSCache<NSNumber, KKImage>()
    nonisolated public func isValid(request: ImageRequest) -> Bool {
        return request.caches.contains(.Memory)
    }
    
    func keyNumberFor(request: ImageRequest, width: Int) -> NSNumber {
        return NSNumber(value: request.cacheKey(width: CGFloat(width)))
    }
    
    func cacheImageFor(request: ImageRequest) -> KKImage? {
        let hashKey = request.key.hash
        let width = Int(exactly: request.size.width * kScale) ?? 0
        let key = keyNumberFor(request: request, width: width)
        if let image = cache.object(forKey: key) {
            return image
        } else {//get memory cache of bigger size
            if let sizes = self.multiWidths[hashKey] {
                for biggerWidth in sizes {
                    if biggerWidth > width {
                        let biggerKey = keyNumberFor(request: request, width: biggerWidth)
                        if let image = cache.object(forKey: biggerKey) {
                            return image
                        }
                    }
                }
            }
        }
        
        return nil
    }
}

extension MemoryCache: CacheProtocol {
    @MainActor public func imageFor(request: ImageRequest) throws -> KKImage? {
        if let image = cacheImageFor(request: request) {
            return image
        }
        
        return nil
    }
    
    @MainActor public func cache(image: KKImage, for request: ImageRequest) {
        let hashKey = request.key.hash
        let width = Int(exactly: max(image.size.width, request.size.width * kScale)) ?? 0
        let key = self.keyNumberFor(request: request, width: width)
        cache.setObject(image, forKey: key)
        
        if var sizes = self.multiWidths[hashKey] {
            if sizes.contains(width) == false {
                sizes.append(width) // TODO: Here you can consider sorting from smallest to largest
                self.multiWidths[hashKey] = sizes
            }
        } else {
            self.multiWidths[hashKey] = [width]
        }
    }
    
    @MainActor public func clear() async {
        cache.removeAllObjects()
    }
}
