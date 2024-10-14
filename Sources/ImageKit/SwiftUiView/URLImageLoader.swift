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
        if let image = try? request.cachedImage() {
            result.value = .image(image)
        }
    }
    
    @MainActor public func loadImage() async {
        do {
            let image = try await request.send()
            result.value = .image(image)
        } catch {
            result.value = .error
            logInfo(error.localizedDescription)
        }
    }
}
