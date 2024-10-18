//
//  ImagesFromHtml.swift
//  Example
//
//  Created by qhc_m@qq.com on 2024/1/13.
//

import SwiftUI
import Combine
import RegexBuilder

private let threshold = 6
final class ImagesFromHtml: ObservableObject, Equatable {
    static func == (lhs: ImagesFromHtml, rhs: ImagesFromHtml) -> Bool {
        lhs.state == rhs.state && lhs.items == rhs.items
    }
    
    var state: State
    
    struct State: Identifiable, Codable, Hashable {
        public var id: String { url }
        var url: String
        var name: String
        var sep: String
        var maxPage: Int
        var pageSize: Int
    }
    
    private var pageIndex: Int? = nil
    @Published var items = [URL]()
    private var isLoadingMoreData: Bool = false
    var lastVisitableUrl: URL? = nil
    
    enum Action {
        case fetch
        case loadMore
    }
    
    convenience init(url: String,
         name: String = "",
         sep: String = "",
         maxPage: Int = 10000,
         pageSize: Int = 10) {
        self.init(state: .init(url: url, name: name, sep: sep, maxPage: maxPage, pageSize: pageSize))
    }
    
    init(state: State) {
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
    
    func loadImages(url: URL) async throws {
        let data = try Data(contentsOf: url)
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

extension ImagesFromHtml: RandomAccessCollection {
    var startIndex: Int { items.startIndex }
    var endIndex: Int { items.endIndex }
    func formIndex(after i: inout Int) {
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
    
    subscript(position: Int) -> URL {
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
