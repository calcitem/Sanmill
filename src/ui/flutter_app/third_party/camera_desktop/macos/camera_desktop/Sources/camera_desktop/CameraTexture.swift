import FlutterMacOS
import CoreVideo

/// Thread-safe FlutterTexture that delivers CVPixelBuffer frames to Flutter's renderer.
class CameraTexture: NSObject, FlutterTexture {
    private var latestBuffer: CVPixelBuffer?
    private let lock = UnfairLock()

    /// Updates the pixel buffer with a new frame from the camera.
    /// Called from the AVCaptureVideoDataOutput callback queue.
    func update(buffer: CVPixelBuffer) {
        lock.lock()
        latestBuffer = buffer
        lock.unlock()
    }

    /// Called by Flutter's rendering engine to get the latest frame.
    func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
        lock.lock()
        defer { lock.unlock() }
        guard let buffer = latestBuffer else { return nil }
        return Unmanaged.passRetained(buffer)
    }
}
