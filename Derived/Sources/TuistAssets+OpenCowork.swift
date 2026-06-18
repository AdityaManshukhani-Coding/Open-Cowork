// swiftlint:disable:this file_name
// swiftlint:disable all
// swift-format-ignore-file
// swiftformat:disable all
// Generated using tuist — https://github.com/tuist/tuist



#if os(macOS)
#if hasFeature(InternalImportsByDefault)
public import AppKit
#else
import AppKit
#endif
#else
#if hasFeature(InternalImportsByDefault)
public import UIKit
#else
import UIKit
#endif
#endif

#if canImport(SwiftUI)
#if hasFeature(InternalImportsByDefault)
public import SwiftUI
#else
import SwiftUI
#endif
#endif

// MARK: - Asset Catalogs

public enum OpenCoworkAsset: Sendable {
  public static let accentColor = OpenCoworkColors(name: "AccentColor")
  public static let anthropic = OpenCoworkImages(name: "anthropic")
  public static let azure = OpenCoworkImages(name: "azure")
  public static let bedrock = OpenCoworkImages(name: "bedrock")
  public static let cerebras = OpenCoworkImages(name: "cerebras")
  public static let claude = OpenCoworkImages(name: "claude")
  public static let cohere = OpenCoworkImages(name: "cohere")
  public static let deepinfra = OpenCoworkImages(name: "deepinfra")
  public static let deepseek = OpenCoworkImages(name: "deepseek")
  public static let fireworks = OpenCoworkImages(name: "fireworks")
  public static let gemini = OpenCoworkImages(name: "gemini")
  public static let groq = OpenCoworkImages(name: "groq")
  public static let huggingface = OpenCoworkImages(name: "huggingface")
  public static let jetbrains = OpenCoworkImages(name: "jetbrains")
  public static let liquidai = OpenCoworkImages(name: "liquidai")
  public static let lmstudio = OpenCoworkImages(name: "lmstudio")
  public static let logo = OpenCoworkImages(name: "logo")
  public static let meta = OpenCoworkImages(name: "meta")
  public static let minimax = OpenCoworkImages(name: "minimax")
  public static let mistral = OpenCoworkImages(name: "mistral")
  public static let moonshot = OpenCoworkImages(name: "moonshot")
  public static let nex = OpenCoworkImages(name: "nex")
  public static let novita = OpenCoworkImages(name: "novita")
  public static let nvidia = OpenCoworkImages(name: "nvidia")
  public static let ollama = OpenCoworkImages(name: "ollama")
  public static let openai = OpenCoworkImages(name: "openai")
  public static let openbmb = OpenCoworkImages(name: "openbmb")
  public static let openrouter = OpenCoworkImages(name: "openrouter")
  public static let perplexity = OpenCoworkImages(name: "perplexity")
  public static let qwen = OpenCoworkImages(name: "qwen")
  public static let sapient = OpenCoworkImages(name: "sapient")
  public static let step = OpenCoworkImages(name: "step")
  public static let togetherai = OpenCoworkImages(name: "togetherai")
  public static let xai = OpenCoworkImages(name: "xai")
  public static let xiaomi = OpenCoworkImages(name: "xiaomi")
  public static let zai = OpenCoworkImages(name: "zai")
}

// MARK: - Implementation Details

public final class OpenCoworkColors: Sendable {
  public let name: String

  #if os(macOS)
  public typealias Color = NSColor
  #elseif os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
  public typealias Color = UIColor
  #endif

  @available(iOS 11.0, tvOS 11.0, watchOS 4.0, macOS 10.13, visionOS 1.0, *)
  public var color: Color {
    guard let color = Color(asset: self) else {
      fatalError("Unable to load color asset named \(name).")
    }
    return color
  }

  #if canImport(SwiftUI)
  @available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 10.15, visionOS 1.0, *)
  public var swiftUIColor: SwiftUI.Color {
      return SwiftUI.Color(asset: self)
  }
  #endif

  fileprivate init(name: String) {
    self.name = name
  }
}

public extension OpenCoworkColors.Color {
  @available(iOS 11.0, tvOS 11.0, watchOS 4.0, macOS 10.13, visionOS 1.0, *)
  convenience init?(asset: OpenCoworkColors) {
    let bundle = Bundle.module
    #if os(iOS) || os(tvOS) || os(visionOS)
    self.init(named: asset.name, in: bundle, compatibleWith: nil)
    #elseif os(macOS)
    self.init(named: NSColor.Name(asset.name), bundle: bundle)
    #elseif os(watchOS)
    self.init(named: asset.name)
    #endif
  }
}

#if canImport(SwiftUI)
@available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 10.15, visionOS 1.0, *)
public extension SwiftUI.Color {
  init(asset: OpenCoworkColors) {
    let bundle = Bundle.module
    self.init(asset.name, bundle: bundle)
  }
}
#endif

public struct OpenCoworkImages: Sendable {
  public let name: String

  #if os(macOS)
  public typealias Image = NSImage
  #elseif os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
  public typealias Image = UIImage
  #endif

  public var image: Image {
    let bundle = Bundle.module
    #if os(iOS) || os(tvOS) || os(visionOS)
    let image = Image(named: name, in: bundle, compatibleWith: nil)
    #elseif os(macOS)
    let image = bundle.image(forResource: NSImage.Name(name))
    #elseif os(watchOS)
    let image = Image(named: name)
    #endif
    guard let result = image else {
      fatalError("Unable to load image asset named \(name).")
    }
    return result
  }

  #if canImport(SwiftUI)
  @available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 10.15, visionOS 1.0, *)
  public var swiftUIImage: SwiftUI.Image {
    SwiftUI.Image(asset: self)
  }
  #endif
}

#if canImport(SwiftUI)
@available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 10.15, visionOS 1.0, *)
public extension SwiftUI.Image {
  init(asset: OpenCoworkImages) {
    let bundle = Bundle.module
    self.init(asset.name, bundle: bundle)
  }

  init(asset: OpenCoworkImages, label: Text) {
    let bundle = Bundle.module
    self.init(asset.name, bundle: bundle, label: label)
  }

  init(decorative asset: OpenCoworkImages) {
    let bundle = Bundle.module
    self.init(decorative: asset.name, bundle: bundle)
  }
}
#endif

// swiftformat:enable all
// swiftlint:enable all
