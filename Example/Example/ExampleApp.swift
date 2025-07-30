//
//  ExampleApp.swift
//  Example
//
//  Created by qhc_m@qq.com on 2024/9/30.
//

import SwiftUI
import ImageKitExample

@main
struct ExampleApp: App {
    @State var isGif = false
    var body: some Scene {
        WindowGroup {
            let store: ImagesFromHtml = isGif ? .init(url: "http://www.sohu.com/a/216538730_170984") : .init(url: "https://pixabay.com/zh/images/search/?order=ec&pagi=1", sep: "pagi=")
            ImageKitExampleView(store: store)
                .toolbar {
                    Toggle(isOn: $isGif, label: {
                        Text("GIF")
                    })
                }
                .iOSNavigationView()
        }
    }
}

extension View {
    @ViewBuilder func iOSNavigationView() -> some View {
        #if os(iOS)
        NavigationView {
            self
        }
        #else
        self
        #endif
    }
}
