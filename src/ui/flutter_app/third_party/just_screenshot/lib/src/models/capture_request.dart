import 'screenshot_mode.dart';

/// Internal model for capture request parameters.
///
/// Used internally to pass parameters from public API to platform implementation.
/// This class is immutable and follows type safety principles.
class CaptureRequest {
  /// Creates a [CaptureRequest] instance.
  const CaptureRequest({
    required this.mode,
    this.includeCursor = false,
    this.displayId,
  });

  /// Screenshot capture mode (screen or region).
  final ScreenshotMode mode;

  /// Whether to include the cursor in the screenshot.
  final bool includeCursor;

  /// Optional display ID for multi-monitor setups (null = primary display).
  final int? displayId;

  /// Convert [CaptureRequest] to map for method channel.
  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'mode': mode.toValue(),
      'includeCursor': includeCursor,
      if (displayId != null) 'displayId': displayId,
    };
  }

  /// Create [CaptureRequest] from map.
  factory CaptureRequest.fromMap(Map<Object?, Object?> map) {
    return CaptureRequest(
      mode: ScreenshotModeExtension.fromValue(map['mode'] as String),
      includeCursor: map['includeCursor'] as bool? ?? false,
      displayId: map['displayId'] as int?,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is CaptureRequest &&
        other.mode == mode &&
        other.includeCursor == includeCursor &&
        other.displayId == displayId;
  }

  @override
  int get hashCode => Object.hash(mode, includeCursor, displayId);

  @override
  String toString() {
    return 'CaptureRequest(mode: $mode, includeCursor: $includeCursor, displayId: $displayId)';
  }
}
