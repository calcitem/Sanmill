import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera_platform_interface/camera_platform_interface.dart';

/// FFI struct matching the native ImageStreamBuffer layout (32-byte header).
///
/// Layout:
///   int64_t sequence      (offset 0)
///   int32_t width         (offset 8)
///   int32_t height        (offset 12)
///   int32_t bytes_per_row (offset 16)
///   int32_t format        (offset 20)  -- 0=BGRA, 1=RGBA
///   int32_t ready         (offset 24)  -- 1=Dart may read, 0=native writing
///   int32_t _pad          (offset 28)
///   uint8_t pixels[]      (offset 32)
final class ImageStreamBuffer extends Struct {
  /// Frame sequence number, incremented by native code for each new frame.
  @Int64()
  external int sequence;

  /// Frame width in pixels.
  @Int32()
  external int width;

  /// Frame height in pixels.
  @Int32()
  external int height;

  /// Number of bytes per row (may include padding beyond width * 4).
  @Int32()
  external int bytesPerRow;

  /// Pixel format: 0 = BGRA (macOS), 1 = RGBA (Linux/Windows).
  @Int32()
  external int format;

  /// Ready flag: 1 = Dart may read, 0 = native is writing.
  @Int32()
  external int ready;

  /// Padding for 8-byte alignment.
  @Int32()
  // ignore: unused_field
  external int _pad;
}

/// Native function signature for retrieving the shared image buffer pointer.
typedef _GetBufferNative = Pointer<Void> Function(Int64 streamHandle);

/// Dart-side function type for [_GetBufferNative].
typedef _GetBufferDart = Pointer<Void> Function(int streamHandle);

/// Native function signature for registering a frame-ready callback.
typedef _RegisterCallbackNative =
    Void Function(
      Int64 streamHandle,
      Pointer<NativeFunction<Void Function(Int32)>> callback,
    );

/// Dart-side function type for [_RegisterCallbackNative].
typedef _RegisterCallbackDart =
    void Function(
      int streamHandle,
      Pointer<NativeFunction<Void Function(Int32)>> callback,
    );

/// Native function signature for unregistering a frame-ready callback.
typedef _UnregisterCallbackNative = Void Function(Int64 streamHandle);

/// Dart-side function type for [_UnregisterCallbackNative].
typedef _UnregisterCallbackDart = void Function(int streamHandle);

/// Manages FFI-based image stream for a single camera.
///
/// Instead of receiving frame data through MethodChannel serialization
/// (3 copies per frame), this reads directly from a native shared buffer
/// via dart:ffi (1 copy per frame, into a Dart-owned Uint8List).
///
/// If FFI setup fails (symbols not found, library not loadable), returns
/// null from [tryCreate] and the caller falls back to MethodChannel.
class ImageStreamFfi {
  ImageStreamFfi._(
    this._streamHandle,
    this._getBuffer,
    this._registerCallback,
    this._unregisterCallback,
    this._nativeNoopCallback,
  );

  /// The native stream handle used to identify this stream to native code.
  final int _streamHandle;

  /// FFI function to retrieve the shared buffer pointer.
  final _GetBufferDart _getBuffer;

  /// FFI function to register a frame-ready callback with native code.
  final _RegisterCallbackDart _registerCallback;

  /// FFI function to unregister the frame-ready callback.
  final _UnregisterCallbackDart _unregisterCallback;

  /// A native no-op callback symbol.
  ///
  /// Registered with native to keep the shared-buffer FFI fast path active
  /// without storing a Dart callback trampoline that can become invalid after
  /// hot restart.
  final Pointer<NativeFunction<Void Function(Int32)>> _nativeNoopCallback;

  /// Polls the shared buffer for new sequence numbers.
  Timer? _pollTimer;

  /// Prevents re-entrant polling when frame decoding/copying takes longer than
  /// the poll interval.
  bool _pollInProgress = false;

  /// The stream controller to which decoded frames are added.
  StreamController<CameraImageData>? _controller;

  /// The sequence number of the last frame delivered, used to skip duplicates.
  int _lastSequence = 0;

  /// Attempts to set up the FFI image stream.
  ///
  /// Returns null if the native library or required symbols cannot be found,
  /// allowing the caller to fall back to MethodChannel frame delivery.
  static ImageStreamFfi? tryCreate(int streamHandle) {
    try {
      final lib = _loadNativeLibrary();

      final getBuffer = lib.lookupFunction<_GetBufferNative, _GetBufferDart>(
        'camera_desktop_get_image_stream_buffer',
      );
      final registerCallback = lib
          .lookupFunction<_RegisterCallbackNative, _RegisterCallbackDart>(
            'camera_desktop_register_image_stream_callback',
          );
      final unregisterCallback = lib
          .lookupFunction<_UnregisterCallbackNative, _UnregisterCallbackDart>(
            'camera_desktop_unregister_image_stream_callback',
          );
      final nativeNoopCallback = lib
          .lookup<NativeFunction<Void Function(Int32)>>(
            'camera_desktop_image_stream_noop_callback',
          );

      return ImageStreamFfi._(
        streamHandle,
        getBuffer,
        registerCallback,
        unregisterCallback,
        nativeNoopCallback,
      );
    } catch (_) {
      return null;
    }
  }

  /// Loads the native library containing the FFI image stream symbols.
  ///
  /// On all desktop platforms, the plugin's native code is compiled into a
  /// shared library loaded by the Flutter engine. [DynamicLibrary.process]
  /// searches the current process's symbol table. On Windows, falls back to
  /// explicitly opening `camera_desktop_plugin.dll` if process lookup fails.
  static DynamicLibrary _loadNativeLibrary() {
    if (Platform.isMacOS) {
      final String contentsDirectory = File(
        Platform.resolvedExecutable,
      ).parent.parent.path;
      return DynamicLibrary.open(
        '$contentsDirectory/Frameworks/'
        'camera_desktop.framework/Versions/A/camera_desktop',
      );
    }
    if (Platform.isLinux) {
      return DynamicLibrary.process();
    }
    if (Platform.isWindows) {
      try {
        return DynamicLibrary.process();
      } catch (_) {
        return DynamicLibrary.open('camera_desktop_plugin.dll');
      }
    }
    throw UnsupportedError('Unsupported platform for FFI image stream');
  }

  /// Registers a native no-op callback and starts polling the shared buffer.
  ///
  /// Using a native callback symbol (instead of [NativeCallable.listener])
  /// avoids stale Dart callback metadata crashes during hot restart.
  void start(StreamController<CameraImageData> controller) {
    _controller = controller;
    _lastSequence = 0;
    _pollInProgress = false;

    _registerCallback(_streamHandle, _nativeNoopCallback);
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(
      const Duration(milliseconds: 8),
      (_) => _pollForFrame(),
    );
    _pollForFrame();
  }

  /// Polls for one new frame and emits it if sequence has advanced.
  void _pollForFrame() {
    if (_pollInProgress) return;
    _pollInProgress = true;
    try {
      _readLatestFrame();
    } finally {
      _pollInProgress = false;
    }
  }

  /// Reads the shared buffer, skips duplicate
  /// frames by comparing sequence numbers, creates a zero-copy view over
  /// the native pixel buffer, then copies into a Dart-owned [Uint8List]
  /// (1 copy, required by the platform interface contract).
  void _readLatestFrame() {
    final controller = _controller;
    if (controller == null || controller.isClosed) return;

    final bufPtr = _getBuffer(_streamHandle);
    if (bufPtr == nullptr) return;

    final buf = bufPtr.cast<ImageStreamBuffer>().ref;
    if (buf.ready != 1) return;

    if (buf.sequence <= _lastSequence) return;
    _lastSequence = buf.sequence;

    final width = buf.width;
    final height = buf.height;
    final bytesPerRow = buf.bytesPerRow;
    final format = buf.format;
    final dataSize = bytesPerRow * height;

    final pixelsPtr = bufPtr.cast<Uint8>() + sizeOf<ImageStreamBuffer>();
    final nativeView = pixelsPtr.asTypedList(dataSize);

    final bytes = Uint8List.fromList(nativeView);

    final rawFormat = format == 0 ? 'BGRA' : 'RGBA';

    controller.add(
      CameraImageData(
        format: CameraImageFormat(ImageFormatGroup.bgra8888, raw: rawFormat),
        width: width,
        height: height,
        planes: [
          CameraImagePlane(
            bytes: bytes,
            bytesPerRow: bytesPerRow,
            bytesPerPixel: 4,
            width: width,
            height: height,
          ),
        ],
      ),
    );
  }

  /// Unregisters the native callback.
  void stop() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _unregisterCallback(_streamHandle);
  }

  /// Releases all resources.
  void dispose() {
    stop();
    _controller = null;
  }
}
