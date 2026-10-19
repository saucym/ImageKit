public enum IKError: Error {
    case decoderIsEmpty
    case loaderIsEmpty
    case imageSourceCreateError
    case decoderImageIsNil
    case invalidHTTPStatus(Int)
}

