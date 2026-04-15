//
//  ImageKitExampleView.swift
//  Example
//
//  Created by qhc_m@qq.com on 2024/1/13.
//

import SwiftUI
import ImageKit
import QuickLook
import PhotosUI

private let space: CGFloat = 1
#if os(iOS)
private let lineCount: CGFloat = 3
#else
private let lineCount: CGFloat = 4
#endif

@available(iOS 17.0, macOS 14.0, *)
public struct ImageKitExampleView: View {
    let store: ImagesFromHtml
    public init(store: ImagesFromHtml) {
        self.store = store
    }
    @State private var tapUrl: URL? = nil
    @State private var grayed: Bool = false
    @State private var showImagePicker: Bool = false
    @State private var selectedPhotos: [PhotosPickerItem] = .init()
    @State var onlinePreviewUrl: OnlinePreviewView.Source? = nil
    public var body: some View {
        GeometryReader { reader in
            let cellWidth: CGFloat = (reader.size.width - lineCount + 1) / lineCount
            let columns = Array(repeating: GridItem(.flexible(minimum: cellWidth, maximum: cellWidth), spacing: space), count: Int(lineCount))
            let imageSize = CGSize(width: cellWidth, height: cellWidth)
            ScrollView {
                LazyVGrid(columns: columns, spacing: space) {
                    ForEach(store) { url in
                        let loader = URLImageLoader(.init(url, size: .absolute(imageSize), processors: grayed ? [.Gay, .preDrawn] : .preDrawn))
                        ImageView(loader: loader)
                        .overlay(alignment: .topTrailing) {
                            Text(url.pathExtension)
                                .foregroundColor(.yellow)
                        }
                        .onAppear {
                            store.lastVisitableUrl = url
                        }
                        .onTapGesture {
                            print(url)
//                            tapUrl = DiskCache().localPath(.init(url.absoluteString, size: .absolute(.zero)))
                            onlinePreviewUrl = .init(current: url.id, items: [.init(url: url)])
                        }
                    }
                    if store.items.count < 0 {
                        Text("Empty")
                    }
                }
            }
        }
        .quickLookPreview($tapUrl)
        .photosPicker(isPresented: $showImagePicker, selection: $selectedPhotos, photoLibrary: .shared())
        .task(id: store.state.id) {
            store.send(.fetch)
        }
        .toolbar {
            Toggle(isOn: $grayed) {
                Text("Gray")
            }
            
            Button {
                showImagePicker = true
            } label: {
                Image(systemName: "photo.circle")
            }
        }
        .fullScreenCover(item: $onlinePreviewUrl) { sub in
            OnlinePreviewView(state: sub)
        }
        .onChange(of: selectedPhotos) { oldValue, newValue in
            if let first = newValue.first,
                let id = first.itemIdentifier,
                let url = URL(string: "ph://\(id)") {
                selectedPhotos = .init()
                onlinePreviewUrl = .init(current: url.id, items: [.init(url: url)])
            }
        }
    }
}
