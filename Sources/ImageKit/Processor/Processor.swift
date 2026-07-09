//
//  Processor.swift
//  ImageKit
//

import Foundation

public protocol ImageProcessor {
    func isValid(request: ImageRequest) -> Bool
    func process(request: ImageRequest, input: KKImage) -> KKImage
}
