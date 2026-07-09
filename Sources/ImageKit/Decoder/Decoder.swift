//
//  Decoder.swift
//  ImageKit
//

import Foundation

public protocol ImageDecoder {
    func isValid(request: ImageRequest) -> Bool
    func decode(request: ImageRequest, data: Data) throws -> KKImage
}
