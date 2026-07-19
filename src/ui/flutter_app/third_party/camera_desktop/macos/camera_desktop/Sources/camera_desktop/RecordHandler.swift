import AVFoundation

/// Manages video recording via AVAssetWriter.
class RecordHandler: NSObject {
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var outputPath: String?
    private var sessionStarted = false
    private let lock = UnfairLock()

    private(set) var isRecording = false

    /// Starts recording to a temporary file.
    /// - Parameters:
    ///   - width: Video frame width.
    ///   - height: Video frame height.
    ///   - targetFps: Target frame rate for encoder hints.
    ///   - targetBitrate: Target average bitrate in bits per second (0 = default).
    ///   - enableAudio: Whether to record audio.
    /// - Returns: The output file path on success.
    /// - Throws: If the asset writer cannot be created.
    func startRecording(width: Int,
                        height: Int,
                        targetFps: Int,
                        targetBitrate: Int,
                        audioBitrate: Int = 0,
                        enableAudio: Bool) throws -> String {
        lock.lock()
        if isRecording {
            lock.unlock()
            throw NSError(domain: "camera_desktop", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Already recording"])
        }
        lock.unlock()

        let path = RecordHandler.generatePath()
        let url = URL(fileURLWithPath: path)

        // Remove any stale file at this path.
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            // Non-fatal: file may simply not exist yet.
            let nsError = error as NSError
            if nsError.code != NSFileNoSuchFileError {
            }
        }

        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)

        // Video input, H.264 encoding.
        var compression: [String: Any] = [
            AVVideoExpectedSourceFrameRateKey: targetFps,
            AVVideoMaxKeyFrameIntervalKey: max(targetFps, 1),
        ]
        if targetBitrate > 0 {
            compression[AVVideoAverageBitRateKey] = targetBitrate
        }

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: compression,
        ]
        let vInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        vInput.expectsMediaDataInRealTime = true
        if writer.canAdd(vInput) {
            writer.add(vInput)
        } else {
        }

        // Audio input, AAC encoding.
        var aInput: AVAssetWriterInput?
        if enableAudio {
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: audioBitrate > 0 ? audioBitrate : 128000,
            ]
            aInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            aInput!.expectsMediaDataInRealTime = true
            if writer.canAdd(aInput!) {
                writer.add(aInput!)
            } else {
            }
        }

        writer.startWriting()

        lock.lock()
        assetWriter = writer
        videoInput = vInput
        audioInput = aInput
        outputPath = path
        sessionStarted = false
        isRecording = true
        lock.unlock()

        return path
    }

    /// Appends a video sample buffer to the recording.
    func appendVideoBuffer(_ sampleBuffer: CMSampleBuffer) {
        lock.lock()
        guard isRecording else {
            lock.unlock()
            return
        }
        guard let writer = assetWriter else {
            lock.unlock()
            return
        }
        guard writer.status == .writing else {
            lock.unlock()
            return
        }
        guard let input = videoInput else {
            lock.unlock()
            return
        }
        guard input.isReadyForMoreMediaData else {
            lock.unlock()
            return
        }

        if !sessionStarted {
            let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            writer.startSession(atSourceTime: timestamp)
            sessionStarted = true
        }
        lock.unlock()

        input.append(sampleBuffer)
    }

    /// Appends an audio sample buffer to the recording.
    func appendAudioBuffer(_ sampleBuffer: CMSampleBuffer) {
        lock.lock()
        guard isRecording else {
            lock.unlock()
            return
        }
        guard let writer = assetWriter else {
            lock.unlock()
            return
        }
        guard writer.status == .writing else {
            lock.unlock()
            return
        }
        guard let input = audioInput else {
            lock.unlock()
            return
        }
        guard input.isReadyForMoreMediaData else {
            lock.unlock()
            return
        }
        guard sessionStarted else {
            lock.unlock()
            return
        }
        lock.unlock()

        input.append(sampleBuffer)
    }

    /// Stops recording and finalizes the file.
    /// - Parameter completion: Called with the output file path on success, or nil on failure.
    func stopRecording(completion: @escaping (String?) -> Void) {
        lock.lock()
        guard isRecording, let writer = assetWriter else {
            lock.unlock()
            completion(nil)
            return
        }

        isRecording = false
        let vInput = videoInput
        let aInput = audioInput
        let path = outputPath

        assetWriter = nil
        videoInput = nil
        audioInput = nil
        outputPath = nil
        sessionStarted = false
        lock.unlock()

        vInput?.markAsFinished()
        aInput?.markAsFinished()

        writer.finishWriting {
            if writer.status == .completed {
                completion(path)
            } else {
                completion(nil)
            }
        }
    }

    /// Generates a unique temporary file path for a video recording.
    static func generatePath() -> String {
        let timestamp = Int(Date().timeIntervalSince1970 * 1000)
        return NSTemporaryDirectory() + "camera_desktop_video_\(timestamp).mp4"
    }
}
