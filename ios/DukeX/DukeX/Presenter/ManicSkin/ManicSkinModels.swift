import AVFoundation
import CoreGraphics
import Foundation
import UIKit

struct ManicSkin {
    let name: String
    let baseURL: URL
    let definition: ManicSkinDefinition

    static func bundledPS1() -> ManicSkin? {
        guard let baseURL = Bundle.main.url(
            forResource: "PS1",
            withExtension: "manicskin",
            subdirectory: "Skins"
        ) else {
            NSLog("Manic skin resource not found: Skins/PS1.manicskin")
            return nil
        }

        return ManicSkin(baseURL: baseURL)
    }

    init?(baseURL: URL) {
        let infoURL = baseURL.appendingPathComponent("info.json")
        do {
            let data = try Data(contentsOf: infoURL)
            let definition = try JSONDecoder().decode(ManicSkinDefinition.self, from: data)
            self.name = definition.name
            self.baseURL = baseURL
            self.definition = definition
        } catch {
            NSLog("Manic skin failed to load %@: %@", infoURL.path, error.localizedDescription)
            return nil
        }
    }

    func assetURL(named name: String) -> URL {
        baseURL.appendingPathComponent(name)
    }

    func resolvedRepresentation(
        in bounds: CGRect,
        safeAreaInsets: UIEdgeInsets,
        traitCollection: UITraitCollection,
        interfaceOrientation: UIInterfaceOrientation?
    ) -> ManicSkinResolvedRepresentation? {
        guard bounds.width > 1, bounds.height > 1 else {
            return nil
        }

        let deviceKey = traitCollection.userInterfaceIdiom == .pad ? "ipad" : "iphone"
        let styleKey = preferredStyleKey(
            for: deviceKey,
            bounds: bounds,
            safeAreaInsets: safeAreaInsets
        )
        let orientationKey = Self.orientationKey(
            for: interfaceOrientation,
            bounds: bounds
        )

        guard let deviceRepresentations = definition.representations[deviceKey],
              let styleRepresentations = deviceRepresentations[styleKey] ?? deviceRepresentations["standard"],
              let representation = styleRepresentations[orientationKey] else {
            NSLog("Manic skin representation unavailable for %@/%@/%@", deviceKey, styleKey, orientationKey)
            return nil
        }

        let backgroundName = representation.assets.resizable ?? representation.assets.standard
        let backgroundURL = backgroundName.map(assetURL(named:))
        let designSize = representation.mappingSize?.size ??
            backgroundURL.flatMap { ManicSkinPDFRenderer.pageSize(for: $0) } ??
            representation.itemExtents
        guard designSize.width > 1, designSize.height > 1 else {
            return nil
        }

        let skinFrame = AVMakeRect(aspectRatio: designSize, insideRect: bounds)
        let scale = min(skinFrame.width / designSize.width, skinFrame.height / designSize.height)
        func transformedFrame(_ frame: ManicSkinFrame) -> CGRect {
            CGRect(
                x: skinFrame.minX + frame.x * scale,
                y: skinFrame.minY + frame.y * scale,
                width: frame.width * scale,
                height: frame.height * scale
            )
        }

        let resolvedItems = representation.items.enumerated().compactMap { index, item -> ManicSkinResolvedItem? in
            guard let frame = item.frame else {
                return nil
            }

            let transformedFrame = transformedFrame(frame)
            let extendedEdges = item.extendedEdges ?? .zero
            let hitFrame = transformedFrame.insetBy(
                dx: -(extendedEdges.left + extendedEdges.right) * scale * 0.5,
                dy: -(extendedEdges.top + extendedEdges.bottom) * scale * 0.5
            ).offsetBy(
                dx: (extendedEdges.right - extendedEdges.left) * scale * 0.5,
                dy: (extendedEdges.bottom - extendedEdges.top) * scale * 0.5
            )

            if let thumbstick = item.thumbstick,
               case .analog(let inputs) = item.inputs {
                let element = ManicSkinInputMapper.thumbstickElement(for: inputs)
                return ManicSkinResolvedItem(
                    id: index,
                    kind: .thumbstick(element: element),
                    assetURL: assetURL(named: thumbstick.name),
                    frame: transformedFrame,
                    hitFrame: hitFrame,
                    scale: scale
                )
            }

            guard let assetName = item.asset?.normal,
                  case .buttons(let inputs) = item.inputs else {
                return nil
            }

            return ManicSkinResolvedItem(
                id: index,
                kind: .buttons(inputs),
                assetURL: assetURL(named: assetName),
                frame: transformedFrame,
                hitFrame: hitFrame,
                scale: scale
            )
        }
        let screenFrame = representation.screens?
            .compactMap(\.outputFrame)
            .map(transformedFrame)
            .first

        return ManicSkinResolvedRepresentation(
            key: "\(deviceKey)-\(styleKey)-\(orientationKey)",
            skinFrame: skinFrame,
            backgroundURL: backgroundURL,
            screenFrame: screenFrame,
            items: resolvedItems
        )
    }

    private func preferredStyleKey(
        for deviceKey: String,
        bounds: CGRect,
        safeAreaInsets: UIEdgeInsets
    ) -> String {
        guard deviceKey == "iphone" else {
            return "standard"
        }

        let hasUnsafeEdges = safeAreaInsets.top > 20 || safeAreaInsets.bottom > 0 ||
            max(bounds.width, bounds.height) >= 812
        return hasUnsafeEdges ? "edgeToEdge" : "standard"
    }

    private static func orientationKey(
        for interfaceOrientation: UIInterfaceOrientation?,
        bounds: CGRect
    ) -> String {
        switch interfaceOrientation {
        case .landscapeLeft, .landscapeRight:
            return "landscape"
        case .portrait, .portraitUpsideDown:
            return "portrait"
        default:
            return bounds.width > bounds.height ? "landscape" : "portrait"
        }
    }
}

struct ManicSkinDefinition: Decodable {
    let gameTypeIdentifier: String
    let identifier: String
    let name: String
    let representations: [String: [String: [String: ManicSkinRepresentation]]]
}

struct ManicSkinRepresentation: Decodable {
    let assets: ManicSkinRepresentationAssets
    let items: [ManicSkinItem]
    let mappingSize: ManicSkinSize?
    let screens: [ManicSkinScreen]?

    var itemExtents: CGSize {
        let width = items.compactMap { item -> CGFloat? in
            guard let frame = item.frame else { return nil }
            return frame.x + frame.width
        }.max() ?? 1
        let height = items.compactMap { item -> CGFloat? in
            guard let frame = item.frame else { return nil }
            return frame.y + frame.height
        }.max() ?? 1
        return CGSize(width: width, height: height)
    }
}

struct ManicSkinRepresentationAssets: Decodable {
    let resizable: String?
    let standard: String?
}

struct ManicSkinSize: Decodable {
    let width: CGFloat
    let height: CGFloat

    var size: CGSize {
        CGSize(width: width, height: height)
    }
}

struct ManicSkinScreen: Decodable {
    let outputFrame: ManicSkinFrame?
}

struct ManicSkinItem: Decodable {
    let asset: ManicSkinAsset?
    let thumbstick: ManicSkinThumbstick?
    let inputs: ManicSkinInputs
    let frame: ManicSkinFrame?
    let extendedEdges: ManicSkinExtendedEdges?
}

struct ManicSkinAsset: Decodable {
    let normal: String?
}

struct ManicSkinThumbstick: Decodable {
    let name: String
    let width: CGFloat?
    let height: CGFloat?
}

enum ManicSkinInputs: Decodable {
    case buttons([String])
    case analog([String: String])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let inputs = try? container.decode([String].self) {
            self = .buttons(inputs)
            return
        }
        self = .analog(try container.decode([String: String].self))
    }
}

struct ManicSkinFrame: Decodable {
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat
}

struct ManicSkinExtendedEdges: Decodable {
    static let zero = ManicSkinExtendedEdges(top: 0, bottom: 0, left: 0, right: 0)

    let top: CGFloat
    let bottom: CGFloat
    let left: CGFloat
    let right: CGFloat
}

struct ManicSkinResolvedRepresentation {
    let key: String
    let skinFrame: CGRect
    let backgroundURL: URL?
    let screenFrame: CGRect?
    let items: [ManicSkinResolvedItem]
}

struct ManicSkinResolvedItem {
    enum Kind {
        case buttons([String])
        case thumbstick(element: String)
    }

    let id: Int
    let kind: Kind
    let assetURL: URL
    let frame: CGRect
    let hitFrame: CGRect
    let scale: CGFloat
}

enum ManicSkinPDFRenderer {
    private static let imageCache = NSCache<NSString, UIImage>()
    private static let sizeCache = NSCache<NSString, NSValue>()

    static func pageSize(for url: URL) -> CGSize? {
        let key = url.path as NSString
        if let cached = sizeCache.object(forKey: key) {
            return cached.cgSizeValue
        }

        guard let page = page(for: url) else {
            return nil
        }

        let size = page.getBoxRect(.mediaBox).size
        sizeCache.setObject(NSValue(cgSize: size), forKey: key)
        return size
    }

    static func image(for url: URL, targetSize: CGSize, scale: CGFloat) -> UIImage? {
        guard targetSize.width > 1, targetSize.height > 1 else {
            return nil
        }

        let pixelWidth = Int((targetSize.width * scale).rounded())
        let pixelHeight = Int((targetSize.height * scale).rounded())
        let cacheKey = "\(url.path)#\(pixelWidth)x\(pixelHeight)" as NSString
        if let image = imageCache.object(forKey: cacheKey) {
            return image
        }

        guard let page = page(for: url) else {
            return nil
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let image = renderer.image { context in
            let cgContext = context.cgContext
            let bounds = CGRect(origin: .zero, size: targetSize)
            cgContext.clear(bounds)
            cgContext.saveGState()
            cgContext.translateBy(x: 0, y: bounds.height)
            cgContext.scaleBy(x: 1, y: -1)
            cgContext.concatenate(page.getDrawingTransform(.mediaBox, rect: bounds, rotate: 0, preserveAspectRatio: true))
            cgContext.drawPDFPage(page)
            cgContext.restoreGState()
        }

        imageCache.setObject(image, forKey: cacheKey)
        return image
    }

    private static func page(for url: URL) -> CGPDFPage? {
        guard let provider = CGDataProvider(url: url as CFURL),
              let document = CGPDFDocument(provider) else {
            return nil
        }
        return document.page(at: 1)
    }
}
