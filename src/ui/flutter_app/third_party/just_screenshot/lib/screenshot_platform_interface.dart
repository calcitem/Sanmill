import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'screenshot_method_channel.dart';
import 'src/models/captured_data.dart';
import 'src/models/screenshot_mode.dart';

/// The interface that platform-specific implementations of screenshot must implement.
///
/// Platform implementations should extend this class rather than implement it directly.
/// Extending this class ensures that the platform implementation doesn't break when
/// new methods are added to the interface.
abstract class ScreenshotPlatform extends PlatformInterface {
  /// Constructs a ScreenshotPlatform.
  ScreenshotPlatform() : super(token: _token);

  static final Object _token = Object();

  static ScreenshotPlatform _instance = MethodChannelScreenshot();

  /// The default instance of [ScreenshotPlatform] to use.
  ///
  /// Defaults to [MethodChannelScreenshot].
  static ScreenshotPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [ScreenshotPlatform] when
  /// they register themselves.
  static set instance(ScreenshotPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// Capture a screenshot.
  ///
  /// - [mode]: Screenshot capture mode (screen or region)
  /// - [includeCursor]: Whether to include the cursor in the screenshot
  /// - [displayId]: Optional display ID for multi-monitor setups (null = primary display)
  ///
  /// Returns [CapturedData] with image dimensions and PNG-encoded bytes,
  /// or null if the operation was cancelled by the user.
  ///
  /// Throws [ScreenshotException] if the operation fails.
  Future<CapturedData?> capture({
    required ScreenshotMode mode,
    bool includeCursor = false,
    int? displayId,
  }) {
    throw UnimplementedError('capture() has not been implemented.');
  }
}
