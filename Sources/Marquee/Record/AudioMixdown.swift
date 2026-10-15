import AVFoundation

/// Recordings with both desktop audio and a microphone are written with two audio tracks.
/// Many players (browsers, Slack, social sites) only play the first track, so after
/// recording the two are mixed into one. Video is copied as-is, without re-encoding.
enum AudioMixdown {
    enum MixError: Error { case cannotRead, cannotWrite, failed }

    /// Replaces the file at `url` with a version that has a single mixed audio track.
    /// Does nothing if the file has fewer than two audio tracks.
    static func mixAudioTracks(at url: URL) async throws {
        let asset = AVURLAsset(url: url)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard audioTracks.count > 1,
              let videoTrack = try await asset.loadTracks(withMediaType: .video).first else { return }
        let formatHint = try await videoTrack.load(.formatDescriptions).first

        let reader = try AVAssetReader(asset: asset)
        let videoOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: nil)
        let audioOutput = AVAssetReaderAudioMixOutput(audioTracks: audioTracks, audioSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsBigEndianKey: false,
        ])
        guard reader.canAdd(videoOutput), reader.canAdd(audioOutput) else { throw MixError.cannotRead }
        reader.add(videoOutput)
        reader.add(audioOutput)

        let mixedURL = url.deletingLastPathComponent()
            .appendingPathComponent("mixed-\(UUID().uuidString).mp4")
        let writer = try AVAssetWriter(outputURL: mixedURL, fileType: .mp4)
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: formatHint)
        let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 192_000,
        ])
        guard writer.canAdd(videoInput), writer.canAdd(audioInput) else { throw MixError.cannotWrite }
        writer.add(videoInput)
        writer.add(audioInput)

        guard reader.startReading() else { throw reader.error ?? MixError.cannotRead }
        guard writer.startWriting() else { throw writer.error ?? MixError.cannotWrite }
        writer.startSession(atSourceTime: .zero)

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let group = DispatchGroup()
            Pump(input: videoInput, output: videoOutput, group: group).start(label: "Marquee.mix.video")
            Pump(input: audioInput, output: audioOutput, group: group).start(label: "Marquee.mix.audio")
            group.notify(queue: .global()) { continuation.resume() }
        }

        if reader.status == .failed {
            writer.cancelWriting()
            throw reader.error ?? MixError.failed
        }
        await writer.finishWriting()
        guard writer.status == .completed else {
            try? FileManager.default.removeItem(at: mixedURL)
            throw writer.error ?? MixError.failed
        }
        _ = try FileManager.default.replaceItemAt(url, withItemAt: mixedURL)
    }

    /// Copies samples from a reader output to a writer input until the output runs dry.
    private final class Pump: @unchecked Sendable {
        private let input: AVAssetWriterInput
        private let output: AVAssetReaderOutput
        private let group: DispatchGroup
        private var finished = false

        init(input: AVAssetWriterInput, output: AVAssetReaderOutput, group: DispatchGroup) {
            self.input = input
            self.output = output
            self.group = group
        }

        func start(label: String) {
            group.enter()
            let queue = DispatchQueue(label: label)
            input.requestMediaDataWhenReady(on: queue) { [self] in
                guard !finished else { return }
                while input.isReadyForMoreMediaData {
                    guard let buffer = output.copyNextSampleBuffer(), input.append(buffer) else {
                        finished = true
                        input.markAsFinished()
                        group.leave()
                        return
                    }
                }
            }
        }
    }
}
