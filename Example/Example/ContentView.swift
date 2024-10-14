//
//  ContentView.swift
//  Example
//
//  Created by qhc_m@qq.com on 2024/1/13.
//

import SwiftUI
import ImageKit
import QuickLook

private let space: CGFloat = 1
#if os(iOS)
private let lineCount: CGFloat = 3
#else
private let lineCount: CGFloat = 4
#endif

extension URL: Identifiable {
    public var id: URL { self }
}

struct ContentView: View {
    @ObservedObject var store: ImageListStore
    @State private var tapUrl: URL? = nil
    @State private var grayed: Bool = false
    var body: some View {
        GeometryReader { reader in
            let cellWidth: CGFloat = (reader.size.width - lineCount + 1) / lineCount
            let columns = Array(repeating: GridItem(.flexible(minimum: cellWidth, maximum: cellWidth), spacing: space), count: Int(lineCount))
            let imageSize = CGSize(width: cellWidth, height: cellWidth)
            ScrollView {
                LazyVGrid(columns: columns, spacing: space) {
                    ForEach(store) { url in
                        let loader = URLImageLoader(.init(url.absoluteString, size: .absolute(imageSize), processors: grayed ? [.Gay, .preDrawn] : .preDrawn))
                        ImageView(loader: loader) { isError in
                            Text(isError ? "error" : "loading")
                        }
                        .overlay(alignment: .topTrailing) {
                            Text(url.pathExtension)
                        }
                        .onAppear {
                            store.lastVisitableUrl = url
                        }
                        .onTapGesture {
                            print(url)
                            tapUrl = DiskCache().localPath(.init(url.absoluteString, size: .absolute(.zero)))
                        }
                    }
                }
            }
        }
        .quickLookPreview($tapUrl)
        .onChange(of: store.state.id) { _, _ in
            store.send(.fetch)
        }
        .onAppear {
            store.send(.fetch)
        }
        .toolbar {
            Toggle(isOn: $grayed) {
                Text("Gray")
            }
        }
    }
}
