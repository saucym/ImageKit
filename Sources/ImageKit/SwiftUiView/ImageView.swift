//
//  ImageView.swift
//  SimpKit
//
//  Created by qhc_m@qq.com on 2022/7/28.
//

import SwiftUI

public enum ImageLoaderResult {
    case placeholder
    case error
    case image(KKImage)
}

public class ImageResultObservableObject: ObservableObject {
    @Published public var value: ImageLoaderResult = .placeholder
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

public struct ImageView<Content>: View where Content : View {
    public init(loader: ImageLoader, @ViewBuilder placeholder: @escaping (_ isError: Bool) -> Content) {
        self.loader = loader
        self.placeholder = placeholder
        self.result = loader.result
    }
    
    public init(url: URL, size: ImageRequest.Size, @ViewBuilder placeholder: @escaping (_ isError: Bool) -> Content) {
        let loader = URLImageLoader(.init(url.absoluteString, size: size))
        self.init(loader: loader, placeholder: placeholder)
    }
    
    let loader: ImageLoader
    let placeholder: (Bool) -> Content
    @ObservedObject var result: ImageResultObservableObject
    public var body: some View {
        contentView
            .task(id: "\(loader.request.size)-\(loader.request.processors.rawValue)") {
                if case .image = result.value { } else {
                    await loader.loadImage()
                }
            }
    }
    
    @ViewBuilder var contentView: some View {
        switch result.value {
        case .image(let image):
            #if os(iOS)
            if loader.request.context.isDisplay() {
                iOSImageView(image)
            } else {
                Text(loader.request.isGif == false ? "\((loader.request.url as NSString).lastPathComponent)" : "gif")
                    .frame(width: loader.request.size.width, height: loader.request.size.height ?? image.size.height / KKScreen.main.scale)
            }
            #else
            buildImageView(image)
            #endif
        case .placeholder:
            placeholder(false)
                .frame(width: loader.request.size.width, height: loader.request.size.defaultHeight)
                .border(color: .gray)
        case .error:
            placeholder(true)
                .frame(width: loader.request.size.width, height: loader.request.size.defaultHeight)
                .border(color: .red)
        }
    }
    
    func buildImageView(_ image: KKImage) -> some View {
        image.swiftUIView
            .resizable()
            .scaledToFill()
            .frame(width: loader.request.size.width, height: loader.request.size.height)
            .clipped()
    }
    
    @ViewBuilder func iOSImageView(_ image: KKImage) -> some View {
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
            buildImageView(image)
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
    func isDisplay() -> Bool {
        #if targetEnvironment(simulator)
        #if DEBUG
        return tag != 1
        #endif
        #endif
        return true
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
