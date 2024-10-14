# ImageKit

support UIKit、AppKit、SwiftUI

```mermaid
graph LR
A[View] -->B(Cache)
    B -->|YES| A
    B -->|NO| C(Loader)
    C -->|Data| D(Decoder)
    C -->|Image| E[Processor]
    D --> E
    E -->|Predrawn| A
```

## Feature
1. Cache: Memory
1. Loader: Disk、Local、Network
1. Decoder: Image、Gif
1. Processor: Predrawn、Gray

## Usage
     
SwiftUI
```swift
ImageView(url: url, size: .absolute(size)) { isError in
    Text(isError ? "error" : "loading")
}
```
