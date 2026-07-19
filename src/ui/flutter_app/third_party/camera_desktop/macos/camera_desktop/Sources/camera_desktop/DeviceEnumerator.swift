import AVFoundation

struct DeviceInfo {
    let deviceId: String
    let name: String
    let lensDirection: Int   // 0=front, 1=back, 2=external
    let sensorOrientation: Int
}

class DeviceEnumerator {
    /// Enumerates available video capture devices.
    static func enumerateDevices() -> [DeviceInfo] {
        let devices = AVCaptureDevice.captureDevices(mediaType: .video)
        let infos = devices.map { device -> (AVCaptureDevice, DeviceInfo) in
            let lensDirection: Int
            switch device.position {
            case .front:
                lensDirection = 0
            case .back:
                lensDirection = 1
            default:
                lensDirection = 2
            }
            let displayName = "\(device.localizedName) (\(device.uniqueID))"
            let info = DeviceInfo(
                deviceId: device.uniqueID,
                name: displayName,
                lensDirection: lensDirection,
                sensorOrientation: 0
            )
            return (device, info)
        }

        // Sort: built-in cameras first, Continuity Camera last.
        let sorted = infos.sorted { a, b in
            let aScore = DeviceEnumerator.sortScore(for: a.0)
            let bScore = DeviceEnumerator.sortScore(for: b.0)
            return aScore < bScore
        }

        return sorted.map { $0.1 }
    }

    /// Returns a sort score for camera ordering.
    /// Lower = higher priority (appears first in the list).
    ///   0 = built-in camera (preferred)
    ///   1 = other/external camera
    ///   2 = Continuity Camera (least preferred, often causes grey frames)
    private static func sortScore(for device: AVCaptureDevice) -> Int {
        // macOS 14+: AVCaptureDevice.DeviceType.continuityCamera is available
        if #available(macOS 14.0, *) {
            if device.deviceType == .continuityCamera {
                return 2
            }
        }

        // Fallback heuristic for pre-macOS 14 or unrecognized Continuity devices
        let modelId = device.modelID.lowercased()
        let name = device.localizedName.lowercased()
        if modelId.contains("iphone") || modelId.contains("ipad") ||
           name.contains("iphone") || name.contains("continuity") {
            return 2
        }

        // Built-in cameras have position .front or .back
        if device.position == .front || device.position == .back {
            return 0
        }

        // External cameras
        return 1
    }

    /// Extracts the device ID from a camera name in the format "Friendly Name (deviceId)".
    static func extractDeviceId(from cameraName: String) -> String? {
        guard let parenStart = cameraName.lastIndex(of: "("),
              let parenEnd = cameraName.lastIndex(of: ")"),
              parenEnd > parenStart else {
            return nil
        }
        let startIdx = cameraName.index(after: parenStart)
        return String(cameraName[startIdx..<parenEnd])
    }

    /// Maps a resolution preset integer to an AVCaptureSession.Preset.
    static func sessionPreset(for preset: Int) -> AVCaptureSession.Preset {
        switch preset {
        case 0: return .low
        case 1: return .medium
        case 2: return .high
        case 3: return .hd1280x720
        case 4, 5: return .hd1920x1080
        default: return .high
        }
    }

    /// Gets the actual output dimensions for a device with a given session preset.
    static func outputDimensions(for device: AVCaptureDevice,
                                  preset: AVCaptureSession.Preset) -> (width: Int, height: Int) {
        let format = device.activeFormat
        let desc = format.formatDescription
        let dims = CMVideoFormatDescriptionGetDimensions(desc)
        if dims.width > 0 && dims.height > 0 {
            return (Int(dims.width), Int(dims.height))
        }
        // Fallback based on preset
        switch preset {
        case .low: return (320, 240)
        case .medium: return (480, 360)
        case .hd1280x720: return (1280, 720)
        case .hd1920x1080: return (1920, 1080)
        default: return (1280, 720)
        }
    }
}
