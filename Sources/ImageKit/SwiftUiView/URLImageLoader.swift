//
//  URLImageLoader.swift
//  SimpKit
//
//  Created by qhc_m@qq.com on 2022/7/28.
//

import SwiftUI

public struct URLImageLoader: ImageLoader, Equatable {
    public static func == (lhs: URLImageLoader, rhs: URLImageLoader) -> Bool {
        return lhs.request.cacheKey() == rhs.request.cacheKey()
    }
    
    public var result: ImageResultObservableObject = .init()
    public let request: ImageRequest
    @MainActor public init(_ request: ImageRequest) {
        self.request = request
        do {
            if let image = try request.cachedImage() {
                result.value = .success(image)
            }
        } catch {
            result.value = .failure(error)
        }
    }
    
    @MainActor public func loadImage() async {
        do {
            let image = try await request.send()
            result.value = .success(image)
        } catch {
            result.value = .failure(error)
            logInfo(error.localizedDescription)
        }
    }
}
