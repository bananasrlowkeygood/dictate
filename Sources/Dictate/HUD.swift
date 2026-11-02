import AppKit

/// Frosted pill above the Dock with soft purple light drifting inside it. While listening the light
/// swells and brightens with your voice; while transcribing and polishing it turns lavender and breathes.
final class HUD {
    private static let size = NSSize(width: 116, height: 36)

    /// One orb of light: its colours, how strongly it follows the voice, and its drift.
    private struct Orb {
        let listening: UInt32
        let working: UInt32
        let gain: CGFloat
        let diameter: CGFloat
        let home: CGFloat        // centre of its drift, as a fraction of the pill's width
        let reach: CGFloat       // horizontal drift radius in points
        let period: Double       // seconds per loop
    }

    private static let orbs: [Orb] = [
        Orb(listening: 0x7C3AED, working: 0x8B5CF6, gain: 1.0, diameter: 54, home: 0.30, reach: 22, period: 4.2),
        Orb(listening: 0xC026D3, working: 0xC084FC, gain: 0.7, diameter: 46, home: 0.66, reach: 26, period: 5.6),
        Orb(listening: 0xA855F7, working: 0xA78BFA, gain: 1.2, diameter: 50, home: 0.48, reach: 30, period: 3.6),
        Orb(listening: 0x6366F1, working: 0x818CF8, gain: 0.85, diameter: 42, home: 0.78, reach: 18, period: 6.4),
    ]

    private static let quietScale: CGFloat = 0.55
    private static let quietOpacity: Float = 0.6

    private let panel: NSPanel
    private let field = CALayer()
    private var lights: [CAGradientLayer] = []
    private var level: CGFloat = 0

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
        let lightView = NSView(frame: bounds)
        lightView.wantsLayer = true
        container.addSubview(lightView)

        field.frame = bounds
        field.cornerRadius = Self.size.height / 2
        field.masksToBounds = true
        lightView.layer?.addSublayer(field)

        for orb in Self.orbs {
            let light = CAGradientLayer()
            light.type = .radial
            light.startPoint = CGPoint(x: 0.5, y: 0.5)
            light.endPoint = CGPoint(x: 1, y: 1)
            light.locations = [0, 0.45, 1]
            light.bounds = CGRect(x: 0, y: 0, width: orb.diameter, height: orb.diameter)
            light.position = CGPoint(x: Self.size.width * orb.home, y: Self.size.height / 2)
            field.addSublayer(light)
            lights.append(light)
        }
        panel.contentView = container
    }

    func showListening() {
        level = 0
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        setDriftSpeed(1)
        for (i, (light, orb)) in zip(lights, Self.orbs).enumerated() {
            light.removeAnimation(forKey: "breathe")
            light.colors = Self.glow(orb.listening)
            light.transform = Self.scale(Self.quietScale)
            light.opacity = Self.quietOpacity
            // Hands-free mode calls this again mid-recording; keep the drift going instead of restarting it.
            if light.animation(forKey: "drift") == nil {
                light.add(Self.drift(orb, index: i), forKey: "drift")
            }
        }
        CATransaction.commit()
        show()
    }

    /// Swells and brightens the light with the mic level; rises quickly, fades gently.
    func push(level rms: Float) {
        level = max(min(1, CGFloat(sqrt(rms)) * 3.5), level * 0.85)
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.12)
        for (light, orb) in zip(lights, Self.orbs) {
            let l = min(1, level * orb.gain)
            light.transform = Self.scale(Self.quietScale + 0.75 * l)
            light.opacity = Self.quietOpacity + 0.4 * Float(l)
        }
        CATransaction.commit()
    }

    func showWorking() {
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.4)
        setDriftSpeed(2.2)
        let now = field.convertTime(CACurrentMediaTime(), from: nil)
        for (i, (light, orb)) in zip(lights, Self.orbs).enumerated() {
            light.colors = Self.glow(orb.working)
            light.transform = Self.scale(0.8)
            light.opacity = 0.8
            let breathe = CABasicAnimation(keyPath: "transform.scale")
            breathe.fromValue = 0.6
            breathe.toValue = 1.0
            breathe.duration = 1.6          // ×2.2 drift speed ≈ 0.7 s
            breathe.autoreverses = true
            breathe.repeatCount = .infinity
            breathe.beginTime = now + Double(i) * 0.4
            breathe.fillMode = .backwards
            breathe.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            light.add(breathe, forKey: "breathe")
        }
        CATransaction.commit()
        show()
    }

    func hide() {
        panel.orderOut(nil)
        lights.forEach { $0.removeAllAnimations() }
    }

    private func show() {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: visible.midX - Self.size.width / 2, y: visible.minY + 14))
        panel.orderFrontRegardless()
    }

    /// Changes how fast everything inside the pill moves without making the orbs jump.
    private func setDriftSpeed(_ speed: Float) {
        guard field.speed != speed else { return }
        let now = CACurrentMediaTime()
        field.timeOffset = field.convertTime(now, from: nil)
        field.beginTime = now
        field.speed = speed
    }

    /// A slow elliptical loop around the orb's home; neighbours circle in opposite directions.
    private static func drift(_ orb: Orb, index: Int) -> CAKeyframeAnimation {
        let path = CGMutablePath()
        let loop = CGAffineTransform(translationX: size.width * orb.home, y: size.height / 2)
            .scaledBy(x: orb.reach, y: 7)
        path.addArc(center: .zero, radius: 1, startAngle: 0, endAngle: 2 * .pi, clockwise: index % 2 == 0, transform: loop)
        let drift = CAKeyframeAnimation(keyPath: "position")
        drift.path = path
        drift.duration = orb.period
        drift.repeatCount = .infinity
        drift.calculationMode = .paced
        drift.timeOffset = orb.period * Double(index) / Double(orbs.count)
        return drift
    }

    private static func glow(_ hex: UInt32) -> [CGColor] {
        let color = NSColor(srgbRed: CGFloat(hex >> 16 & 255) / 255, green: CGFloat(hex >> 8 & 255) / 255,
                            blue: CGFloat(hex & 255) / 255, alpha: 1)
        return [color.withAlphaComponent(0.95).cgColor, color.withAlphaComponent(0.35).cgColor, color.withAlphaComponent(0).cgColor]
    }

    private static func scale(_ s: CGFloat) -> CATransform3D { CATransform3DMakeScale(s, s, 1) }

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
