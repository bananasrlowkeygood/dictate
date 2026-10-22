import FluidAudio

/// Parakeet TDT v2 (English), cached at
/// ~/Library/Application Support/FluidAudio/Models/parakeet-tdt-0.6b-v2.
actor Transcriber {
    private var manager: AsrManager?

    func load() async throws {
        let models = try await AsrModels.downloadAndLoad(version: .v2)
        let manager = AsrManager(config: .default)
        try await manager.loadModels(models)
        self.manager = manager
    }

    /// Returns "" if the model isn't loaded yet or nothing was said.
    func transcribe(_ samples: [Float]) async throws -> String {
        guard let manager else { return "" }
        var padded = samples
        // Parakeet misbehaves on clips under 1 s.
        if padded.count < 16000 {
            padded += [Float](repeating: 0, count: 16000 - padded.count)
        }
        var state = try TdtDecoderState(decoderLayers: await manager.decoderLayerCount)
        let result = try await manager.transcribe(padded, decoderState: &state)
        return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
