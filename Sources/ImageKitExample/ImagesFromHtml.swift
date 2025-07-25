//
//  ImagesFromHtml.swift
//  Example
//
//  Created by qhc_m@qq.com on 2024/1/13.
//

import SwiftUI
import Combine
import RegexBuilder
import Observation

private let cache = NSCache<NSString, NSData>()
private let threshold = 6
@available(iOS 17.0, macOS 14.0, *)
@Observable public final class ImagesFromHtml: ObservableObject, Equatable {
    public static func == (lhs: ImagesFromHtml, rhs: ImagesFromHtml) -> Bool {
        lhs.state == rhs.state && lhs.items == rhs.items
    }
    
    @ObservationIgnored var state: State
    
    public struct State: Identifiable, Codable, Hashable {
        public var id: String { url }
        var url: String
        var name: String
        var sep: String
        var maxPage: Int
        var pageSize: Int
    }
    
    @ObservationIgnored private var pageIndex: Int? = nil
    var items = [URL]()
    @ObservationIgnored private var isLoadingMoreData: Bool = false
    @ObservationIgnored var lastVisitableUrl: URL? = nil
    
    enum Action {
        case fetch
        case loadMore
    }
    
    public convenience init(url: String,
         name: String = "",
         sep: String = "",
         maxPage: Int = 10000,
         pageSize: Int = 10) {
        self.init(state: .init(url: url, name: name, sep: sep, maxPage: maxPage, pageSize: pageSize))
    }
    
    public init(state: State) {
        self.state = state
        let pageIndex: Int?
        if !state.sep.isEmpty {
            let regex = Regex {
                One(state.sep)
                Capture {
                    OneOrMore(.digit)
                }
            }
            pageIndex = .init(state.url.firstMatch(of: regex)?.output.1 ?? "")
        } else {
            pageIndex = nil
        }
        self.pageIndex = pageIndex
    }
    
    func send(_ action: Action) {
        switch action {
        case .fetch:
            if items.isEmpty {
                loadPage(index: nil)
            }
        case .loadMore:
            loadMoreData()
        }
    }
}

@available(iOS 17.0, macOS 14.0, *)
private extension ImagesFromHtml {
    func loadMoreData() {
        guard !isLoadingMoreData else { return }
        isLoadingMoreData = true
        
        loadPage(index: pageIndex)
    }
    
    func loadPage(index: Int?) {
        let url: String
        let sep = state.sep
        if let index, !sep.isEmpty {
            pageIndex = index + 1
            let regex = Regex {
                Capture {
                    One(sep)
                    OneOrMore(.digit)
                }
            }
            url = state.url.replacing(regex, with: sep + "\(index + 1)")
        } else {
            url = state.url
        }
        
        Task {
            do {
                if let pageUrl = URL(string: url) {
                    try await loadImages(url: pageUrl)
                } else {
                    print("count: 0, url: \(url)")
                }
            } catch {
                print(error.localizedDescription)
            }
        }
    }
    
    private func imagesFrom(url: URL) throws -> [URL] {
        let data: Data
        if let old = cache.object(forKey: url.absoluteString as NSString) {
            data = old as Data
        } else {
            data = try Data(contentsOf: url)
            cache.setObject(data as NSData, forKey: url.absoluteString as NSString)
        }
        var html = String(data: data, encoding: .utf8) ?? ""
        if html.isEmpty {
            html = String(data: data, encoding: .ascii) ?? ""
        }
        var images = [URL]()
        
        if images.isEmpty {
            let detector = try NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
            let regularRange = NSRange(location: 0, length: html.count)
            detector.enumerateMatches(in: html, options: [], range: regularRange) { (textCheckingResult, _, stop) in
                if let result = textCheckingResult,
                    let rUrl = result.url,
                    ["jpg", "jpeg", "gif"].contains(rUrl.pathExtension.lowercased()) {
                    images.append(rUrl)
                    if images.count > 1000 {
                        stop.pointee = true
                    }
                }
            }
        }
        
        return images
    }
    
    func loadImages(url: URL) async throws {
        let images = try imagesFrom(url: url)
        if !images.isEmpty {
            let images = images
            await MainActor.run {
                if url.absoluteString == self.state.url {
                    self.items = images.withoutDuplicates()
                } else {
                    var items = self.items
                    items.append(contentsOf: images)
                    self.items = items.withoutDuplicates()
                }
                self.isLoadingMoreData = false
                print("count: \(self.items.count)")
            }
        }
    }
}

@available(iOS 17.0, macOS 14.0, *)
extension ImagesFromHtml: RandomAccessCollection {
    public var startIndex: Int { items.startIndex }
    public var endIndex: Int { items.endIndex }
    public func formIndex(after i: inout Int) {
        i += 1
        
        if i >= (items.count - threshold)
            && !isLoadingMoreData
            && items.count > threshold
            && !state.sep.isEmpty {
            if let lastVisitableUrl, let index = items.firstIndex(of: lastVisitableUrl), i > 60 + index {
                print("---")
            } else {
                send(.loadMore)
            }
        }
    }
    
    public subscript(position: Int) -> URL {
        items[position]
    }
}

extension Sequence {
    
    /// Remove duplicate elements based on condition.
    ///
    ///        [1, 2, 1, 3, 2].withoutDuplicates { $0 } -> [1, 2, 3]
    ///        [(1, 4), (2, 2), (1, 3), (3, 2), (2, 1)].withoutDuplicates { $0.0 } -> [(1, 4), (2, 2), (3, 2)]
    ///
    /// - Parameter transform: A closure that should return the value to be evaluated for repeating elements.
    /// - Returns: Sequence without repeating elements
    /// - Complexity: O(*n*), where *n* is the length of the sequence.
    func withoutDuplicates<H: Hashable>(transform: (Element) throws -> H) rethrows -> [Element] {
        var set = Set<H>()
        return try self.filter { set.insert(try transform($0)).inserted }
    }
    
    func withoutDuplicates() -> [Element] where Element: Hashable {
        return withoutDuplicates { $0 }
    }
}
