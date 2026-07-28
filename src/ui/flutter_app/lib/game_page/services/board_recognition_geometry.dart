// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import 'board_corner_detector.dart';
import 'board_recognition_models.dart';

/// Geometry operations for orienting and rectifying photographed boards.
abstract final class BoardRecognitionGeometry {
  static const int canonicalImageSize = 768;

  /// Padding around the selected outer-ring intersections in the canonical
  /// image. It keeps complete pieces visible at the eight outer-ring points.
  static const double canonicalPadding = 0.10;

  static const int maximumSourceDimension = 1600;

  /// Decodes an image, applies its EXIF orientation and bounds its resolution.
  static PreparedBoardImage? prepare(
    Uint8List bytes, {
    bool detectCorners = true,
  }) {
    final img.Image? decoded = img.decodeImage(bytes);
    if (decoded == null) {
      return null;
    }

    img.Image oriented = img.bakeOrientation(decoded);
    final int largestDimension = math.max(oriented.width, oriented.height);
    if (largestDimension > maximumSourceDimension) {
      final double scale = maximumSourceDimension / largestDimension;
      oriented = img.copyResize(
        oriented,
        width: math.max(1, (oriented.width * scale).round()),
        height: math.max(1, (oriented.height * scale).round()),
        interpolation: img.Interpolation.average,
      );
    }

    final BoardCornerDetection? cornerDetection = detectCorners
        ? BoardCornerDetector.detect(oriented)
        : null;
    return PreparedBoardImage(
      bytes: Uint8List.fromList(img.encodeJpg(oriented, quality: 94)),
      width: oriented.width,
      height: oriented.height,
      detectedCorners: cornerDetection != null && cornerDetection.isReliable
          ? cornerDetection.corners
          : null,
      cornerConfidence: cornerDetection?.confidence ?? 0,
    );
  }

  /// Maps the selected outer square to a canonical board using a projective
  /// transform rather than an axis-aligned crop.
  static img.Image rectify(
    img.Image source,
    BoardImageCorners corners, {
    int outputSize = canonicalImageSize,
    double padding = canonicalPadding,
  }) {
    assert(outputSize >= 64);
    assert(padding >= 0 && padding < 0.25);
    if (!corners.isValid) {
      throw ArgumentError.value(corners, 'corners', 'Invalid quadrilateral');
    }

    final _SquareToQuadrilateral transform = _SquareToQuadrilateral(
      topLeft: _toSourcePoint(corners.topLeft, source),
      topRight: _toSourcePoint(corners.topRight, source),
      bottomRight: _toSourcePoint(corners.bottomRight, source),
      bottomLeft: _toSourcePoint(corners.bottomLeft, source),
    );
    final img.Image destination = img.Image(
      width: outputSize,
      height: outputSize,
      numChannels: 3,
    );
    final double playableExtent = 1 - 2 * padding;

    for (int y = 0; y < outputSize; y++) {
      final double canonicalY = y / (outputSize - 1);
      final double v = (canonicalY - padding) / playableExtent;
      for (int x = 0; x < outputSize; x++) {
        final double canonicalX = x / (outputSize - 1);
        final double u = (canonicalX - padding) / playableExtent;
        final Offset sourcePoint = transform.map(u, v);

        // Selection handles are normally inset enough to cover the canonical
        // padding. Clamping keeps malformed edge pixels deterministic.
        final double sourceX = sourcePoint.dx.clamp(
          0.0,
          (source.width - 1).toDouble(),
        );
        final double sourceY = sourcePoint.dy.clamp(
          0.0,
          (source.height - 1).toDouble(),
        );
        destination.setPixel(
          x,
          y,
          source.getPixelInterpolate(
            sourceX,
            sourceY,
            interpolation: img.Interpolation.linear,
          ),
        );
      }
    }

    return destination;
  }

  /// Returns the fixed 24 Mill locations in canonical image coordinates.
  static List<BoardPoint> createCanonicalBoardPoints({
    int imageSize = canonicalImageSize,
    double padding = canonicalPadding,
  }) {
    assert(imageSize >= 64);
    assert(padding >= 0 && padding < 0.25);
    final double playableSize = (imageSize - 1) * (1 - 2 * padding);
    final double spacing = playableSize / 6;
    final double offset = (imageSize - 1) * padding;
    final double radius = spacing * 0.34;

    return standardGridPoints
        .map(
          (Offset point) => BoardPoint(
            (offset + point.dx * spacing).round(),
            (offset + point.dy * spacing).round(),
            radius,
            point.dx.round(),
            point.dy.round(),
          ),
        )
        .toList(growable: false);
  }

  static const List<Offset> standardGridPoints = <Offset>[
    Offset.zero,
    Offset(3, 0),
    Offset(6, 0),
    Offset(6, 3),
    Offset(6, 6),
    Offset(3, 6),
    Offset(0, 6),
    Offset(0, 3),
    Offset(1, 1),
    Offset(3, 1),
    Offset(5, 1),
    Offset(5, 3),
    Offset(5, 5),
    Offset(3, 5),
    Offset(1, 5),
    Offset(1, 3),
    Offset(2, 2),
    Offset(3, 2),
    Offset(4, 2),
    Offset(4, 3),
    Offset(4, 4),
    Offset(3, 4),
    Offset(2, 4),
    Offset(2, 3),
  ];

  static Offset _toSourcePoint(Offset normalized, img.Image source) => Offset(
    normalized.dx * (source.width - 1),
    normalized.dy * (source.height - 1),
  );
}

/// Projective mapping from the unit square to a quadrilateral.
class _SquareToQuadrilateral {
  _SquareToQuadrilateral({
    required Offset topLeft,
    required Offset topRight,
    required Offset bottomRight,
    required Offset bottomLeft,
  }) {
    final double dx1 = topRight.dx - bottomRight.dx;
    final double dx2 = bottomLeft.dx - bottomRight.dx;
    final double dx3 =
        topLeft.dx - topRight.dx + bottomRight.dx - bottomLeft.dx;
    final double dy1 = topRight.dy - bottomRight.dy;
    final double dy2 = bottomLeft.dy - bottomRight.dy;
    final double dy3 =
        topLeft.dy - topRight.dy + bottomRight.dy - bottomLeft.dy;

    if (dx3.abs() < 1e-9 && dy3.abs() < 1e-9) {
      _g = 0;
      _h = 0;
    } else {
      final double denominator = dx1 * dy2 - dx2 * dy1;
      if (denominator.abs() < 1e-9) {
        throw ArgumentError('The selected corners form a degenerate board');
      }
      _g = (dx3 * dy2 - dx2 * dy3) / denominator;
      _h = (dx1 * dy3 - dx3 * dy1) / denominator;
    }

    _a = topRight.dx - topLeft.dx + _g * topRight.dx;
    _b = bottomLeft.dx - topLeft.dx + _h * bottomLeft.dx;
    _c = topLeft.dx;
    _d = topRight.dy - topLeft.dy + _g * topRight.dy;
    _e = bottomLeft.dy - topLeft.dy + _h * bottomLeft.dy;
    _f = topLeft.dy;
  }

  late final double _a;
  late final double _b;
  late final double _c;
  late final double _d;
  late final double _e;
  late final double _f;
  late final double _g;
  late final double _h;

  Offset map(double u, double v) {
    final double denominator = _g * u + _h * v + 1;
    if (denominator.abs() < 1e-9) {
      throw StateError('Projective transform crossed infinity');
    }
    return Offset(
      (_a * u + _b * v + _c) / denominator,
      (_d * u + _e * v + _f) / denominator,
    );
  }
}
