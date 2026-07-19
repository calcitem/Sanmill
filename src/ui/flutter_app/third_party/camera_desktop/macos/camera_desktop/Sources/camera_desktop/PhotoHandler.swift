import AVFoundation
import CoreImage

/// Captures a still image from a CVPixelBuffer and writes it to a JPEG file.
class PhotoHandler {
    private static let ciContext = CIContext()

    /// Takes a picture from the given pixel buffer and writes a JPEG to the output path.
    /// Returns true on success, false on failure.
    static func takePicture(from buffer: CVPixelBuffer, outputPath: String) -> Bool {
        let ciImage = CIImage(cvPixelBuffer: buffer)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let jpegData = ciContext.jpegRepresentation(
            of: ciImage,
            colorSpace: colorSpace,
            options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.9]
        ) else {
            return false
        }
        let url = URL(fileURLWithPath: outputPath)
        do {
            try jpegData.write(to: url)
            return true
        } catch {
            return false
        }
    }

    /// Generates a unique temporary file path for a captured image.
    static func generatePath(cameraId: Int) -> String {
        let timestamp = Int(Date().timeIntervalSince1970 * 1000)
        return NSTemporaryDirectory() + "camera_desktop_\(cameraId)_\(timestamp).jpg"
    }
}
