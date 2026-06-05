import AVFoundation
import CoreGraphics
import Foundation
import UIKit

struct ManicSkin {
    let name: String
    let baseURL: URL
    let definition: ManicSkinDefinition
    private let resources: ManicSkinResourceProvider

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
        let resources = ManicSkinResourceProvider(baseURL: baseURL)
        do {
            guard let data = resources.data(named: "info.json") else {
                NSLog("Manic skin info.json not found at %@", baseURL.path)
                return nil
            }
            let definition = try JSONDecoder().decode(ManicSkinDefinition.self, from: data)
            self.name = definition.name
            self.baseURL = baseURL
            self.definition = definition
            self.resources = resources
        } catch {
            NSLog("Manic skin failed to load %@: %@", baseURL.path, error.localizedDescription)
            return nil
        }
    }

    func asset(named name: String) -> ManicSkinResource {
        resources.resource(named: name)
    }

    func resolvedRepresentation(
        in bounds: CGRect,
        safeAreaInsets: UIEdgeInsets,
        traitCollection: UITraitCollection,
        interfaceOrientation: UIInterfaceOrientation?,
        styleReferenceBounds: CGRect? = nil,
        styleReferenceSafeAreaInsets: UIEdgeInsets? = nil
    ) -> ManicSkinResolvedRepresentation? {
        guard bounds.width > 1, bounds.height > 1 else {
            return nil
        }

        let deviceKey = traitCollection.userInterfaceIdiom == .pad ? "ipad" : "iphone"
        let styleKey = preferredStyleKey(
            for: deviceKey,
            bounds: styleReferenceBounds ?? bounds,
            safeAreaInsets: styleReferenceSafeAreaInsets ?? safeAreaInsets
        )
        let orientationKey = Self.orientationKey(
            for: interfaceOrientation,
            bounds: bounds
        )

        guard let representation = representation(
            deviceKey: deviceKey,
            styleKey: styleKey,
            orientationKey: orientationKey
        ) else {
            NSLog("Manic skin representation unavailable for %@/%@/%@", deviceKey, styleKey, orientationKey)
            return nil
        }

        let backgroundName = representation.assets.resizable ?? representation.assets.standard
        let backgroundResource = backgroundName.map(asset(named:))
        let designSize = designSize(for: representation)
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
                let visualFrame = Self.thumbstickVisualFrame(
                    in: transformedFrame,
                    thumbstick: thumbstick,
                    scale: scale
                )
                return ManicSkinResolvedItem(
                    id: index,
                    kind: .thumbstick(element: element),
                    asset: asset(named: thumbstick.name),
                    frame: transformedFrame,
                    visualFrame: visualFrame,
                    hitFrame: hitFrame,
                    scale: scale
                )
            }

            guard let assetName = item.asset?.normal else {
                return nil
            }
            let inputs: [String]
            switch item.inputs {
            case .buttons(let buttonInputs):
                inputs = buttonInputs
            case .analog(let mappedInputs):
                inputs = Set(mappedInputs.values).sorted()
            }
            guard !inputs.isEmpty else {
                return nil
            }

            return ManicSkinResolvedItem(
                id: index,
                kind: .buttons(inputs),
                asset: asset(named: assetName),
                frame: transformedFrame,
                visualFrame: transformedFrame,
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
            background: backgroundResource,
            screenFrame: screenFrame,
            items: resolvedItems
        )
    }

    func previewAspectRatio(
        for orientation: ManicSkinPreviewOrientation,
        traitCollection: UITraitCollection? = nil,
        screenBounds: CGRect = UIScreen.main.bounds,
        safeAreaInsets: UIEdgeInsets = .zero
    ) -> CGFloat? {
        let deviceKey = (traitCollection?.userInterfaceIdiom ?? UIDevice.current.userInterfaceIdiom) == .pad ?
            "ipad" :
            "iphone"
        let styleKey = preferredStyleKey(
            for: deviceKey,
            bounds: screenBounds,
            safeAreaInsets: safeAreaInsets
        )
        guard let representation = representation(
            deviceKey: deviceKey,
            styleKey: styleKey,
            orientationKey: orientation.representationKey
        ) else {
            return nil
        }

        let size = designSize(for: representation)
        guard size.width > 1, size.height > 1 else {
            return nil
        }
        return size.width / size.height
    }

    private func representation(
        deviceKey: String,
        styleKey: String,
        orientationKey: String
    ) -> ManicSkinRepresentation? {
        guard let deviceRepresentations = definition.representations[deviceKey] else {
            return nil
        }

        return (deviceRepresentations[styleKey] ?? deviceRepresentations["standard"])?[orientationKey]
    }

    private func designSize(for representation: ManicSkinRepresentation) -> CGSize {
        let backgroundName = representation.assets.resizable ?? representation.assets.standard
        let backgroundResource = backgroundName.map(asset(named:))
        return representation.mappingSize?.size ??
            backgroundResource.flatMap { ManicSkinPDFRenderer.pageSize(for: $0) } ??
            representation.itemExtents
    }

    private static func thumbstickVisualFrame(
        in frame: CGRect,
        thumbstick: ManicSkinThumbstick,
        scale: CGFloat
    ) -> CGRect {
        let width = (thumbstick.width ?? frame.width / scale) * scale
        let height = (thumbstick.height ?? frame.height / scale) * scale
        guard width > 1, height > 1 else {
            return frame
        }

        return CGRect(
            x: frame.midX - width * 0.5,
            y: frame.midY - height * 0.5,
            width: width,
            height: height
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

enum ManicSkinPreviewOrientation: String, CaseIterable, Identifiable {
    case portrait
    case landscape

    var id: String { rawValue }

    var title: String {
        switch self {
        case .portrait:
            return "Portrait"
        case .landscape:
            return "Landscape"
        }
    }

    var representationKey: String {
        rawValue
    }

    var interfaceOrientation: UIInterfaceOrientation {
        switch self {
        case .portrait:
            return .portrait
        case .landscape:
            return .landscapeRight
        }
    }

    var fallbackAspectRatio: CGFloat {
        switch self {
        case .portrait:
            return UIDevice.current.userInterfaceIdiom == .pad ? 0.75 : 0.48
        case .landscape:
            return UIDevice.current.userInterfaceIdiom == .pad ? 1.33 : 2.05
        }
    }
}

struct ManicSkinLibraryItem: Identifiable, Equatable {
    let url: URL
    let definitionName: String

    var id: String { url.standardizedFileURL.path }
    var fileName: String { url.lastPathComponent }
    var displayName: String { url.deletingPathExtension().lastPathComponent }

    init?(url: URL) {
        guard let skin = ManicSkin(baseURL: url) else {
            return nil
        }

        self.url = url
        definitionName = skin.name
    }

    func makeSkin() -> ManicSkin? {
        ManicSkin(baseURL: url)
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
    let background: ManicSkinResource?
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
    let asset: ManicSkinResource
    let frame: CGRect
    let visualFrame: CGRect
    let hitFrame: CGRect
    let scale: CGFloat
}

private enum ManicSkinResourceProvider {
    case directory(URL)
    case archive(URL)

    init(baseURL: URL) {
        let values = try? baseURL.resourceValues(forKeys: [.isDirectoryKey])
        if values?.isDirectory == true {
            self = .directory(baseURL)
        } else {
            self = .archive(baseURL)
        }
    }

    func resource(named name: String) -> ManicSkinResource {
        switch self {
        case .directory(let baseURL):
            return ManicSkinResource(source: .file(baseURL.appendingPathComponent(name)))
        case .archive(let archiveURL):
            return ManicSkinResource(source: .archive(archiveURL: archiveURL, entryName: name))
        }
    }

    func data(named name: String) -> Data? {
        resource(named: name).data()
    }
}

struct ManicSkinResource {
    enum Source {
        case file(URL)
        case archive(archiveURL: URL, entryName: String)
    }

    let source: Source

    var cacheKey: String {
        switch source {
        case .file(let url):
            return url.path
        case .archive(let archiveURL, let entryName):
            return "\(archiveURL.path)#\(entryName)"
        }
    }

    func data() -> Data? {
        switch source {
        case .file(let url):
            return try? Data(contentsOf: url)
        case .archive(let archiveURL, let entryName):
            return try? DukeXZipArchive.data(
                forEntryNamed: entryName,
                inArchiveAtPath: archiveURL.path
            )
        }
    }
}

enum ManicSkinPDFRenderer {
    private static let imageCache = NSCache<NSString, UIImage>()
    private static let sizeCache = NSCache<NSString, NSValue>()

    static func pageSize(for resource: ManicSkinResource) -> CGSize? {
        let key = resource.cacheKey as NSString
        if let cached = sizeCache.object(forKey: key) {
            return cached.cgSizeValue
        }

        guard let page = page(for: resource) else {
            return nil
        }

        let size = page.getBoxRect(.mediaBox).size
        sizeCache.setObject(NSValue(cgSize: size), forKey: key)
        return size
    }

    static func image(for resource: ManicSkinResource, targetSize: CGSize, scale: CGFloat) -> UIImage? {
        guard targetSize.width > 1, targetSize.height > 1 else {
            return nil
        }

        let pixelWidth = Int((targetSize.width * scale).rounded())
        let pixelHeight = Int((targetSize.height * scale).rounded())
        let cacheKey = "\(resource.cacheKey)#\(pixelWidth)x\(pixelHeight)" as NSString
        if let image = imageCache.object(forKey: cacheKey) {
            return image
        }

        guard let page = page(for: resource) else {
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

    private static func page(for resource: ManicSkinResource) -> CGPDFPage? {
        let provider: CGDataProvider?
        switch resource.source {
        case .file(let url):
            provider = CGDataProvider(url: url as CFURL)
        case .archive:
            provider = resource.data().flatMap { CGDataProvider(data: $0 as CFData) }
        }

        guard let provider,
              let document = CGPDFDocument(provider) else {
            return nil
        }
        return document.page(at: 1)
    }
}
