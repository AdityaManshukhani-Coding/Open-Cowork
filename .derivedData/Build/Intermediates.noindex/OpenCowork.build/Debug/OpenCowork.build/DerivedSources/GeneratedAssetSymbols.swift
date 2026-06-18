import Foundation
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif
#if canImport(SwiftUI)
import SwiftUI
#endif
#if canImport(DeveloperToolsSupport)
import DeveloperToolsSupport
#endif

#if SWIFT_PACKAGE
private let resourceBundle = Foundation.Bundle.module
#else
private class ResourceBundleClass {}
private let resourceBundle = Foundation.Bundle(for: ResourceBundleClass.self)
#endif

// MARK: - Color Symbols -

@available(iOS 11.0, macOS 10.13, tvOS 11.0, *)
extension ColorResource {

}

// MARK: - Image Symbols -

@available(iOS 11.0, macOS 10.7, tvOS 11.0, *)
extension ImageResource {

    /// The "anthropic" asset catalog image resource.
    static let anthropic = ImageResource(name: "anthropic", bundle: resourceBundle)

    /// The "azure" asset catalog image resource.
    static let azure = ImageResource(name: "azure", bundle: resourceBundle)

    /// The "bedrock" asset catalog image resource.
    static let bedrock = ImageResource(name: "bedrock", bundle: resourceBundle)

    /// The "cerebras" asset catalog image resource.
    static let cerebras = ImageResource(name: "cerebras", bundle: resourceBundle)

    /// The "claude" asset catalog image resource.
    static let claude = ImageResource(name: "claude", bundle: resourceBundle)

    /// The "cohere" asset catalog image resource.
    static let cohere = ImageResource(name: "cohere", bundle: resourceBundle)

    /// The "deepinfra" asset catalog image resource.
    static let deepinfra = ImageResource(name: "deepinfra", bundle: resourceBundle)

    /// The "deepseek" asset catalog image resource.
    static let deepseek = ImageResource(name: "deepseek", bundle: resourceBundle)

    /// The "fireworks" asset catalog image resource.
    static let fireworks = ImageResource(name: "fireworks", bundle: resourceBundle)

    /// The "gemini" asset catalog image resource.
    static let gemini = ImageResource(name: "gemini", bundle: resourceBundle)

    /// The "groq" asset catalog image resource.
    static let groq = ImageResource(name: "groq", bundle: resourceBundle)

    /// The "huggingface" asset catalog image resource.
    static let huggingface = ImageResource(name: "huggingface", bundle: resourceBundle)

    /// The "jetbrains" asset catalog image resource.
    static let jetbrains = ImageResource(name: "jetbrains", bundle: resourceBundle)

    /// The "liquidai" asset catalog image resource.
    static let liquidai = ImageResource(name: "liquidai", bundle: resourceBundle)

    /// The "lmstudio" asset catalog image resource.
    static let lmstudio = ImageResource(name: "lmstudio", bundle: resourceBundle)

    /// The "logo" asset catalog image resource.
    static let logo = ImageResource(name: "logo", bundle: resourceBundle)

    /// The "meta" asset catalog image resource.
    static let meta = ImageResource(name: "meta", bundle: resourceBundle)

    /// The "minimax" asset catalog image resource.
    static let minimax = ImageResource(name: "minimax", bundle: resourceBundle)

    /// The "mistral" asset catalog image resource.
    static let mistral = ImageResource(name: "mistral", bundle: resourceBundle)

    /// The "moonshot" asset catalog image resource.
    static let moonshot = ImageResource(name: "moonshot", bundle: resourceBundle)

    /// The "nex" asset catalog image resource.
    static let nex = ImageResource(name: "nex", bundle: resourceBundle)

    /// The "novita" asset catalog image resource.
    static let novita = ImageResource(name: "novita", bundle: resourceBundle)

    /// The "nvidia" asset catalog image resource.
    static let nvidia = ImageResource(name: "nvidia", bundle: resourceBundle)

    /// The "ollama" asset catalog image resource.
    static let ollama = ImageResource(name: "ollama", bundle: resourceBundle)

    /// The "openai" asset catalog image resource.
    static let openai = ImageResource(name: "openai", bundle: resourceBundle)

    /// The "openbmb" asset catalog image resource.
    static let openbmb = ImageResource(name: "openbmb", bundle: resourceBundle)

    /// The "openrouter" asset catalog image resource.
    static let openrouter = ImageResource(name: "openrouter", bundle: resourceBundle)

    /// The "perplexity" asset catalog image resource.
    static let perplexity = ImageResource(name: "perplexity", bundle: resourceBundle)

    /// The "qwen" asset catalog image resource.
    static let qwen = ImageResource(name: "qwen", bundle: resourceBundle)

    /// The "sapient" asset catalog image resource.
    static let sapient = ImageResource(name: "sapient", bundle: resourceBundle)

    /// The "step" asset catalog image resource.
    static let step = ImageResource(name: "step", bundle: resourceBundle)

    /// The "togetherai" asset catalog image resource.
    static let togetherai = ImageResource(name: "togetherai", bundle: resourceBundle)

    /// The "xai" asset catalog image resource.
    static let xai = ImageResource(name: "xai", bundle: resourceBundle)

    /// The "xiaomi" asset catalog image resource.
    static let xiaomi = ImageResource(name: "xiaomi", bundle: resourceBundle)

    /// The "zai" asset catalog image resource.
    static let zai = ImageResource(name: "zai", bundle: resourceBundle)

}

// MARK: - Backwards Deployment Support -

/// A color resource.
struct ColorResource: Swift.Hashable, Swift.Sendable {

    /// An asset catalog color resource name.
    fileprivate let name: Swift.String

    /// An asset catalog color resource bundle.
    fileprivate let bundle: Foundation.Bundle

    /// Initialize a `ColorResource` with `name` and `bundle`.
    init(name: Swift.String, bundle: Foundation.Bundle) {
        self.name = name
        self.bundle = bundle
    }

}

/// An image resource.
struct ImageResource: Swift.Hashable, Swift.Sendable {

    /// An asset catalog image resource name.
    fileprivate let name: Swift.String

    /// An asset catalog image resource bundle.
    fileprivate let bundle: Foundation.Bundle

    /// Initialize an `ImageResource` with `name` and `bundle`.
    init(name: Swift.String, bundle: Foundation.Bundle) {
        self.name = name
        self.bundle = bundle
    }

}

#if canImport(AppKit)
@available(macOS 10.13, *)
@available(macCatalyst, unavailable)
extension AppKit.NSColor {

    /// Initialize a `NSColor` with a color resource.
    convenience init(resource: ColorResource) {
        self.init(named: NSColor.Name(resource.name), bundle: resource.bundle)!
    }

}

protocol _ACResourceInitProtocol {}
extension AppKit.NSImage: _ACResourceInitProtocol {}

@available(macOS 10.7, *)
@available(macCatalyst, unavailable)
extension _ACResourceInitProtocol {

    /// Initialize a `NSImage` with an image resource.
    init(resource: ImageResource) {
        self = resource.bundle.image(forResource: NSImage.Name(resource.name))! as! Self
    }

}
#endif

#if canImport(UIKit)
@available(iOS 11.0, tvOS 11.0, *)
@available(watchOS, unavailable)
extension UIKit.UIColor {

    /// Initialize a `UIColor` with a color resource.
    convenience init(resource: ColorResource) {
#if !os(watchOS)
        self.init(named: resource.name, in: resource.bundle, compatibleWith: nil)!
#else
        self.init()
#endif
    }

}

@available(iOS 11.0, tvOS 11.0, *)
@available(watchOS, unavailable)
extension UIKit.UIImage {

    /// Initialize a `UIImage` with an image resource.
    convenience init(resource: ImageResource) {
#if !os(watchOS)
        self.init(named: resource.name, in: resource.bundle, compatibleWith: nil)!
#else
        self.init()
#endif
    }

}
#endif

#if canImport(SwiftUI)
@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
extension SwiftUI.Color {

    /// Initialize a `Color` with a color resource.
    init(_ resource: ColorResource) {
        self.init(resource.name, bundle: resource.bundle)
    }

}

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
extension SwiftUI.Image {

    /// Initialize an `Image` with an image resource.
    init(_ resource: ImageResource) {
        self.init(resource.name, bundle: resource.bundle)
    }

}
#endif