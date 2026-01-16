//
//  ImageView.swift
//  SimpKit
//
//  Created by qhc_m@qq.com on 2022/7/28.
//

import SwiftUI

public enum ImagePhase : Sendable {
    case empty
    case success(KKImage)
    case failure(any Error)
    
    @ViewBuilder func buildView(loader: ImageLoader) -> some View {
        switch self {
        case .success(let image):
            #if os(iOS)
            if loader.request.context.isDisplay() {
                iOSImageView(image, loader: loader)
            } else {
                Text(loader.request.isGif == false ? "\((loader.request.url as NSString).lastPathComponent)" : "gif")
                    .frame(width: loader.request.size.width, height: loader.request.size.height ?? image.size.height / KKScreen.main.scale)
                    .border(color: .green)
            }
            #else
            buildImageView(image)
            #endif
        case .empty:
            ProgressView()
                .frame(width: loader.request.size.width, height: loader.request.size.defaultHeight)
                .border(color: .gray)
        case .failure:
            Text("error")
                .frame(width: loader.request.size.width, height: loader.request.size.defaultHeight)
                .border(color: .red)
        }
    }
    
    #if os(iOS)
    @ViewBuilder private func iOSImageView(_ image: KKImage, loader: ImageLoader) -> some View {
        if loader.request.isGif != false {
            GenericView<AutoResizeImageView> {
                let size = CGSize(width: loader.request.size.width, height: loader.request.size.height ?? 100)
                let view = AutoResizeImageView(size: size)
                view.contentMode = .scaleAspectFill
                return view
            } updater: { view in
                view.image = image
            }
            .frame(width: loader.request.size.width, height: loader.request.size.height)
            .clipped()
            .contentShape(Rectangle())
        } else {
            buildImageView(image, loader: loader)
        }
    }
    #endif
    
    private func buildImageView(_ image: KKImage, loader: ImageLoader) -> some View {
        image.swiftUIView
            .resizable()
            .scaledToFill()
            .frame(width: loader.request.size.width, height: loader.request.size.height)
            .clipped()
    }
}

public class ImageResultObservableObject: ObservableObject {
    @Published public var value: ImagePhase = .empty
    public init() { }
}

public protocol ImageLoader {
    var request: ImageRequest { get }
    var result: ImageResultObservableObject { get }
    func loadImage() async
    func cancel()
}

public extension ImageLoader {
    func cancel() {
        logInfo("ImageLoader cancel")
    }
}

public struct ImageView: View {
    public init(loader: ImageLoader) {
        self.loader = loader
    }
    
    public init(url: URL,
                size: ImageRequest.Size) {
        loader = URLImageLoader(.init(url.absoluteString, size: size))
    }
    private let loader: ImageLoader
    public var body: some View {
        ImageCustomView(loader: loader) {
            $0.buildView(loader: $1)
        }
    }
}

public struct ImageCustomView<Content>: View where Content : View {
    public init(loader: ImageLoader,
                @ViewBuilder content: @escaping (ImagePhase, ImageLoader) -> Content) {
        self.loader = loader
        self.content = content
        self.result = loader.result
    }
    
    public init(url: URL,
                size: ImageRequest.Size,
                @ViewBuilder content: @escaping (ImagePhase, ImageLoader) -> Content) {
        let loader = URLImageLoader(.init(url.absoluteString, size: size))
        self.init(loader: loader, content: content)
    }
    
    let loader: ImageLoader
    let content: (ImagePhase, ImageLoader) -> Content
    @ObservedObject var result: ImageResultObservableObject
    public var body: some View {
        content(result.value, loader)
            .task(id: "\(loader.request.size)-\(loader.request.processors.rawValue)") {
                if case .success = result.value { } else {
                    await loader.loadImage()
                }
            }
    }
}

extension View {
    func border(color: KKColor = KKColor(hex: .random(in: 0...0xffffff))) -> some View {
        #if DEBUG
        self.border(Color(color))
        #else
        self
        #endif
    }
}

private extension ImageRequest.Context {
    nonisolated func isDisplay() -> Bool {
        #if DEBUG
        return tag != 1
        #else
        return true
        #endif
    }
}

extension KKColor {
    @objc public convenience init(hex: Int, alpha: CGFloat = 1) {
        let red = CGFloat((hex >> 16) & 0xFF)
        let green = CGFloat((hex >> 8) & 0xFF)
        let blue = CGFloat(hex & 0xFF)
        self.init(red: red / 255.0, green: green / 255.0, blue: blue / 255.0, alpha: alpha)
    }
}

#if canImport(UIKit)
import UIKit

public class AutoResizeImageView: UIImageView {
    let size: CGSize
    public init(size: CGSize) {
        self.size = size
        super.init(frame: .zero)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override var intrinsicContentSize: CGSize {
        return size
    }
}
#endif
