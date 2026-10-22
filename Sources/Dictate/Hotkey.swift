import AppKit

/// Watches Right ⌘ through a session event tap (needs Accessibility).
/// Callbacks run on the main thread with NSEvent timestamps.
final class Hotkey {
    var onRightCommandDown: ((TimeInterval) -> Void)?
    var onRightCommandUp: ((TimeInterval) -> Void)?
    /// Another key pressed while Right ⌘ is held: the user wants a normal shortcut.
    var onChord: (() -> Void)?
    var onShift: (() -> Void)?
    /// Return true to swallow Esc.
    var onEscape: (() -> Bool)?

    private static let rightCommandKey: Int64 = 54
    private static let escapeKey: Int64 = 53
    private static let rightCommandMask: UInt64 = 0x10 // NX_DEVICERCMDKEYMASK

    private var tap: CFMachPort?
    private var rightCommandHeld = false

    func start() -> Bool {
        let mask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, refcon in
                let hotkey = Unmanaged<Hotkey>.fromOpaque(refcon!).takeUnretainedValue()
                return hotkey.handle(type, event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        self.tap = tap
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }

        case .flagsChanged:
            let key = event.getIntegerValueField(.keyboardEventKeycode)
            let time = NSEvent(cgEvent: event)?.timestamp ?? ProcessInfo.processInfo.systemUptime
            if key == Self.rightCommandKey {
                let held = event.flags.rawValue & Self.rightCommandMask != 0
                if held != rightCommandHeld {
                    rightCommandHeld = held
                    held ? onRightCommandDown?(time) : onRightCommandUp?(time)
                }
            } else if event.flags.contains(.maskShift) {
                onShift?()
            }

        case .keyDown:
            if rightCommandHeld { onChord?() }
            if event.getIntegerValueField(.keyboardEventKeycode) == Self.escapeKey, onEscape?() == true {
                return nil
            }

        default:
            break
        }
        return Unmanaged.passUnretained(event)
    }
}
