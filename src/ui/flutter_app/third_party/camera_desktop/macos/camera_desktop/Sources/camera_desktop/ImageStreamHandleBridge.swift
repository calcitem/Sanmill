import Foundation

public typealias ImageStreamCallback = @convention(c) (Int32) -> Void

@_cdecl("camera_desktop_image_stream_noop_callback")
public func cameraDesktopImageStreamNoopCallback(_ cameraId: Int32) {
    _ = cameraId
}

@_cdecl("camera_desktop_get_image_stream_buffer")
public func cameraDesktopGetImageStreamBuffer(_ streamHandle: Int64) -> UnsafeMutableRawPointer? {
    ImageStreamHandleBridge.getImageStreamBuffer(forHandle: streamHandle)
}

@_cdecl("camera_desktop_register_image_stream_callback")
public func cameraDesktopRegisterImageStreamCallback(
    _ streamHandle: Int64,
    _ callback: ImageStreamCallback?
) {
    guard let callback else { return }
    ImageStreamHandleBridge.registerImageStreamCallback(callback, forHandle: streamHandle)
}

@_cdecl("camera_desktop_unregister_image_stream_callback")
public func cameraDesktopUnregisterImageStreamCallback(_ streamHandle: Int64) {
    ImageStreamHandleBridge.unregisterImageStreamCallback(forHandle: streamHandle)
}

private final class WeakCameraSession {
    weak var value: CameraSession?

    init(_ value: CameraSession) {
        self.value = value
    }
}

final class ImageStreamHandleBridge {
    private static var nextHandle: Int64 = 1
    private static var sessionsByHandle: [Int64: WeakCameraSession] = [:]
    private static var cameraIdByHandle: [Int64: Int] = [:]
    private static let lock = UnfairLock()

    static func registerSession(_ session: CameraSession) -> Int64 {
        lock.lock()
        defer { lock.unlock() }
        let handle = nextHandle
        nextHandle += 1
        sessionsByHandle[handle] = WeakCameraSession(session)
        cameraIdByHandle[handle] = session.cameraId
        return handle
    }

    static func releaseHandle(_ handle: Int64) {
        if handle == 0 { return }
        lock.lock()
        sessionsByHandle.removeValue(forKey: handle)
        cameraIdByHandle.removeValue(forKey: handle)
        lock.unlock()
    }

    static func releaseHandles(forCameraId cameraId: Int) {
        lock.lock()
        defer { lock.unlock() }
        let handlesToRemove = cameraIdByHandle.compactMap { entry in
            entry.value == cameraId ? entry.key : nil
        }
        for handle in handlesToRemove {
            sessionsByHandle.removeValue(forKey: handle)
            cameraIdByHandle.removeValue(forKey: handle)
        }
    }

    static func getImageStreamBuffer(forHandle handle: Int64) -> UnsafeMutableRawPointer? {
        lock.lock()
        let wrapper = sessionsByHandle[handle]
        let session = wrapper?.value
        if wrapper != nil && session == nil {
            sessionsByHandle.removeValue(forKey: handle)
            cameraIdByHandle.removeValue(forKey: handle)
        }
        lock.unlock()
        return session?.getImageStreamBufferPointer()
    }

    static func registerImageStreamCallback(
        _ callback: ImageStreamCallback,
        forHandle handle: Int64
    ) {
        lock.lock()
        let wrapper = sessionsByHandle[handle]
        let session = wrapper?.value
        if wrapper != nil && session == nil {
            sessionsByHandle.removeValue(forKey: handle)
            cameraIdByHandle.removeValue(forKey: handle)
        }
        lock.unlock()
        session?.registerImageStreamCallback(callback)
    }

    static func unregisterImageStreamCallback(forHandle handle: Int64) {
        lock.lock()
        let wrapper = sessionsByHandle[handle]
        let session = wrapper?.value
        if wrapper != nil && session == nil {
            sessionsByHandle.removeValue(forKey: handle)
            cameraIdByHandle.removeValue(forKey: handle)
        }
        lock.unlock()
        session?.unregisterImageStreamCallback()
    }
}
