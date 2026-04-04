import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'screenshot_platform_interface.dart';
import 'src/models/captured_data.dart';
import 'src/models/capture_request.dart';
import 'src/models/screenshot_exception.dart';
import 'src/models/screenshot_mode.dart';

/// An implementation of [ScreenshotPlatform] that uses method channels.
class MethodChannelScreenshot extends ScreenshotPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final MethodChannel methodChannel = const MethodChannel(
    'dev.flutter.screenshot',
  );

  @override
  Future<CapturedData?> capture({
    required ScreenshotMode mode,
    bool includeCursor = false,
    int? displayId,
  }) async {
    try {
      // Create request and serialize to map
      final CaptureRequest request = CaptureRequest(
        mode: mode,
        includeCursor: includeCursor,
        displayId: displayId,
      );

      final Map<String, dynamic> arguments = request.toMap();

      // Invoke platform method
      final Map<Object?, Object?>? result = await methodChannel
          .invokeMethod<Map<Object?, Object?>>('capture', arguments);

      // Handle null result (cancellation)
      if (result == null) {
        return null;
      }

      // Deserialize response
      return CapturedData.fromMap(result);
    } on PlatformException catch (e) {
      // Map PlatformException to ScreenshotException
      throw ScreenshotException.fromPlatformException(
        code: e.code,
        message: e.message,
        details: e.details,
      );
    }
  }
}
