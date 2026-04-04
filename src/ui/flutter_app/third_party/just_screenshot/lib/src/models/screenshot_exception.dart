/// Exception thrown when screenshot capture fails.
///
/// This class is immutable and follows type safety principles.
class ScreenshotException implements Exception {
  /// Creates a [ScreenshotException] instance.
  const ScreenshotException({
    required this.code,
    required this.message,
    this.details,
  });

  /// Error code identifying the type of error.
  ///
  /// Possible values:
  /// - 'cancelled': User cancelled the operation
  /// - 'not_supported': Operation not supported on this platform
  /// - 'internal_error': Internal error occurred
  /// - 'invalid_argument': Invalid argument provided
  final String code;

  /// Human-readable error message.
  final String message;

  /// Optional additional error details.
  final dynamic details;

  /// Create [ScreenshotException] from method channel error.
  factory ScreenshotException.fromPlatformException({
    required String code,
    required String? message,
    dynamic details,
  }) {
    return ScreenshotException(
      code: code,
      message: message ?? 'Unknown error',
      details: details,
    );
  }

  @override
  String toString() {
    final StringBuffer buffer = StringBuffer();
    buffer.write('ScreenshotException($code: $message');
    if (details != null) {
      buffer.write(', details: $details');
    }
    buffer.write(')');
    return buffer.toString();
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is ScreenshotException &&
        other.code == code &&
        other.message == message &&
        other.details == details;
  }

  @override
  int get hashCode => Object.hash(code, message, details);
}
