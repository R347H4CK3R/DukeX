import UIKit

final class GameplayExitOverlayView: UIView {
    private let session: NativeMetalPresenterSession
    private let onExitRequested: () -> Void
    private let onRestartRequested: () -> Void
    private let panelView = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
    private let titleLabel = UILabel()
    private let messageLabel = UILabel()
    private let restartButton = UIButton(type: .system)
    private let exitButton = UIButton(type: .system)
    private let cancelButton = UIButton(type: .system)
    private var actionHasBeenRequested = false
    private var suppressShowUntil: CFTimeInterval = 0

    init(
        session: NativeMetalPresenterSession,
        onExitRequested: @escaping () -> Void,
        onRestartRequested: @escaping () -> Void
    ) {
        self.session = session
        self.onExitRequested = onExitRequested
        self.onRestartRequested = onRestartRequested
        super.init(frame: .zero)
        configure()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc func toggle() {
        isVisible ? hide() : show()
    }

    @objc func show() {
        guard !isVisible,
              !actionHasBeenRequested,
              CACurrentMediaTime() >= suppressShowUntil else {
            return
        }

        isHidden = false
        isUserInteractionEnabled = true
        accessibilityViewIsModal = true
        UIView.animate(withDuration: 0.18, delay: 0, options: [.curveEaseOut]) {
            self.alpha = 1
        }
    }

    @objc func hide() {
        guard isVisible, !actionHasBeenRequested else {
            return
        }

        suppressShowUntil = CACurrentMediaTime() + 0.35
        UIView.animate(withDuration: 0.16, delay: 0, options: [.curveEaseIn]) {
            self.alpha = 0
        } completion: { _ in
            self.isHidden = true
            self.isUserInteractionEnabled = false
            self.accessibilityViewIsModal = false
        }
    }

    private var isVisible: Bool {
        !isHidden && alpha > 0
    }

    var isMenuVisible: Bool {
        isVisible
    }

    func refreshLayoutForGeometryChange() {
        superview?.setNeedsLayout()
        superview?.layoutIfNeeded()
        setNeedsLayout()
        layoutIfNeeded()
        panelView.setNeedsLayout()
        panelView.layoutIfNeeded()
    }

    @discardableResult
    func handleRawTouchEnded(from event: UIEvent) -> Bool {
        guard isVisible,
              let touches = event.allTouches else {
            return false
        }

        refreshLayoutForGeometryChange()
        let restartFrame = restartButton.convert(restartButton.bounds, to: self).insetBy(dx: -12, dy: -10)
        let exitFrame = exitButton.convert(exitButton.bounds, to: self).insetBy(dx: -12, dy: -10)
        let cancelFrame = cancelButton.convert(cancelButton.bounds, to: self).insetBy(dx: -12, dy: -10)
        let panelFrame = panelView.convert(panelView.bounds, to: self)

        for touch in touches where touch.phase == .ended {
            let point = touch.location(in: self)
            if restartFrame.contains(point) {
                confirmRestart()
                return true
            }
            if exitFrame.contains(point) {
                confirmExit()
                return true
            }
            if cancelFrame.contains(point) {
                hide()
                return true
            }
            if !panelFrame.contains(point) {
                hide()
                return true
            }
        }

        return false
    }

    private func configure() {
        alpha = 0
        isHidden = true
        isUserInteractionEnabled = false
        backgroundColor = UIColor.black.withAlphaComponent(0.42)

        let dismissButton = UIButton(type: .custom)
        dismissButton.translatesAutoresizingMaskIntoConstraints = false
        dismissButton.addTarget(self, action: #selector(hide), for: .touchUpInside)
        addSubview(dismissButton)

        panelView.translatesAutoresizingMaskIntoConstraints = false
        panelView.layer.cornerRadius = 22
        panelView.layer.cornerCurve = .continuous
        panelView.layer.masksToBounds = true
        addSubview(panelView)

        let stack = UIStackView(arrangedSubviews: [titleLabel, messageLabel, restartButton, exitButton, cancelButton])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        panelView.contentView.addSubview(stack)

        titleLabel.text = session.isDashboard ? "Exit Dashboard?" : "Exit Gameplay?"
        titleLabel.textColor = .white
        titleLabel.font = .preferredFont(forTextStyle: .title3).withWeight(.bold)
        titleLabel.numberOfLines = 0
        titleLabel.textAlignment = .center

        messageLabel.text = session.isDashboard ?
            "DukeX will stop the dashboard and return to the Games tab." :
            "DukeX will stop \(session.displayTitle) and return to the Games tab. Unsaved progress may be lost."
        messageLabel.textColor = UIColor.white.withAlphaComponent(0.78)
        messageLabel.font = .preferredFont(forTextStyle: .subheadline)
        messageLabel.numberOfLines = 0
        messageLabel.textAlignment = .center

        restartButton.configuration = primaryButtonConfiguration(
            title: session.isDashboard ? "Restart Dashboard" : "Restart Game",
            color: .systemGreen
        )
        restartButton.addTarget(self, action: #selector(confirmRestart), for: .touchUpInside)

        exitButton.configuration = primaryButtonConfiguration(
            title: session.isDashboard ? "Exit Dashboard" : "Exit Game",
            color: .systemRed
        )
        exitButton.addTarget(self, action: #selector(confirmExit), for: .touchUpInside)

        cancelButton.configuration = secondaryButtonConfiguration(title: "Cancel")
        cancelButton.addTarget(self, action: #selector(hide), for: .touchUpInside)

        NSLayoutConstraint.activate([
            dismissButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            dismissButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            dismissButton.topAnchor.constraint(equalTo: topAnchor),
            dismissButton.bottomAnchor.constraint(equalTo: bottomAnchor),

            panelView.centerXAnchor.constraint(equalTo: safeAreaLayoutGuide.centerXAnchor),
            panelView.centerYAnchor.constraint(equalTo: safeAreaLayoutGuide.centerYAnchor),
            panelView.widthAnchor.constraint(lessThanOrEqualTo: safeAreaLayoutGuide.widthAnchor, constant: -36),
            panelView.widthAnchor.constraint(lessThanOrEqualToConstant: 390),

            stack.leadingAnchor.constraint(equalTo: panelView.contentView.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: panelView.contentView.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: panelView.contentView.topAnchor, constant: 18),
            stack.bottomAnchor.constraint(equalTo: panelView.contentView.bottomAnchor, constant: -18),
            restartButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 48),
            exitButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 48),
            cancelButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
        ])

        accessibilityLabel = session.isDashboard ? "Exit Dashboard Menu" : "Exit Gameplay Menu"
    }

    @objc private func confirmExit() {
        guard !actionHasBeenRequested else {
            return
        }

        actionHasBeenRequested = true
        restartButton.isEnabled = false
        exitButton.isEnabled = false
        cancelButton.isEnabled = false
        titleLabel.text = "Exiting..."
        messageLabel.text = session.isDashboard ?
            "Stopping the dashboard and returning to Games." :
            "Stopping \(session.displayTitle) and returning to Games."
        exitButton.configuration = primaryButtonConfiguration(title: "Exiting", color: .systemGray)
        onExitRequested()
    }

    @objc private func confirmRestart() {
        guard !actionHasBeenRequested else {
            return
        }

        actionHasBeenRequested = true
        restartButton.isEnabled = false
        exitButton.isEnabled = false
        cancelButton.isEnabled = false
        titleLabel.text = "Restarting..."
        messageLabel.text = session.isDashboard ?
            "Stopping and relaunching the dashboard." :
            "Stopping and relaunching \(session.displayTitle)."
        restartButton.configuration = primaryButtonConfiguration(title: "Restarting", color: .systemGray)
        onRestartRequested()
    }

    private func primaryButtonConfiguration(title: String, color: UIColor) -> UIButton.Configuration {
        var configuration = UIButton.Configuration.filled()
        configuration.title = title
        configuration.baseBackgroundColor = color
        configuration.baseForegroundColor = .white
        configuration.cornerStyle = .large
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 11, leading: 16, bottom: 11, trailing: 16)
        return configuration
    }

    private func secondaryButtonConfiguration(title: String) -> UIButton.Configuration {
        var configuration = UIButton.Configuration.gray()
        configuration.title = title
        configuration.baseForegroundColor = .white
        configuration.cornerStyle = .large
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16)
        return configuration
    }
}

extension NativeMetalPresenterSession {
    var displayTitle: String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedTitle.isEmpty ? "the running game" : trimmedTitle
    }
}

private extension UIFont {
    func withWeight(_ weight: UIFont.Weight) -> UIFont {
        let traits = [UIFontDescriptor.TraitKey.weight: weight]
        let descriptor = fontDescriptor.addingAttributes([.traits: traits])
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}
