import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:stream_transform/stream_transform.dart';

import 'image_stream_ffi.dart';

/// Desktop implementation of [CameraPlatform].
///
/// On Linux, uses GStreamer + V4L2. On macOS, uses AVFoundation.
/// On Windows, uses Media Foundation (IMFCaptureEngine).
///
/// This plugin registers itself as the camera platform implementation for
/// desktop. When an app depends on both `camera` and `camera_desktop`, Flutter
/// automatically calls [registerWith], making [CameraController] work out of
/// the box.
class CameraDesktopPlugin extends CameraPlatform {
  /// Creates a new [CameraDesktopPlugin].
  ///
  /// The [channel] parameter is exposed for testing only.
  CameraDesktopPlugin({
    @visibleForTesting MethodChannel? channel,
    this.mirrorPreview = true,
  }) : _channel =
           channel ?? const MethodChannel('plugins.flutter.io/camera_desktop');

  /// Registers this class as the default [CameraPlatform] implementation.
  static void registerWith() {
    CameraPlatform.instance = CameraDesktopPlugin();
  }

  /// The method channel used to communicate with the native platform.
  final MethodChannel _channel;

  /// Returns desktop backend capabilities for feature-gating advanced controls.
  ///
  /// Keys are stable capability names (e.g. `supportsMirrorControl`).
  /// If the native side does not implement this method yet, returns an empty map.
  Future<Map<String, bool>> getPlatformCapabilities() async {
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>(
        'getPlatformCapabilities',
      );
      if (raw == null) return const <String, bool>{};
      final out = <String, bool>{};
      raw.forEach((key, value) {
        if (value is bool) {
          out[key] = value;
        }
      });
      return out;
    } on MissingPluginException {
      return const <String, bool>{};
    } on PlatformException {
      return const <String, bool>{};
    }
  }

  /// Whether to mirror the preview horizontally (like a mirror).
  /// Defaults to `true`. Set to `false` to show the unmirrored camera image.
  @Deprecated('Mirroring is now handled at the native capture level.')
  final bool mirrorPreview;

  /// Whether the native → Dart method-call handler has been installed.
  bool _nativeCallHandlerSet = false;

  /// Lazily installs the native → Dart method-call handler.
  ///
  /// Called before the first camera is created. This cannot run in the
  /// constructor because [registerWith] executes during plugin registration,
  /// before [WidgetsFlutterBinding.ensureInitialized].
  void _ensureNativeCallHandler() {
    if (!_nativeCallHandlerSet) {
      _channel.setMethodCallHandler(_handleNativeCall);
      _nativeCallHandlerSet = true;
    }
  }

  /// Mapping from cameraId to textureId (separate to decouple lifecycles).
  final Map<int, int> _textureIds = {};

  /// Broadcast stream for all camera events, filtered by cameraId downstream.
  final StreamController<CameraEvent> _eventStreamController =
      StreamController<CameraEvent>.broadcast();

  /// Per-camera image stream controllers for [onStreamedFrameAvailable].
  ///
  /// Only populated when [ImageStreamFfi] is unavailable and the fallback
  /// MethodChannel path is used for frame delivery. When FFI is active,
  /// frames bypass this map entirely and `_handleNativeCall`'s
  /// `imageStreamFrame` branch is a no-op for that camera.
  final Map<int, StreamController<CameraImageData>> _imageStreamControllers =
      {};

  /// Handles method calls from the native side (events pushed to Dart).
  ///
  /// Dispatches `cameraError`, `cameraClosing`, and `imageStreamFrame`
  /// events from native code into the appropriate Dart stream controllers.
  Future<dynamic> _handleNativeCall(MethodCall call) async {
    final args = call.arguments as Map<Object?, Object?>?;
    switch (call.method) {
      case 'cameraError':
        final cameraId = args!['cameraId']! as int;
        final description = args['description']! as String;
        _eventStreamController.add(CameraErrorEvent(cameraId, description));
      case 'cameraClosing':
        final cameraId = args!['cameraId']! as int;
        _eventStreamController.add(CameraClosingEvent(cameraId));
      case 'imageStreamFrame':
        final cameraId = args!['cameraId']! as int;
        final controller = _imageStreamControllers[cameraId];
        if (controller != null && !controller.isClosed) {
          final width = args['width']! as int;
          final height = args['height']! as int;
          final bytesPerRow = args['bytesPerRow'] as int? ?? (width * 4);
          final bytes = args['bytes']! as Uint8List;
          controller.add(
            CameraImageData(
              format: CameraImageFormat(
                ImageFormatGroup.bgra8888,
                raw: Platform.isMacOS ? 'BGRA' : 'RGBA',
              ),
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
    }
  }

  /// Filters the global event stream to events for a specific [cameraId].
  Stream<CameraEvent> _cameraEvents(int cameraId) => _eventStreamController
      .stream
      .where((CameraEvent e) => e.cameraId == cameraId);

  @override
  Future<List<CameraDescription>> availableCameras() async {
    final result = await _channel.invokeListMethod<Map<dynamic, dynamic>>(
      'availableCameras',
    );
    if (result == null) return <CameraDescription>[];
    return result.map((Map<dynamic, dynamic> m) {
      return CameraDescription(
        name: m['name'] as String,
        lensDirection: CameraLensDirection.values[m['lensDirection'] as int],
        sensorOrientation: m['sensorOrientation'] as int,
      );
    }).toList();
  }

  @override
  Future<int> createCamera(
    CameraDescription cameraDescription,
    ResolutionPreset? resolutionPreset, {
    bool enableAudio = false,
  }) async {
    return createCameraWithSettings(
      cameraDescription,
      MediaSettings(
        resolutionPreset: resolutionPreset,
        enableAudio: enableAudio,
      ),
    );
  }

  /// Creates a camera with the given [mediaSettings].
  ///
  /// The `videoBitrate` and `audioBitrate` fields are accessed via dynamic
  /// dispatch with try/catch because older versions of
  /// `camera_platform_interface` may not expose them.
  @override
  Future<int> createCameraWithSettings(
    CameraDescription cameraDescription,
    MediaSettings mediaSettings,
  ) async {
    _ensureNativeCallHandler();
    int? videoBitrate;
    try {
      final dynamic dynamicSettings = mediaSettings;
      final dynamic value = dynamicSettings.videoBitrate;
      if (value is int) {
        videoBitrate = value;
      } else if (value is num) {
        videoBitrate = value.toInt();
      }
    } catch (_) {}
    int? audioBitrate;
    try {
      final dynamic dynamicSettings = mediaSettings;
      final dynamic value = dynamicSettings.audioBitrate;
      if (value is int) {
        audioBitrate = value;
      } else if (value is num) {
        audioBitrate = value.toInt();
      }
    } catch (_) {}
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>('create', {
        'cameraName': cameraDescription.name,
        'resolutionPreset':
            mediaSettings.resolutionPreset?.index ?? ResolutionPreset.max.index,
        'enableAudio': mediaSettings.enableAudio,
        'fps': mediaSettings.fps,
        'videoBitrate': ?videoBitrate,
        'audioBitrate': ?audioBitrate,
      });
      final cameraId = result!['cameraId'] as int;
      final textureId = result['textureId'] as int;
      _textureIds[cameraId] = textureId;
      return cameraId;
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  @override
  Future<void> initializeCamera(
    int cameraId, {
    ImageFormatGroup imageFormatGroup = ImageFormatGroup.unknown,
  }) async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'initialize',
        {'cameraId': cameraId},
      );
      _eventStreamController.add(
        CameraInitializedEvent(
          cameraId,
          (result!['previewWidth'] as num).toDouble(),
          (result['previewHeight'] as num).toDouble(),
          ExposureMode.auto,
          false,
          FocusMode.auto,
          false,
        ),
      );
    } on PlatformException catch (e) {
      _eventStreamController.add(
        CameraErrorEvent(cameraId, e.message ?? 'Initialization failed'),
      );
      throw CameraException(e.code, e.message);
    }
  }

  /// Disposes the camera and releases all associated resources.
  ///
  /// Platform exceptions during disposal are silently ignored to ensure
  /// cleanup always completes.
  @override
  Future<void> dispose(int cameraId) async {
    try {
      await _channel.invokeMethod<void>('dispose', {'cameraId': cameraId});
    } on PlatformException catch (_) {
    } finally {
      _textureIds.remove(cameraId);
      final imageController = _imageStreamControllers.remove(cameraId);
      if (imageController != null && !imageController.isClosed) {
        imageController.close();
      }
    }
  }

  @override
  Stream<CameraInitializedEvent> onCameraInitialized(int cameraId) =>
      _cameraEvents(cameraId).whereType<CameraInitializedEvent>();

  @override
  Stream<CameraResolutionChangedEvent> onCameraResolutionChanged(
    int cameraId,
  ) => _cameraEvents(cameraId).whereType<CameraResolutionChangedEvent>();

  @override
  Stream<CameraClosingEvent> onCameraClosing(int cameraId) =>
      _cameraEvents(cameraId).whereType<CameraClosingEvent>();

  @override
  Stream<CameraErrorEvent> onCameraError(int cameraId) =>
      _cameraEvents(cameraId).whereType<CameraErrorEvent>();

  @override
  Stream<VideoRecordedEvent> onVideoRecordedEvent(int cameraId) =>
      _cameraEvents(cameraId).whereType<VideoRecordedEvent>();

  @override
  Stream<DeviceOrientationChangedEvent> onDeviceOrientationChanged() =>
      Stream<DeviceOrientationChangedEvent>.value(
        const DeviceOrientationChangedEvent(DeviceOrientation.landscapeLeft),
      );

  /// Builds the camera preview widget for the given [cameraId].
  ///
  /// On macOS and Linux the native backend mirrors the texture, so the
  /// [Texture] widget is returned as-is. On Windows, IMFCaptureEngine does
  /// not mirror natively, so the texture is wrapped in a horizontal
  /// [Transform] flip.
  @override
  Widget buildPreview(int cameraId) {
    final textureId = _textureIds[cameraId];
    if (textureId == null) {
      throw CameraException(
        'buildPreview',
        'Camera $cameraId has no registered texture. '
            'Was createCamera called?',
      );
    }
    final texture = Texture(textureId: textureId);
    if (!Platform.isWindows) return texture;
    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.diagonal3Values(-1, 1, 1),
      child: texture,
    );
  }

  @override
  Future<void> pausePreview(int cameraId) async {
    try {
      await _channel.invokeMethod<void>('pausePreview', {'cameraId': cameraId});
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  @override
  Future<void> resumePreview(int cameraId) async {
    try {
      await _channel.invokeMethod<void>('resumePreview', {
        'cameraId': cameraId,
      });
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  /// Toggles horizontal mirroring on the live camera feed.
  ///
  /// On macOS, this sets `isVideoMirrored` on the AVCaptureConnection.
  /// On Linux, this toggles the `videoflip` GStreamer element's method.
  /// On Windows, this returns a platform `unsupported` error.
  ///
  /// Can be called while the camera is running, no restart needed.
  /// Silently ignored via [MissingPluginException] if the native side
  /// has no handler for this platform.
  Future<void> setMirror(int cameraId, bool mirrored) async {
    try {
      await _channel.invokeMethod<void>('setMirror', {
        'cameraId': cameraId,
        'mirrored': mirrored,
      });
    } on MissingPluginException catch (_) {
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  @override
  bool supportsImageStreaming() => true;

  /// Returns a stream of [CameraImageData] frames from the camera.
  ///
  /// Image delivery uses a two-path architecture:
  /// 1. **FFI path** (preferred): reads directly from a native shared buffer
  ///    via `dart:ffi` for minimal copies (1 per frame). When active, frames
  ///    bypass [_imageStreamControllers] entirely, so `_handleNativeCall`'s
  ///    `imageStreamFrame` branch is a no-op for that camera.
  /// 2. **MethodChannel fallback**: if FFI setup fails (symbols not found),
  ///    frames are delivered through `_handleNativeCall` and stored in
  ///    [_imageStreamControllers].
  ///
  /// The stream handle returned by native `startImageStream` may be an int
  /// directly or a map containing a `streamHandle` key. Falls back to
  /// [cameraId] for backward compatibility with older native implementations.
  @override
  Stream<CameraImageData> onStreamedFrameAvailable(
    int cameraId, {
    CameraImageStreamOptions? options,
  }) {
    int extractStreamHandle(dynamic value) {
      if (value is int) return value;
      if (value is Map<dynamic, dynamic>) {
        final dynamic raw = value['streamHandle'];
        if (raw is int) return raw;
      }
      return cameraId;
    }

    ImageStreamFfi? ffi;
    int streamHandle = cameraId;
    late final StreamController<CameraImageData> controller;

    controller = StreamController<CameraImageData>(
      onListen: () async {
        final dynamic value = await _channel.invokeMethod<dynamic>(
          'startImageStream',
          {'cameraId': cameraId},
        );
        streamHandle = extractStreamHandle(value);
        ffi = ImageStreamFfi.tryCreate(streamHandle);
        if (ffi == null) {
          _imageStreamControllers[cameraId] = controller;
        } else {
          ffi!.start(controller);
        }
      },
      onCancel: () async {
        // Unregister the native callback first so no new frames are dispatched.
        ffi?.stop();
        _imageStreamControllers.remove(cameraId);
        // Tell native to stop streaming; await ensures the native side has
        // fully stopped before we dispose the FFI poller.
        await _channel.invokeMethod<void>('stopImageStream', {
          'cameraId': cameraId,
          'streamHandle': streamHandle,
        });
        // Native has stopped, safe to release FFI resources.
        ffi?.dispose();
      },
      onPause: () {},
      onResume: () {},
    );

    return controller.stream;
  }

  @override
  Future<XFile> takePicture(int cameraId) async {
    try {
      final path = await _channel.invokeMethod<String>('takePicture', {
        'cameraId': cameraId,
      });
      return XFile(path!);
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  /// No-op on desktop, no preparation needed before recording.
  @override
  Future<void> prepareForVideoRecording() async {}

  @override
  Future<void> startVideoCapturing(VideoCaptureOptions options) async {
    if (options.streamCallback != null) {
      throw CameraException(
        'startVideoCapturing',
        'Simultaneous recording and streaming via streamCallback is not yet supported on desktop. Use onStreamedFrameAvailable() and startVideoRecording() separately.',
      );
    }
    await startVideoRecording(options.cameraId);
  }

  @override
  Future<void> startVideoRecording(
    int cameraId, {
    Duration? maxVideoDuration,
  }) async {
    try {
      await _channel.invokeMethod<void>('startVideoRecording', {
        'cameraId': cameraId,
        if (maxVideoDuration != null)
          'maxVideoDuration': maxVideoDuration.inMilliseconds,
      });
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  @override
  Future<XFile> stopVideoRecording(int cameraId) async {
    try {
      final dynamic value = await _channel.invokeMethod<dynamic>(
        'stopVideoRecording',
        {'cameraId': cameraId},
      );
      if (value is String) {
        return XFile(value);
      }
      final map = value as Map<dynamic, dynamic>;
      final path = map['path'] as String?;
      if (path == null || path.isEmpty) {
        throw CameraException(
          'stopVideoRecording',
          'Native stopVideoRecording returned no output path.',
        );
      }
      return XFile(path);
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  @override
  Future<void> pauseVideoRecording(int cameraId) async {
    throw CameraException(
      'pauseVideoRecording',
      'Pausing video recording is not supported on desktop.',
    );
  }

  @override
  Future<void> resumeVideoRecording(int cameraId) async {
    throw CameraException(
      'resumeVideoRecording',
      'Resuming video recording is not supported on desktop.',
    );
  }

  /// No-op for [FlashMode.off]; desktop cameras typically lack flash hardware.
  @override
  Future<void> setFlashMode(int cameraId, FlashMode mode) async {
    if (mode == FlashMode.off) {
      return;
    }
    throw CameraException(
      'setFlashMode',
      'Flash mode is not supported on desktop.',
    );
  }

  /// No-op for [ExposureMode.auto] (the default); throws otherwise.
  @override
  Future<void> setExposureMode(int cameraId, ExposureMode mode) async {
    if (mode == ExposureMode.auto) return;
    throw CameraException(
      'setExposureMode',
      'Exposure mode control is not supported on desktop.',
    );
  }

  @override
  Future<void> setExposurePoint(int cameraId, Point<double>? point) async {
    throw CameraException(
      'setExposurePoint',
      'Exposure point is not supported on desktop.',
    );
  }

  @override
  Future<double> getMinExposureOffset(int cameraId) async => 0.0;

  @override
  Future<double> getMaxExposureOffset(int cameraId) async => 0.0;

  @override
  Future<double> getExposureOffsetStepSize(int cameraId) async => 0.0;

  @override
  Future<double> setExposureOffset(int cameraId, double offset) async => 0.0;

  /// No-op for [FocusMode.auto] (the default); throws otherwise.
  @override
  Future<void> setFocusMode(int cameraId, FocusMode mode) async {
    if (mode == FocusMode.auto) return;
    throw CameraException(
      'setFocusMode',
      'Focus mode control is not supported on desktop.',
    );
  }

  @override
  Future<void> setFocusPoint(int cameraId, Point<double>? point) async {
    throw CameraException(
      'setFocusPoint',
      'Focus point is not supported on desktop.',
    );
  }

  @override
  Future<double> getMinZoomLevel(int cameraId) async => 1.0;

  @override
  Future<double> getMaxZoomLevel(int cameraId) async => 1.0;

  @override
  Future<void> setZoomLevel(int cameraId, double zoom) async {
    if (zoom != 1.0) {
      throw CameraException(
        'setZoomLevel',
        'Zoom is not supported on desktop. Only 1.0 is accepted.',
      );
    }
  }

  /// No-op on desktop, orientation locking is not applicable.
  @override
  Future<void> lockCaptureOrientation(
    int cameraId,
    DeviceOrientation orientation,
  ) async {}

  /// No-op on desktop, orientation locking is not applicable.
  @override
  Future<void> unlockCaptureOrientation(int cameraId) async {}

  @override
  Future<void> setDescriptionWhileRecording(
    CameraDescription description,
  ) async {
    throw CameraException(
      'setDescriptionWhileRecording',
      'Switching camera during recording is not supported on desktop.',
    );
  }
}
