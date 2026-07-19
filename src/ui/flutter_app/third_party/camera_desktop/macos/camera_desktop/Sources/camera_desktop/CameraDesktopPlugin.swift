import FlutterMacOS
import AVFoundation

/// Flutter plugin entry point for camera_desktop on macOS.
///
/// Routes MethodChannel calls to the appropriate CameraSession instance.
/// Speaks the exact same protocol as the Linux native side so the shared
/// Dart CameraDesktopPlugin class works on both platforms.
public class CameraDesktopPlugin: NSObject, FlutterPlugin, NSApplicationDelegate {
    private var sessions: [Int: CameraSession] = [:]
    private let sessionsLock = UnfairLock()
    private var nextCameraId = 1
    private let textureRegistry: FlutterTextureRegistry
    private let methodChannel: FlutterMethodChannel

    init(textureRegistry: FlutterTextureRegistry, methodChannel: FlutterMethodChannel) {
        self.textureRegistry = textureRegistry
        self.methodChannel = methodChannel
        super.init()
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "plugins.flutter.io/camera_desktop",
            binaryMessenger: registrar.messenger
        )
        let instance = CameraDesktopPlugin(
            textureRegistry: registrar.textures,
            methodChannel: channel
        )
        registrar.addMethodCallDelegate(instance, channel: channel)
        registrar.addApplicationDelegate(instance)
    }

    deinit {
        disposeAllSessions()
    }

    /// Called by the Flutter engine when it is being detached/destroyed.
    ///
    /// Note: on macOS this does NOT reliably fire during hot restart, but it
    /// may fire during other teardown paths. Kept as defense-in-depth.
    public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
        disposeAllSessions()
    }

    /// Called by NSApplication on normal app termination.
    public func applicationWillTerminate(_ notification: Notification) {
        disposeAllSessions()
    }

    private func disposeAllSessions() {
        sessionsLock.lock()
        let snapshot = sessions
        sessions.removeAll()
        sessionsLock.unlock()

        for (cameraId, session) in snapshot {
            ImageStreamHandleBridge.releaseHandles(forCameraId: cameraId)
            session.dispose()
        }
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "availableCameras":
            handleAvailableCameras(result: result)
        case "getPlatformCapabilities":
            handleGetPlatformCapabilities(result: result)
        case "create":
            handleCreate(call: call, result: result)
        case "initialize":
            handleInitialize(call: call, result: result)
        case "takePicture":
            handleTakePicture(call: call, result: result)
        case "startVideoRecording":
            handleStartVideoRecording(call: call, result: result)
        case "stopVideoRecording":
            handleStopVideoRecording(call: call, result: result)
        case "startImageStream":
            handleStartImageStream(call: call, result: result)
        case "stopImageStream":
            handleStopImageStream(call: call, result: result)
        case "pausePreview":
            handlePausePreview(call: call, result: result)
        case "resumePreview":
            handleResumePreview(call: call, result: result)
        case "setMirror":
            handleSetMirror(call: call, result: result)
        case "dispose":
            handleDispose(call: call, result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Method Handlers

    private func handleGetPlatformCapabilities(result: @escaping FlutterResult) {
        result([
            "supportsMirrorControl": true,
            "supportsVideoFpsControl": true,
            "supportsVideoBitrateControl": true,
        ])
    }

    private func handleAvailableCameras(result: @escaping FlutterResult) {
        DispatchQueue.global(qos: .userInitiated).async {
            let devices = DeviceEnumerator.enumerateDevices()
            let list = devices.map { device -> [String: Any] in
                return [
                    "name": device.name,
                    "lensDirection": device.lensDirection,
                    "sensorOrientation": device.sensorOrientation,
                ]
            }
            DispatchQueue.main.async {
                result(list)
            }
        }
    }

    private func handleCreate(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let cameraName = args["cameraName"] as? String,
              let resolutionPreset = args["resolutionPreset"] as? Int else {
            result(FlutterError(code: "invalid_args",
                                message: "Missing required arguments for create",
                                details: nil))
            return
        }

        let enableAudio = args["enableAudio"] as? Bool ?? false
        var targetFps = 30
        if let fps = args["fps"] as? Int {
            targetFps = fps
        } else if let fps = args["fps"] as? Double {
            targetFps = Int(fps)
        }
        let rawFps = targetFps
        if targetFps < 5 { targetFps = 5 }
        if targetFps > 60 { targetFps = 60 }
        if targetFps != rawFps {
        }

        var targetBitrate = 0
        if let bitrate = args["videoBitrate"] as? Int {
            targetBitrate = bitrate
        } else if let bitrate = args["videoBitrate"] as? Double {
            targetBitrate = Int(bitrate)
        }
        let rawBitrate = targetBitrate
        if targetBitrate < 0 { targetBitrate = 0 }
        if targetBitrate != rawBitrate {
        }

        var targetAudioBitrate = 0
        if let bitrate = args["audioBitrate"] as? Int {
            targetAudioBitrate = bitrate
        } else if let bitrate = args["audioBitrate"] as? Double {
            targetAudioBitrate = Int(bitrate)
        }
        let rawAudioBitrate = targetAudioBitrate
        if targetAudioBitrate < 0 { targetAudioBitrate = 0 }
        if targetAudioBitrate != rawAudioBitrate {
        }

        // Extract device ID from camera name: "Friendly Name (deviceId)"
        guard let deviceId = DeviceEnumerator.extractDeviceId(from: cameraName) else {
            result(FlutterError(code: "invalid_camera_name",
                                message: "Could not extract device ID from camera name",
                                details: nil))
            return
        }


        let cameraId = nextCameraId
        nextCameraId += 1

        let config = CameraSession.CameraConfig(
            deviceId: deviceId,
            resolutionPreset: resolutionPreset,
            enableAudio: enableAudio,
            targetFps: targetFps,
            targetBitrate: targetBitrate,
            audioBitrate: targetAudioBitrate
        )

        let session = CameraSession(
            cameraId: cameraId,
            config: config,
            textureRegistry: textureRegistry,
            methodChannel: methodChannel
        )

        let textureId = session.registerTexture()
        if textureId < 0 {
            result(FlutterError(code: "texture_registration_failed",
                                message: "Failed to register Flutter texture",
                                details: nil))
            return
        }

        sessionsLock.lock()
        sessions[cameraId] = session
        sessionsLock.unlock()

        result([
            "cameraId": cameraId,
            "textureId": textureId,
        ])
    }

    private func handleInitialize(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let session = findSession(call: call, result: result) else { return }
        session.initialize(result: result)
    }

    private func handleTakePicture(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let session = findSession(call: call, result: result) else { return }
        session.takePicture(result: result)
    }

    private func handleStartVideoRecording(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let session = findSession(call: call, result: result) else { return }
        session.startVideoRecording(result: result)
    }

    private func handleStopVideoRecording(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let session = findSession(call: call, result: result) else { return }
        session.stopVideoRecording(result: result)
    }

    private func handleStartImageStream(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let session = findSession(call: call, result: result) else { return }
        session.startImageStream()
        let streamHandle = ImageStreamHandleBridge.registerSession(session)
        result(["streamHandle": streamHandle])
    }

    private func handleStopImageStream(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let session = findSession(call: call, result: result) else { return }
        if let args = call.arguments as? [String: Any] {
            if let streamHandle = args["streamHandle"] as? Int64 {
                ImageStreamHandleBridge.releaseHandle(streamHandle)
            } else if let streamHandleInt = args["streamHandle"] as? Int {
                ImageStreamHandleBridge.releaseHandle(Int64(streamHandleInt))
            }
        }
        session.stopImageStream()
        result(nil)
    }

    private func handlePausePreview(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let session = findSession(call: call, result: result) else { return }
        session.pausePreview()
        result(nil)
    }

    private func handleResumePreview(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let session = findSession(call: call, result: result) else { return }
        session.resumePreview()
        result(nil)
    }

    private func handleSetMirror(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let session = findSession(call: call, result: result) else { return }
        guard let args = call.arguments as? [String: Any],
              let mirrored = args["mirrored"] as? Bool else {
            result(FlutterError(code: "invalid_args",
                                message: "Missing 'mirrored' argument",
                                details: nil))
            return
        }
        session.setMirror(mirrored: mirrored)
        result(nil)
    }

    private func handleDispose(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let cameraId = args["cameraId"] as? Int else {
            result(nil)
            return
        }

        sessionsLock.lock()
        let session = sessions.removeValue(forKey: cameraId)
        sessionsLock.unlock()

        ImageStreamHandleBridge.releaseHandles(forCameraId: cameraId)
        session?.dispose()
        result(nil)
    }

    // MARK: - Helpers

    private func findSession(call: FlutterMethodCall,
                              result: @escaping FlutterResult) -> CameraSession? {
        guard let args = call.arguments as? [String: Any],
              let cameraId = args["cameraId"] as? Int else {
            result(FlutterError(code: "invalid_args",
                                message: "Missing cameraId argument",
                                details: nil))
            return nil
        }

        guard let session = sessions[cameraId] else {
            result(FlutterError(code: "camera_not_found",
                                message: "No camera found with the given ID",
                                details: nil))
            return nil
        }

        return session
    }
}
