import 'dart:typed_data';

/// Represents captured screenshot data with dimensions and pixel bytes.
///
/// This class is immutable and follows type safety principles.
class CapturedData {
  /// Creates a [CapturedData] instance.
  ///
  /// Validates that width and height are positive and bytes is non-empty.
  const CapturedData({
    required this.width,
    required this.height,
    required this.bytes,
  }) : assert(width > 0, 'Width must be positive'),
       assert(height > 0, 'Height must be positive'),
       assert(bytes.length > 0, 'Bytes must not be empty');

  /// Width of the captured image in pixels.
  final int width;

  /// Height of the captured image in pixels.
  final int height;

  /// PNG-encoded image data as bytes.
  final Uint8List bytes;

  /// Create [CapturedData] from method channel response map.
  factory CapturedData.fromMap(Map<Object?, Object?> map) {
    final int width = map['width'] as int;
    final int height = map['height'] as int;
    final Uint8List bytes = map['bytes'] as Uint8List;

    return CapturedData(width: width, height: height, bytes: bytes);
  }

  /// Convert [CapturedData] to map for method channel.
  Map<String, dynamic> toMap() {
    return <String, dynamic>{'width': width, 'height': height, 'bytes': bytes};
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is CapturedData &&
        other.width == width &&
        other.height == height &&
        _listEquals(other.bytes, bytes);
  }

  @override
  int get hashCode {
    int result = 17;
    result = 37 * result + width.hashCode;
    result = 37 * result + height.hashCode;
    // Hash bytes content, not identity
    for (final int byte in bytes) {
      result = 37 * result + byte.hashCode;
    }
    return result;
  }

  bool _listEquals<T>(List<T>? a, List<T>? b) {
    if (a == null) return b == null;
    if (b == null || a.length != b.length) return false;
    for (int index = 0; index < a.length; index += 1) {
      if (a[index] != b[index]) return false;
    }
    return true;
  }

  @override
  String toString() {
    return 'CapturedData(width: $width, height: $height, bytes: ${bytes.length} bytes)';
  }
}
