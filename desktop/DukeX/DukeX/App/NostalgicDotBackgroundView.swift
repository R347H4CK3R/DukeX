import CoreMotion
import SwiftUI

struct NostalgicDotBackgroundView: View {
    @Environment(\.dukeXTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var tiltObserver = BackgroundTiltObserver()

    private let parallaxInset: CGFloat = 36

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                baseLayer

                Canvas { context, size in
                    drawDots(in: size, context: &context)
                }
                .opacity(colorScheme == .dark ? 0.55 : 0.85)

                radialGlow
            }
            .frame(
                width: geometry.size.width + parallaxInset * 2,
                height: geometry.size.height + parallaxInset * 2
            )
            .offset(tiltObserver.offset)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            .clipped()
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .onAppear {
            tiltObserver.start()
        }
        .onDisappear {
            tiltObserver.stop()
        }
    }

    private var baseLayer: some View {
        LinearGradient(
            colors: theme.animatedBackgroundColors(for: colorScheme),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var radialGlow: some View {
        let glowColors = theme.animatedGlowColors(for: colorScheme)

        return ZStack {
            RadialGradient(
                colors: [
                    glowColors.accent,
                    Color.clear
                ],
                center: .bottomTrailing,
                startRadius: 0,
                endRadius: 360
            )

            RadialGradient(
                colors: [
                    glowColors.bottom,
                    Color.clear
                ],
                center: .bottom,
                startRadius: 80,
                endRadius: 760
            )
        }
        .blendMode(.screen)
    }

    private func drawDots(in size: CGSize, context: inout GraphicsContext) {
        let step: CGFloat = colorScheme == .dark ? 20 : 21
        let diameter: CGFloat = colorScheme == .dark ? 1.9 : 2.3
        let offset = step / 2
        let rows = Int(ceil(size.height / step)) + 2
        let columns = Int(ceil(size.width / step)) + 2
        let dotColor = theme.animatedDotColor(for: colorScheme)
        let accentColor = theme.animatedAccentDotColor(for: colorScheme)

        for row in 0..<rows {
            let y = CGFloat(row) * step - step
            let rowOffset = row.isMultiple(of: 2) ? 0 : offset

            for column in 0..<columns {
                let x = CGFloat(column) * step + rowOffset - step
                let rect = CGRect(x: x, y: y, width: diameter, height: diameter)

                context.fill(Path(ellipseIn: rect), with: .color(dotColor))

                if row.isMultiple(of: 4) && column.isMultiple(of: 5) {
                    context.fill(
                        Path(ellipseIn: rect.insetBy(dx: -0.6, dy: -0.6)),
                        with: .color(accentColor)
                    )
                }
            }
        }

        if colorScheme == .light {
            drawSecondaryLightDots(in: size, context: &context)
        }
    }

    private func drawSecondaryLightDots(in size: CGSize, context: inout GraphicsContext) {
        let step: CGFloat = 21
        let diameter: CGFloat = 1.15
        let offset = step / 2
        let rows = Int(ceil(size.height / step)) + 2
        let columns = Int(ceil(size.width / step)) + 2
        let dotColor = theme.animatedSecondaryDotColor(for: colorScheme)

        for row in 0..<rows {
            let y = CGFloat(row) * step - step
            let rowOffset = row.isMultiple(of: 2) ? offset * 0.5 : 0

            for column in 0..<columns {
                let x = CGFloat(column) * step + rowOffset - step
                let rect = CGRect(x: x, y: y, width: diameter, height: diameter)
                context.fill(Path(ellipseIn: rect), with: .color(dotColor))
            }
        }
    }
}

private final class BackgroundTiltObserver: ObservableObject {
    @Published var offset = CGSize.zero

    private let motionManager = CMMotionManager()
    private let maximumOffset: CGFloat = 26
    private let smoothing: CGFloat = 0.18

    func start() {
        guard motionManager.isDeviceMotionAvailable else {
            return
        }

        motionManager.deviceMotionUpdateInterval = 1.0 / 30.0
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let gravity = motion?.gravity else {
                return
            }

            let target = CGSize(
                width: self.clamped(CGFloat(gravity.x), -0.9, 0.9) * self.maximumOffset,
                height: self.clamped(CGFloat(-gravity.y), -0.9, 0.9) * self.maximumOffset
            )

            self.offset = CGSize(
                width: self.offset.width + (target.width - self.offset.width) * self.smoothing,
                height: self.offset.height + (target.height - self.offset.height) * self.smoothing
            )
        }
    }

    func stop() {
        motionManager.stopDeviceMotionUpdates()
    }

    deinit {
        motionManager.stopDeviceMotionUpdates()
    }

    private func clamped(_ value: CGFloat, _ lowerBound: CGFloat, _ upperBound: CGFloat) -> CGFloat {
        min(max(value, lowerBound), upperBound)
    }
}
