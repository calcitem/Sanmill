import AVFoundation

extension AVCaptureDevice {
    /// Returns all capture devices matching the given media type.
    /// Uses DiscoverySession on macOS 10.15+.
    static func captureDevices(mediaType: AVMediaType) -> [AVCaptureDevice] {
        let deviceTypes: [AVCaptureDevice.DeviceType]
        if mediaType == .video {
            if #available(macOS 14.0, *) {
                deviceTypes = [.builtInWideAngleCamera, .external]
            } else {
                deviceTypes = [.builtInWideAngleCamera, .externalUnknown]
            }
        } else {
            if #available(macOS 14.0, *) {
                deviceTypes = [.microphone]
            } else {
                deviceTypes = [.builtInMicrophone]
            }
        }

        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: deviceTypes,
            mediaType: mediaType,
            position: .unspecified
        )
        return session.devices
    }
}
