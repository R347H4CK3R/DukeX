import UIKit

final class GameplayExitOverlayView: UIView {
    private let session: NativeMetalPresenterSession
    private let onExitRequested: () -> Void
    private let onRestartRequested: () -> Bool
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
        onRestartRequested: @escaping () -> Bool
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
        backgroundColor = UIColor.black.withAlphaComponent(0.36)

        let dismissButton = UIButton(type: .custom)
        dismissButton.translatesAutoresizingMaskIntoConstraints = false
        dismissButton.addTarget(self, action: #selector(hide), for: .touchUpInside)
        addSubview(dismissButton)

        panelView.translatesAutoresizingMaskIntoConstraints = false
        panelView.layer.cornerRadius = 18
        panelView.layer.cornerCurve = .continuous
        panelView.layer.masksToBounds = true
        addSubview(panelView)

        let actionStack = UIStackView(arrangedSubviews: [restartButton, exitButton])
        actionStack.axis = .horizontal
        actionStack.alignment = .fill
        actionStack.distribution = .fillEqually
        actionStack.spacing = 8

        let stack = UIStackView(arrangedSubviews: [titleLabel, messageLabel, actionStack, cancelButton])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 8
        stack.setCustomSpacing(12, after: messageLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        panelView.contentView.addSubview(stack)

        titleLabel.text = session.isDashboard ? "Exit Dashboard?" : "Exit Gameplay?"
        titleLabel.textColor = .white
        titleLabel.font = .preferredFont(forTextStyle: .headline).withWeight(.bold)
        titleLabel.numberOfLines = 0
        titleLabel.textAlignment = .center

        messageLabel.text = session.isDashboard ?
            "DukeX will stop the dashboard and return to the Games tab." :
            "DukeX will stop \(session.displayTitle) and return to the Games tab. Unsaved progress may be lost."
        messageLabel.textColor = UIColor.white.withAlphaComponent(0.78)
        messageLabel.font = .preferredFont(forTextStyle: .footnote)
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
            panelView.widthAnchor.constraint(lessThanOrEqualTo: safeAreaLayoutGuide.widthAnchor, constant: -42),
            panelView.widthAnchor.constraint(lessThanOrEqualToConstant: 340),

            stack.leadingAnchor.constraint(equalTo: panelView.contentView.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: panelView.contentView.trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: panelView.contentView.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: panelView.contentView.bottomAnchor, constant: -14),
            restartButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 38),
            exitButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 38),
            cancelButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 36),
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
            "Restarting the dashboard." :
            "Restarting \(session.displayTitle)."
        restartButton.configuration = primaryButtonConfiguration(title: "Restarting", color: .systemGray)
        guard onRestartRequested() else {
            showRestartUnavailable()
            return
        }

        finishRestartRequest()
    }

    private func finishRestartRequest() {
        suppressShowUntil = CACurrentMediaTime() + 0.35
        layer.removeAllAnimations()
        panelView.layer.removeAllAnimations()
        alpha = 0
        isHidden = true
        isUserInteractionEnabled = false
        accessibilityViewIsModal = false
        restoreDefaultState()
    }

    private func showRestartUnavailable() {
        actionHasBeenRequested = false
        restartButton.isEnabled = true
        exitButton.isEnabled = true
        cancelButton.isEnabled = true
        titleLabel.text = "Restart Unavailable"
        messageLabel.text = "DukeX could not restart this session without leaving gameplay."
        restartButton.configuration = primaryButtonConfiguration(
            title: session.isDashboard ? "Restart Dashboard" : "Restart Game",
            color: .systemGreen
        )
    }

    private func restoreDefaultState() {
        actionHasBeenRequested = false
        restartButton.isEnabled = true
        exitButton.isEnabled = true
        cancelButton.isEnabled = true
        titleLabel.text = session.isDashboard ? "Exit Dashboard?" : "Exit Gameplay?"
        messageLabel.text = session.isDashboard ?
            "DukeX will stop the dashboard and return to the Games tab." :
            "DukeX will stop \(session.displayTitle) and return to the Games tab. Unsaved progress may be lost."
        restartButton.configuration = primaryButtonConfiguration(
            title: session.isDashboard ? "Restart Dashboard" : "Restart Game",
            color: .systemGreen
        )
        exitButton.configuration = primaryButtonConfiguration(
            title: session.isDashboard ? "Exit Dashboard" : "Exit Game",
            color: .systemRed
        )
    }

    private func primaryButtonConfiguration(title: String, color: UIColor) -> UIButton.Configuration {
        var configuration = UIButton.Configuration.filled()
        configuration.attributedTitle = AttributedString(title, attributes: buttonTitleAttributes())
        configuration.baseBackgroundColor = color
        configuration.baseForegroundColor = .white
        configuration.cornerStyle = .medium
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 7, leading: 10, bottom: 7, trailing: 10)
        return configuration
    }

    private func secondaryButtonConfiguration(title: String) -> UIButton.Configuration {
        var configuration = UIButton.Configuration.gray()
        configuration.attributedTitle = AttributedString(title, attributes: buttonTitleAttributes())
        configuration.baseForegroundColor = .white
        configuration.cornerStyle = .medium
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10)
        return configuration
    }

    private func buttonTitleAttributes() -> AttributeContainer {
        var attributes = AttributeContainer()
        attributes.font = UIFont.preferredFont(forTextStyle: .subheadline).withWeight(.semibold)
        return attributes
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
