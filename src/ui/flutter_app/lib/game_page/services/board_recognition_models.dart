// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import 'mill.dart';

/// The four outer-ring corner intersections selected in the source image.
///
/// Coordinates are normalized to the oriented source image, so they remain
/// stable when the preview is laid out at a different size.
class BoardImageCorners {
  const BoardImageCorners({
    required this.topLeft,
    required this.topRight,
    required this.bottomRight,
    required this.bottomLeft,
  });

  factory BoardImageCorners.inset([double inset = 0.12]) {
    assert(inset > 0 && inset < 0.5);
    return BoardImageCorners(
      topLeft: Offset(inset, inset),
      topRight: Offset(1 - inset, inset),
      bottomRight: Offset(1 - inset, 1 - inset),
      bottomLeft: Offset(inset, 1 - inset),
    );
  }

  final Offset topLeft;
  final Offset topRight;
  final Offset bottomRight;
  final Offset bottomLeft;

  List<Offset> get points => <Offset>[
    topLeft,
    topRight,
    bottomRight,
    bottomLeft,
  ];

  BoardImageCorners replace(int index, Offset value) {
    assert(index >= 0 && index < 4);
    return BoardImageCorners(
      topLeft: index == 0 ? value : topLeft,
      topRight: index == 1 ? value : topRight,
      bottomRight: index == 2 ? value : bottomRight,
      bottomLeft: index == 3 ? value : bottomLeft,
    );
  }

  /// Whether the points form a sufficiently large, convex quadrilateral.
  bool get isValid {
    const double epsilon = 0.0001;
    for (final Offset point in points) {
      if (!point.dx.isFinite ||
          !point.dy.isFinite ||
          point.dx < 0 ||
          point.dx > 1 ||
          point.dy < 0 ||
          point.dy > 1) {
        return false;
      }
    }

    final List<double> turns = <double>[];
    for (int i = 0; i < 4; i++) {
      final Offset a = points[i];
      final Offset b = points[(i + 1) % 4];
      final Offset c = points[(i + 2) % 4];
      turns.add(_cross(b - a, c - b));
    }
    final bool orderedClockwise = turns.every(
      (double value) => value > epsilon,
    );
    if (!orderedClockwise) {
      return false;
    }

    return area >= 0.04;
  }

  double get area {
    double twiceArea = 0;
    for (int i = 0; i < 4; i++) {
      final Offset current = points[i];
      final Offset next = points[(i + 1) % 4];
      twiceArea += current.dx * next.dy - next.dx * current.dy;
    }
    return twiceArea.abs() / 2;
  }

  static double _cross(Offset first, Offset second) =>
      first.dx * second.dy - first.dy * second.dx;
}

/// An oriented, bounded-resolution image ready for corner selection.
class PreparedBoardImage {
  const PreparedBoardImage({
    required this.bytes,
    required this.width,
    required this.height,
    this.detectedCorners,
    this.cornerConfidence = 0,
  });

  final Uint8List bytes;
  final int width;
  final int height;
  final BoardImageCorners? detectedCorners;
  final double cornerConfidence;

  Size get size => Size(width.toDouble(), height.toDouble());
}

enum BoardRecognitionFailure {
  imageDecodeFailed,
  invalidCorners,
  noPiecesDetected,
  processingFailed,
}

/// Immutable output from a board-recognition attempt.
class BoardRecognitionResult {
  BoardRecognitionResult.success({
    required Map<int, PieceColor> pieces,
    required Map<int, double> confidences,
    required this.rectifiedImageBytes,
    required this.boardPoints,
    required this.processedWidth,
    required this.processedHeight,
    required this.debugInfo,
  }) : pieces = UnmodifiableMapView<int, PieceColor>(pieces),
       confidences = UnmodifiableMapView<int, double>(confidences),
       failure = null;

  BoardRecognitionResult.failure({
    required this.failure,
    this.rectifiedImageBytes,
    this.boardPoints = const <BoardPoint>[],
    this.processedWidth = 0,
    this.processedHeight = 0,
    BoardRecognitionDebugInfo? debugInfo,
  }) : pieces = const <int, PieceColor>{},
       confidences = const <int, double>{},
       debugInfo = debugInfo ?? BoardRecognitionDebugInfo();

  final Map<int, PieceColor> pieces;
  final Map<int, double> confidences;
  final BoardRecognitionFailure? failure;
  final Uint8List? rectifiedImageBytes;
  final List<BoardPoint> boardPoints;
  final int processedWidth;
  final int processedHeight;
  final BoardRecognitionDebugInfo debugInfo;

  bool get isSuccess => failure == null;

  bool get hasPieces => pieces.values.any(
    (PieceColor color) =>
        color == PieceColor.white || color == PieceColor.black,
  );
}

/// Debug information retained for the existing development diagnostics.
class BoardRecognitionDebugInfo {
  BoardRecognitionDebugInfo({
    this.originalImage,
    this.processedImage,
    this.boardRect,
    this.boardColor,
    this.characteristics,
    this.colorProfile,
    this.boardMask,
    this.boardPoints = const <BoardPoint>[],
    this.linesDetectionImage,
  });

  final img.Image? originalImage;
  final img.Image? processedImage;
  final math.Rectangle<int>? boardRect;
  final Rgb? boardColor;
  final ImageCharacteristics? characteristics;
  final ColorProfile? colorProfile;
  final List<List<bool>>? boardMask;
  final List<BoardPoint> boardPoints;
  final img.Image? linesDetectionImage;

  BoardRecognitionDebugInfo copyWith({
    img.Image? originalImage,
    img.Image? processedImage,
    math.Rectangle<int>? boardRect,
    Rgb? boardColor,
    ImageCharacteristics? characteristics,
    ColorProfile? colorProfile,
    List<List<bool>>? boardMask,
    List<BoardPoint>? boardPoints,
    img.Image? linesDetectionImage,
  }) {
    return BoardRecognitionDebugInfo(
      originalImage: originalImage ?? this.originalImage,
      processedImage: processedImage ?? this.processedImage,
      boardRect: boardRect ?? this.boardRect,
      boardColor: boardColor ?? this.boardColor,
      characteristics: characteristics ?? this.characteristics,
      colorProfile: colorProfile ?? this.colorProfile,
      boardMask: boardMask ?? this.boardMask,
      boardPoints: boardPoints ?? this.boardPoints,
      linesDetectionImage: linesDetectionImage ?? this.linesDetectionImage,
    );
  }

  static Uint8List? imageToBytes(img.Image? image) {
    if (image == null) {
      return null;
    }
    return Uint8List.fromList(img.encodeJpg(image));
  }
}

/// A sampled location in the rectified board image.
class BoardPoint {
  const BoardPoint(
    this.x,
    this.y,
    this.radius, [
    this.originalX,
    this.originalY,
  ]);

  final int x;
  final int y;
  final double radius;
  final int? originalX;
  final int? originalY;
}

class ImageCharacteristics {
  const ImageCharacteristics({
    required this.averageBrightness,
    required this.isDarkBackground,
    required this.isHighContrast,
    required this.whiteBrightnessThreshold,
    required this.blackBrightnessThreshold,
    required this.pieceDetectionThreshold,
    this.contrastRatio = 1.0,
  });

  final double averageBrightness;
  final bool isDarkBackground;
  final bool isHighContrast;
  final int whiteBrightnessThreshold;
  final int blackBrightnessThreshold;
  final double pieceDetectionThreshold;
  final double contrastRatio;
}

class ColorProfile {
  const ColorProfile({
    required this.whiteMean,
    required this.blackMean,
    required this.emptyMean,
    required this.whiteStd,
    required this.blackStd,
    required this.emptyStd,
  });

  final double whiteMean;
  final double blackMean;
  final double emptyMean;
  final double whiteStd;
  final double blackStd;
  final double emptyStd;
}

class Rgb {
  const Rgb(this.r, this.g, this.b);

  final int r;
  final int g;
  final int b;

  double distanceTo(Rgb other) {
    final int dr = r - other.r;
    final int dg = g - other.g;
    final int db = b - other.b;
    return math.sqrt((dr * dr + dg * dg + db * db).toDouble());
  }

  double get luma => 0.299 * r + 0.587 * g + 0.114 * b;

  @override
  String toString() => 'RGB($r, $g, $b)';
}
