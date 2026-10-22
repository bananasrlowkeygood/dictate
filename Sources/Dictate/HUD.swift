import AppKit

/// Frosted pill above the Dock. Pink glowing waveform while listening,
/// teal sweep while transcribing and polishing.
final class HUD {
    private static let size = NSSize(width: 116, height: 36)
    private static let barCount = 11
    private static let barWidth: CGFloat = 4
    private static let barGap: CGFloat = 4
    private static let minBar: CGFloat = 4
    private static let maxBar: CGFloat = 20

    private let panel: NSPanel
    private var bars: [CALayer] = []
    private var levels: [CGFloat] = Array(repeating: 0, count: HUD.barCount)

    init() {
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let bounds = NSRect(origin: .zero, size: Self.size)
        let container = NSView(frame: bounds)

        let blur = NSVisualEffectView(frame: bounds)
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.maskImage = Self.pillMask(Self.size)
        container.addSubview(blur)

        // Custom layers get hidden inside an NSVisualEffectView, so they live in
        // a sibling view stacked above it.
        let barsView = NSView(frame: bounds)
        barsView.wantsLayer = true
        container.addSubview(barsView)

        let total = CGFloat(Self.barCount) * Self.barWidth + CGFloat(Self.barCount - 1) * Self.barGap
        var x = (Self.size.width - total) / 2
        for _ in 0..<Self.barCount {
            let bar = CALayer()
            bar.cornerRadius = Self.barWidth / 2
            bar.frame = CGRect(x: x, y: (Self.size.height - Self.minBar) / 2, width: Self.barWidth, height: Self.minBar)
            bar.shadowOffset = .zero
            bar.shadowRadius = 4
            barsView.layer?.addSublayer(bar)
            bars.append(bar)
            x += Self.barWidth + Self.barGap
        }
        panel.contentView = container
    }

    func showListening() {
        levels = Array(repeating: 0, count: Self.barCount)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for bar in bars {
            bar.removeAllAnimations()
            bar.backgroundColor = NSColor.systemPink.cgColor
            bar.shadowColor = NSColor.systemPink.cgColor
            bar.shadowOpacity = 0.9
            setHeight(bar, Self.minBar)
        }
        CATransaction.commit()
        show()
    }

    /// Scrolls the newest mic level in from the right.
    func push(level rms: Float) {
        levels.removeFirst()
        levels.append(min(1, CGFloat(sqrt(rms)) * 3.5))
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.08)
        for (bar, level) in zip(bars, levels) {
            setHeight(bar, Self.minBar + level * (Self.maxBar - Self.minBar))
        }
        CATransaction.commit()
    }

    func showWorking() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let now = CACurrentMediaTime()
        for (i, bar) in bars.enumerated() {
            bar.backgroundColor = NSColor.systemTeal.cgColor
            bar.shadowColor = NSColor.systemTeal.cgColor
            bar.shadowOpacity = 0.6
            setHeight(bar, Self.minBar)
            let sweep = CABasicAnimation(keyPath: "bounds.size.height")
            sweep.fromValue = Self.minBar
            sweep.toValue = Self.maxBar * 0.7
            sweep.duration = 0.35
            sweep.autoreverses = true
            sweep.repeatCount = .infinity
            sweep.beginTime = now + Double(i) * 0.07
            sweep.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            bar.add(sweep, forKey: "sweep")
        }
        CATransaction.commit()
        show()
    }

    func hide() {
        panel.orderOut(nil)
        bars.forEach { $0.removeAllAnimations() }
    }

    private func show() {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: visible.midX - Self.size.width / 2, y: visible.minY + 14))
        panel.orderFrontRegardless()
    }

    private func setHeight(_ bar: CALayer, _ height: CGFloat) {
        bar.bounds.size.height = height
        bar.position.y = Self.size.height / 2
    }

    private static func pillMask(_ size: NSSize) -> NSImage {
        let radius = size.height / 2
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}
