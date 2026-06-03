import Metal
import QuartzCore
import UIKit

final class NativeMetalPresenterView: UIView {
    override class var layerClass: AnyClass {
        CAMetalLayer.self
    }

    var metalLayer: CAMetalLayer {
        layer as! CAMetalLayer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = true
        backgroundColor = .black
        contentMode = .scaleAspectFit
        configureMetalLayer()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        isOpaque = true
        backgroundColor = .black
        contentMode = .scaleAspectFit
        configureMetalLayer()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateDrawableSize()
    }

    func refreshDrawableSize() {
        setNeedsLayout()
        layoutIfNeeded()
        updateDrawableSize()
    }

    func configureMetalLayer() {
        let layer = metalLayer
        layer.device = MTLCreateSystemDefaultDevice()
        layer.pixelFormat = .bgra8Unorm
        layer.framebufferOnly = false
        layer.isOpaque = true
        layer.presentsWithTransaction = false
        layer.allowsNextDrawableTimeout = true
        layer.contentsGravity = .resizeAspect
        MetalHUDLayerConfigurator.apply(to: layer)
        PresentPacingLayerConfigurator.apply(to: layer)
        updateDrawableSize()
    }

    func updateDrawableSize() {
        let scale = window?.windowScene?.screen.scale ??
            window?.screen.scale ??
            max(traitCollection.displayScale, 1)
        contentScaleFactor = scale
        metalLayer.contentsScale = scale

        let width = max(1.0, bounds.width * scale)
        let height = max(1.0, bounds.height * scale)
        let size = CGSize(width: width, height: height)
        guard metalLayer.drawableSize != size else {
            return
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        metalLayer.drawableSize = size
        CATransaction.commit()
    }
}
