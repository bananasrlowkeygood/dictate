import AVFoundation
import Darwin

/// The Siri Remote's microphone, read from the remote-mic helper (bananasrlowkeygood/remote). The helper streams the
/// remote's Opus frames (CELT wideband, 20 ms) over a Unix socket for as long as we stay connected; they're decoded
/// here to 16 kHz mono floats, the same as `Recorder`.
final class RemoteMic {
    var onLevel: ((Float) -> Void)?

    private static let socketPath = "/var/run/com.ravibandaru.remote-mic.sock"
    private let lock = NSLock()
    private var fd: Int32 = -1
    private var samples: [Float] = []
    private var frames = 0

    /// Connects and starts buffering. Returns false if the helper isn't running.
    func start() -> Bool {
        stop { _ in }
        let s = socket(AF_UNIX, SOCK_STREAM, 0)
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            Self.socketPath.utf8CString.withUnsafeBytes { raw.copyMemory(from: $0) }
        }
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(s, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard connected == 0 else { close(s); return false }
        lock.lock(); fd = s; samples.removeAll(keepingCapacity: true); frames = 0; lock.unlock()
        Thread.detachNewThread { [weak self] in self?.read(from: s) }
        return true
    }

    /// Disconnects (which stops the helper's capture) and hands back what was heard.
    func stop(completion: @escaping ([Float]) -> Void) {
        lock.lock()
        let s = fd, out = samples, count = frames
        fd = -1
        lock.unlock()
        if s >= 0 {
            shutdown(s, SHUT_RDWR)
            log("Remote mic: \(count) frames")
        }
        completion(out)
    }

    private func read(from s: Int32) {
        var asbd = AudioStreamBasicDescription(mSampleRate: 48000, mFormatID: kAudioFormatOpus, mFormatFlags: 0,
            mBytesPerPacket: 0, mFramesPerPacket: 960, mBytesPerFrame: 0, mChannelsPerFrame: 1, mBitsPerChannel: 0, mReserved: 0)
        let opus = AVAudioFormat(streamDescription: &asbd)!
        let pcm = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48000, channels: 1, interleaved: false)!
        let decoder = AVAudioConverter(from: opus, to: pcm)!
        defer { close(s) }

        while let frame = readFrame(s) {
            let packet = AVAudioCompressedBuffer(format: opus, packetCapacity: 1, maximumPacketSize: frame.count)
            frame.withUnsafeBytes { packet.data.copyMemory(from: $0.baseAddress!, byteCount: frame.count) }
            packet.byteLength = UInt32(frame.count)
            packet.packetCount = 1
            packet.packetDescriptions![0] = AudioStreamPacketDescription(
                mStartOffset: 0, mVariableFramesInPacket: 0, mDataByteSize: UInt32(frame.count))
            let out = AVAudioPCMBuffer(pcmFormat: pcm, frameCapacity: 960)!
            var fed = false
            var error: NSError?
            decoder.convert(to: out, error: &error) { _, status in
                if fed { status.pointee = .noDataNow; return nil }
                fed = true
                status.pointee = .haveData
                return packet
            }
            guard error == nil, let data = out.floatChannelData, out.frameLength > 0 else { continue }
            // The remote sends wideband speech (nothing above 8 kHz), so every third sample is a clean 16 kHz signal.
            let chunk = stride(from: 0, to: Int(out.frameLength), by: 3).map { data[0][$0] }
            let rms = sqrt(chunk.reduce(0) { $0 + $1 * $1 } / Float(chunk.count))
            lock.lock()
            let live = fd == s
            if live { samples.append(contentsOf: chunk); frames += 1 }
            lock.unlock()
            guard live else { return }
            onLevel?(rms)
        }
    }

    /// One frame: a 2-byte big-endian length, then the Opus bytes. Nil when the connection ends.
    private func readFrame(_ s: Int32) -> [UInt8]? {
        guard let header = readExactly(s, 2) else { return nil }
        let length = Int(header[0]) << 8 | Int(header[1])
        guard length > 0 else { return nil }
        return readExactly(s, length)
    }

    private func readExactly(_ s: Int32, _ count: Int) -> [UInt8]? {
        var buffer = [UInt8](repeating: 0, count: count)
        var got = 0
        while got < count {
            let n = buffer.withUnsafeMutableBytes { Darwin.read(s, $0.baseAddress! + got, count - got) }
            if n <= 0 { return nil }
            got += n
        }
        return buffer
    }
}
