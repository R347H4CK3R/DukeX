import UIKit

final class StatsHUDView: UIVisualEffectView {
    private let fpsLabel = UILabel()
    private let systemLabel = UILabel()
    private let geometryLabel = UILabel()
    private let detailLabel = UILabel()
    private var displayLink: CADisplayLink?
    private var lastRefreshTimestamp: CFTimeInterval = 0

    init() {
        super.init(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
        layer.cornerRadius = 12
        layer.cornerCurve = .continuous
        layer.masksToBounds = true
        isUserInteractionEnabled = false

        let stack = UIStackView(arrangedSubviews: [fpsLabel, systemLabel, geometryLabel, detailLabel])
        stack.axis = .vertical
        stack.spacing = 3
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -10),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
        ])

        configure(label: fpsLabel, size: 13, weight: .semibold, color: .white)
        configure(label: systemLabel, size: 11, weight: .medium, color: UIColor.white.withAlphaComponent(0.86))
        configure(label: geometryLabel, size: 10, weight: .regular, color: UIColor.white.withAlphaComponent(0.72))
        configure(label: detailLabel, size: 10, weight: .regular, color: UIColor.white.withAlphaComponent(0.62))
        updateContent()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            stop()
        } else {
            start()
        }
    }

    private func configure(label: UILabel, size: CGFloat, weight: UIFont.Weight, color: UIColor) {
        label.font = UIFont.monospacedSystemFont(ofSize: size, weight: weight)
        label.textColor = color
        label.numberOfLines = 1
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    private func start() {
        guard displayLink == nil else {
            return
        }

        let displayLink = CADisplayLink(target: self, selector: #selector(refresh(_:)))
        displayLink.preferredFrameRateRange = CAFrameRateRange(minimum: 10, maximum: 30, preferred: 10)
        displayLink.add(to: .main, forMode: .common)
        self.displayLink = displayLink
    }

    private func stop() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func refresh(_ displayLink: CADisplayLink) {
        guard displayLink.timestamp - lastRefreshTimestamp >= 0.5 else {
            return
        }

        lastRefreshTimestamp = displayLink.timestamp
        updateContent()
    }

    private func updateContent() {
        let resources = AppResourceMonitor.shared.sample()
        let displayStats = XemuDisplayStatsBridge.shared.sample()

        if let displayStats {
            fpsLabel.text = String(
                format: "FPS %.1f  NV2A %u  %d ms",
                displayStats.presenterFPS,
                displayStats.nv2aFPS,
                displayStats.mspf
            )
            geometryLabel.text = String(
                format: "geom %d  ram/idx/inl %d/%d/%d",
                displayStats.geometryUpdates,
                displayStats.geometryRAMUpdates,
                displayStats.geometryIndexUpdates,
                displayStats.geometryInlineUpdates
            )
            detailLabel.text = String(
                format: "miss %llu  surf dl/up/to %d/%d/%d  pipe/shd/tex %d/%d/%d",
                displayStats.presentMissedFrames,
                displayStats.surfaceDownloads,
                displayStats.surfaceUploads,
                displayStats.surfaceToTexture,
                displayStats.pipelineGenerations,
                displayStats.shaderGenerations,
                displayStats.textureUploads
            )
        } else {
            fpsLabel.text = "FPS --  NV2A --"
            geometryLabel.text = "geom --"
            detailLabel.text = "waiting for renderer"
        }

        systemLabel.text = String(
            format: "CPU %.0f%%  RAM %@  %@",
            resources.cpuPercent,
            Self.memoryFormatter.string(fromByteCount: Int64(resources.residentMemoryBytes)),
            Self.thermalLabel(resources.thermalState)
        )
    }

    private static let memoryFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .memory
        return formatter
    }()

    private static func thermalLabel(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal:
            return "Thermal nominal"
        case .fair:
            return "Thermal fair"
        case .serious:
            return "Thermal serious"
        case .critical:
            return "Thermal critical"
        @unknown default:
            return "Thermal unknown"
        }
    }
}
