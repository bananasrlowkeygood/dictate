import AppKit
import AVFoundation

/// Hold Right ⌘ to dictate, release to paste. Double-tap for hands-free
/// (tap again to finish, Esc cancels). Hold Shift at any point to paste the
/// raw transcript instead of the polished one.
final class Dictate: NSObject, NSApplicationDelegate {
    private enum State { case idle, recording, handsFree, processing }

    private static let tapMaxDuration: TimeInterval = 0.25
    private static let doubleTapWindow: TimeInterval = 0.5
    private static let hudDelay: TimeInterval = 0.2

    private let hotkey = Hotkey()
    private let recorder = Recorder()
    private let transcriber = Transcriber()
    private let polisher = Polisher()
    private let hud = HUD()

    private var state = State.idle
    private var pressedAt: TimeInterval = 0
    private var lastTapAt: TimeInterval = -10
    private var raw = false
    private var session = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            if !granted { log("Microphone permission denied") }
        }
        recorder.onLevel = { [weak self] level in
            DispatchQueue.main.async {
                guard let self, self.state == .recording || self.state == .handsFree else { return }
                self.hud.push(level: level)
            }
        }
        wire()
        startHotkeyWhenTrusted()
        Task {
            do {
                try await transcriber.load()
                log("Model ready")
            } catch {
                log("Model failed to load: \(error.localizedDescription)")
            }
        }
    }

    private func startHotkeyWhenTrusted() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if AXIsProcessTrustedWithOptions(options), hotkey.start() {
            log("Listening for Right Command")
            return
        }
        log("Waiting for Accessibility permission")
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
            guard let self, AXIsProcessTrusted(), self.hotkey.start() else { return }
            timer.invalidate()
            log("Listening for Right Command")
        }
    }

    private func wire() {
        hotkey.onRightCommandDown = { [weak self] time in
            guard let self else { return }
            switch state {
            case .idle:
                pressedAt = time
                raw = NSEvent.modifierFlags.contains(.shift)
                startRecording()
            case .handsFree:
                finish()
            case .recording, .processing:
                break
            }
        }
        hotkey.onRightCommandUp = { [weak self] time in
            guard let self, state == .recording else { return }
            if time - pressedAt >= Self.tapMaxDuration {
                finish()
            } else if time - lastTapAt < Self.doubleTapWindow {
                lastTapAt = -10
                state = .handsFree
                hud.showListening()
            } else {
                lastTapAt = time
                cancel()
            }
        }
        hotkey.onChord = { [weak self] in
            guard let self, state == .recording else { return }
            cancel()
        }
        hotkey.onShift = { [weak self] in
            guard let self, state == .recording || state == .handsFree else { return }
            raw = true
        }
        hotkey.onEscape = { [weak self] in
            guard let self, state == .recording || state == .handsFree else { return false }
            cancel()
            return true
        }
    }

    private func startRecording() {
        state = .recording
        session += 1
        let current = session
        recorder.start()
        // Wait before showing the HUD so the first tap of a double-tap doesn't flash it.
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.hudDelay) { [weak self] in
            guard let self, session == current, state == .recording else { return }
            hud.showListening()
        }
    }

    private func cancel() {
        state = .idle
        session += 1
        recorder.stop { _ in }
        hud.hide()
    }

    private func finish() {
        state = .processing
        session += 1
        let raw = raw
        hud.showWorking()
        recorder.stop { [weak self] samples in
            guard let self else { return }
            Task {
                let started = Date()
                var transcript = ""
                do {
                    transcript = try await self.transcriber.transcribe(samples)
                } catch {
                    log("Transcription failed: \(error.localizedDescription)")
                }
                let (text, path) = transcript.isEmpty || raw
                    ? (transcript, Polisher.Path.raw)
                    : await self.polisher.polish(transcript)
                let elapsed = Int(Date().timeIntervalSince(started) * 1000)
                await MainActor.run {
                    self.hud.hide()
                    self.state = .idle
                    if text.isEmpty {
                        let pop = NSSound(named: "Pop")
                        pop?.volume = 0.25
                        pop?.play()
                    } else {
                        Paster.paste(text)
                        log("Pasted via \(raw ? "raw (Shift)" : path.rawValue) in \(elapsed) ms")
                    }
                }
            }
        }
    }
}

let app = NSApplication.shared
let delegate = Dictate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
