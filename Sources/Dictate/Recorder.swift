import AVFoundation

/// Captures the mic as 16 kHz mono floats. AVAudioEngine work stays on its own
/// queue: blocking the main thread here breaks double-tap timing.
final class Recorder {
    var onLevel: ((Float) -> Void)?

    private let engine = AVAudioEngine()
    private let queue = DispatchQueue(label: "dictate.audio")
    private let lock = NSLock()
    private let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
    private var converter: AVAudioConverter?
    private var samples: [Float] = []

    func start() {
        queue.async { [self] in
            lock.lock(); samples.removeAll(keepingCapacity: true); lock.unlock()
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            converter = AVAudioConverter(from: format, to: target)
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                self?.append(buffer)
            }
            do {
                engine.prepare()
                try engine.start()
            } catch {
                log("Audio engine failed: \(error.localizedDescription)")
            }
        }
    }

    func stop(completion: @escaping ([Float]) -> Void) {
        queue.async { [self] in
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            lock.lock(); let out = samples; lock.unlock()
            completion(out)
        }
    }

    private func append(_ buffer: AVAudioPCMBuffer) {
        guard let converter else { return }
        let ratio = target.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16
        guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
        var fed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if fed {
                status.pointee = .noDataNow
                return nil
            }
            fed = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, let data = out.floatChannelData, out.frameLength > 0 else { return }
        let chunk = Array(UnsafeBufferPointer(start: data[0], count: Int(out.frameLength)))
        let rms = sqrt(chunk.reduce(0) { $0 + $1 * $1 } / Float(chunk.count))
        lock.lock(); samples.append(contentsOf: chunk); lock.unlock()
        onLevel?(rms)
    }
}
