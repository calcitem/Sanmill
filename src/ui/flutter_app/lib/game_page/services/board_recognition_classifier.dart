// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:math' as math;

import 'package:image/image.dart' as img;

import 'board_recognition_models.dart';
import 'mill.dart';

class BoardClassification {
  const BoardClassification({
    required this.pieces,
    required this.confidences,
    required this.characteristics,
    required this.colorProfile,
    required this.boardColor,
  });

  final Map<int, PieceColor> pieces;
  final Map<int, double> confidences;
  final ImageCharacteristics characteristics;
  final ColorProfile colorProfile;
  final Rgb boardColor;
}

/// Classifies fixed board locations relative to their local background.
///
/// No application theme colors are used. Each location is split into an inner
/// disk and a surrounding annulus, which makes the evidence resilient to
/// board material, color temperature and broad lighting gradients.
abstract final class BoardRecognitionClassifier {
  static const double occupancyThreshold = 0.43;
  static const double _minimumOutlineOnlyWhiteLuma = 225;
  static const double _minimumFilledDarkCoverage = 0.68;
  static const double _fullFilledDarkCoverage = 0.86;
  static const double _minimumFilledDarkAnnulusCoverage = 0.42;
  static const double _fullFilledDarkAnnulusCoverage = 0.53;
  static const double _maximumChangedPixelThreshold = 64;
  static const int _maximumBoardCoordinate = 6;

  static BoardClassification classify(
    img.Image image,
    List<BoardPoint> points,
  ) {
    assert(points.length == 24);
    final List<_PointEvidence> evidence = <_PointEvidence>[
      for (int index = 0; index < points.length; index++)
        _samplePoint(image, index, points[index]),
    ];

    final List<_PointEvidence> occupied = evidence
        .where(
          (_PointEvidence item) => item.occupancyScore >= occupancyThreshold,
        )
        .toList();
    final Map<int, PieceColor> pieces = <int, PieceColor>{
      for (int index = 0; index < points.length; index++)
        index: PieceColor.none,
    };
    final Map<int, double> confidences = <int, double>{
      for (final _PointEvidence item in evidence)
        item.index: _occupancyConfidence(item.occupancyScore),
    };

    final _LumaSplit? split = _findPieceLumaSplit(occupied);
    for (final _PointEvidence item in occupied) {
      final _PieceDecision decision = _classifyOccupiedPoint(item, split);
      pieces[item.index] = decision.color;
      confidences[item.index] = math.min(
        confidences[item.index]!,
        decision.confidence,
      );
    }

    final List<double> whiteLuma = <double>[
      for (final _PointEvidence item in occupied)
        if (pieces[item.index] == PieceColor.white) item.innerColor.luma,
    ];
    final List<double> blackLuma = <double>[
      for (final _PointEvidence item in occupied)
        if (pieces[item.index] == PieceColor.black) item.innerColor.luma,
    ];
    final List<double> emptyLuma = <double>[
      for (final _PointEvidence item in evidence)
        if (pieces[item.index] == PieceColor.none) item.outerColor.luma,
    ];
    final List<double> boardLuma = <double>[
      for (final _PointEvidence item in evidence) item.outerColor.luma,
    ];
    final Rgb boardColor = _medianRgb(<Rgb>[
      for (final _PointEvidence item in evidence) item.outerColor,
    ]);
    final double minimumLuma = evidence
        .map((_PointEvidence item) => item.innerColor.luma)
        .reduce(math.min);
    final double maximumLuma = evidence
        .map((_PointEvidence item) => item.innerColor.luma)
        .reduce(math.max);
    final double averageLuma = _mean(boardLuma, fallback: 128);
    final double contrast = maximumLuma - minimumLuma;

    return BoardClassification(
      pieces: pieces,
      confidences: confidences,
      characteristics: ImageCharacteristics(
        averageBrightness: averageLuma,
        isDarkBackground: averageLuma < 110,
        isHighContrast: contrast >= 80,
        whiteBrightnessThreshold: split?.threshold.round() ?? 160,
        blackBrightnessThreshold: split?.threshold.round() ?? 105,
        pieceDetectionThreshold: occupancyThreshold,
        contrastRatio: contrast / (averageLuma + 1),
      ),
      colorProfile: ColorProfile(
        whiteMean: _mean(whiteLuma, fallback: 210),
        blackMean: _mean(blackLuma, fallback: 45),
        emptyMean: _mean(emptyLuma, fallback: averageLuma),
        whiteStd: _standardDeviation(whiteLuma, minimum: 8),
        blackStd: _standardDeviation(blackLuma, minimum: 8),
        emptyStd: _standardDeviation(emptyLuma, minimum: 8),
      ),
      boardColor: boardColor,
    );
  }

  static _PointEvidence _samplePoint(
    img.Image image,
    int index,
    BoardPoint point,
  ) {
    final double innerRadius = point.radius * 0.76;
    final double outerRadiusMin = point.radius * 1.50;
    final double outerRadiusMax = point.radius * 1.82;
    final int scanRadius = outerRadiusMax.ceil();
    final List<Rgb> innerSamples = <Rgb>[];
    final List<Rgb> outerSamples = <Rgb>[];

    for (int dy = -scanRadius; dy <= scanRadius; dy++) {
      for (int dx = -scanRadius; dx <= scanRadius; dx++) {
        final double distanceSquared = (dx * dx + dy * dy).toDouble();
        final int x = point.x + dx;
        final int y = point.y + dy;
        if (x < 0 || x >= image.width || y < 0 || y >= image.height) {
          continue;
        }
        if (distanceSquared <= innerRadius * innerRadius) {
          innerSamples.add(_pixelRgb(image.getPixel(x, y)));
        } else if (distanceSquared >= outerRadiusMin * outerRadiusMin &&
            distanceSquared <= outerRadiusMax * outerRadiusMax &&
            _pointsTowardBoardInterior(point, dx, dy)) {
          outerSamples.add(_pixelRgb(image.getPixel(x, y)));
        }
      }
    }

    if (innerSamples.isEmpty || outerSamples.isEmpty) {
      throw StateError('Board point $index falls outside the rectified image');
    }

    final Rgb innerColor = _medianRgb(innerSamples);
    final Rgb outerColor = _medianRgb(outerSamples);
    final List<double> outerDistances = <double>[
      for (final Rgb sample in outerSamples)
        _perceptualDistance(sample, outerColor),
    ];
    final double outerNoise = _median(outerDistances);
    final double changedPixelThreshold = (outerNoise * 3 + 6).clamp(
      16,
      _maximumChangedPixelThreshold,
    );
    int changedPixels = 0;
    for (final Rgb sample in innerSamples) {
      if (_perceptualDistance(sample, outerColor) >= changedPixelThreshold) {
        changedPixels++;
      }
    }

    final double coverage = changedPixels / innerSamples.length;
    final double centerDistance = _perceptualDistance(innerColor, outerColor);
    // Thick board lines can cover much of an empty intersection. Give the
    // median center color enough weight to distinguish them from a filled
    // piece.
    final double rawCenterOccupancyScore =
        0.40 * coverage + 0.60 * (centerDistance / 32).clamp(0.0, 1.0);
    final double outlineCoverage = _outlineCoverage(
      image,
      point,
      outerColor,
      changedPixelThreshold,
    );
    final double lineBreakSupport = _lineBreakSupport(image, point, index);
    // A line crossing or an outlined empty node can have a dark median
    // center and a complete circular rim. A filled dark piece must instead
    // cover most of the sampled disk or its outer annulus. The annulus keeps
    // textured pieces detectable without admitting thick line crossings.
    final bool centerIsDarker = innerColor.luma < outerColor.luma;
    final double filledDiskSupport =
        ((coverage - _minimumFilledDarkCoverage) /
                (_fullFilledDarkCoverage - _minimumFilledDarkCoverage))
            .clamp(0.0, 1.0);
    final double innerAnnulusCoverage = _innerAnnulusCoverage(
      image,
      point,
      outerColor,
      changedPixelThreshold,
    );
    final double filledAnnulusSupport =
        ((innerAnnulusCoverage - _minimumFilledDarkAnnulusCoverage) /
                (_fullFilledDarkAnnulusCoverage -
                    _minimumFilledDarkAnnulusCoverage))
            .clamp(0.0, 1.0);
    final double filledDarkShapeSupport = math.max(
      filledDiskSupport,
      filledAnnulusSupport,
    );
    final double centerOccupancyScore = centerIsDarker
        ? rawCenterOccupancyScore * filledDarkShapeSupport
        : rawCenterOccupancyScore;
    // On darker boards, an isolated ring is more likely to mark an empty node
    // than a white piece whose center matches the board.
    final bool canBeOutlineOnlyWhitePiece =
        innerColor.luma >= _minimumOutlineOnlyWhiteLuma;
    final double outlineOccupancyScore = canBeOutlineOnlyWhitePiece
        ? ((outlineCoverage - 0.24) / 0.48).clamp(0.0, 1.0)
        : 0;
    // A board-colored piece suppresses the crossing line inside its disk while
    // leaving a circular rim, texture, and line continuation outside it.
    // Empty intersections retain much more changed-pixel coverage from the
    // crossing lines, including themes that draw an empty circular node.
    final double uncoveredLineBreak =
        lineBreakSupport * (1 - coverage / 0.25).clamp(0.0, 1.0);
    final double matchingColorShapeEvidence =
        outlineCoverage +
        2.0 * innerAnnulusCoverage +
        0.5 * uncoveredLineBreak -
        2.5 * coverage;
    // A mathematically complete ring is usually an empty-node marker. Filled
    // pieces still retain their regular center-color or dark-shape evidence.
    final double matchingColorOccupancyScore =
        outlineCoverage >= 0.96 || matchingColorShapeEvidence < 0.33
        ? 0
        : occupancyThreshold +
              ((matchingColorShapeEvidence - 0.33) / 0.67).clamp(0.0, 1.0) *
                  (1 - occupancyThreshold);
    final double occupancyScore = math.max(
      centerOccupancyScore,
      math.max(outlineOccupancyScore, matchingColorOccupancyScore),
    );
    return _PointEvidence(
      index: index,
      innerColor: innerColor,
      outerColor: outerColor,
      occupancyScore: occupancyScore,
    );
  }

  static double _outlineCoverage(
    img.Image image,
    BoardPoint point,
    Rgb backgroundColor,
    double changedPixelThreshold,
  ) {
    const int angleSamples = 36;
    const int radialSamples = 12;
    const double minimumRadiusScale = 0.68;
    const double maximumRadiusScale = 1.46;
    int changedAngles = 0;
    int consideredAngles = 0;

    // A piece rim crosses most radial spokes, while board lines cross only a
    // few. This detects outlined pieces whose centers match the board color.
    for (int angleIndex = 0; angleIndex < angleSamples; angleIndex++) {
      final double angle = angleIndex * 2 * math.pi / angleSamples;
      final double directionX = math.cos(angle);
      final double directionY = math.sin(angle);
      if (!_pointsTowardBoardInterior(point, directionX, directionY)) {
        continue;
      }
      consideredAngles++;
      bool changed = false;
      for (int radialIndex = 0; radialIndex < radialSamples; radialIndex++) {
        final double fraction = radialIndex / (radialSamples - 1);
        final double radius =
            point.radius *
            (minimumRadiusScale +
                (maximumRadiusScale - minimumRadiusScale) * fraction);
        final int x = (point.x + directionX * radius).round();
        final int y = (point.y + directionY * radius).round();
        if (x < 0 || x >= image.width || y < 0 || y >= image.height) {
          continue;
        }
        if (_perceptualDistance(
              _pixelRgb(image.getPixel(x, y)),
              backgroundColor,
            ) >=
            changedPixelThreshold) {
          changed = true;
          break;
        }
      }
      if (changed) {
        changedAngles++;
      }
    }
    return consideredAngles == 0 ? 0 : changedAngles / consideredAngles;
  }

  static double _innerAnnulusCoverage(
    img.Image image,
    BoardPoint point,
    Rgb backgroundColor,
    double changedPixelThreshold,
  ) {
    final double minimumRadius = point.radius * 0.55;
    final double maximumRadius = point.radius * 0.92;
    final int scanRadius = maximumRadius.ceil();
    int changedPixels = 0;
    int consideredPixels = 0;

    for (int dy = -scanRadius; dy <= scanRadius; dy++) {
      for (int dx = -scanRadius; dx <= scanRadius; dx++) {
        final double distanceSquared = (dx * dx + dy * dy).toDouble();
        if (distanceSquared < minimumRadius * minimumRadius ||
            distanceSquared > maximumRadius * maximumRadius) {
          continue;
        }
        final int x = point.x + dx;
        final int y = point.y + dy;
        consideredPixels++;
        if (_perceptualDistance(
              _pixelRgb(image.getPixel(x, y)),
              backgroundColor,
            ) >=
            changedPixelThreshold) {
          changedPixels++;
        }
      }
    }

    return changedPixels / consideredPixels;
  }

  static double _lineBreakSupport(
    img.Image image,
    BoardPoint point,
    int index,
  ) {
    final List<_SampleDirection> directions = _directionsForPoint(index);
    final List<double> rayScores = <double>[];
    for (final _SampleDirection direction in directions) {
      final List<double> outerContrasts = <double>[
        for (final double radiusScale in const <double>[1.12, 1.34, 1.56])
          _bilateralLineContrast(image, point, direction, radiusScale),
      ]..sort();
      final List<double> innerContrasts = <double>[
        for (final double radiusScale in const <double>[0.15, 0.35, 0.55])
          _bilateralLineContrast(image, point, direction, radiusScale),
      ]..sort();
      final double outerContrast = outerContrasts[1];
      final double innerContrast = innerContrasts[1];
      final double outerSupport = ((outerContrast - 6) / 18).clamp(0.0, 1.0);
      final double interruption = ((outerContrast - innerContrast - 3) / 17)
          .clamp(0.0, 1.0);
      rayScores.add(outerSupport * interruption);
    }
    rayScores.sort();
    if (rayScores.length == 2) {
      return 0.55 * rayScores[0] + 0.45 * rayScores[1];
    }
    return _mean(rayScores.sublist(1), fallback: 0);
  }

  static double _bilateralLineContrast(
    img.Image image,
    BoardPoint point,
    _SampleDirection direction,
    double radiusScale,
  ) {
    final double distance = point.radius * radiusScale;
    final double sideOffset = point.radius * 0.22;
    final double centerX = point.x + direction.dx * distance;
    final double centerY = point.y + direction.dy * distance;
    final double normalX = -direction.dy;
    final double normalY = direction.dx;
    final Rgb center = _sampleRgb(image, centerX, centerY);
    final Rgb negativeSide = _sampleRgb(
      image,
      centerX - normalX * sideOffset,
      centerY - normalY * sideOffset,
    );
    final Rgb positiveSide = _sampleRgb(
      image,
      centerX + normalX * sideOffset,
      centerY + normalY * sideOffset,
    );
    return math.min(
      _perceptualDistance(center, negativeSide),
      _perceptualDistance(center, positiveSide),
    );
  }

  static Rgb _sampleRgb(img.Image image, double x, double y) {
    final double boundedX = x.clamp(0.0, (image.width - 1).toDouble());
    final double boundedY = y.clamp(0.0, (image.height - 1).toDouble());
    return _pixelRgb(
      image.getPixelInterpolate(
        boundedX,
        boundedY,
        interpolation: img.Interpolation.linear,
      ),
    );
  }

  static List<_SampleDirection> _directionsForPoint(int index) {
    assert(index >= 0 && index < 24);
    final int ring = index ~/ 8;
    final int point = index % 8;
    final List<_SampleDirection> directions = <_SampleDirection>[
      ..._ringDirections[point],
    ];
    if (point.isOdd) {
      final _SampleDirection inward = _inwardDirections[point]!;
      if (ring < 2) {
        directions.add(inward);
      }
      if (ring > 0) {
        directions.add(_SampleDirection(-inward.dx, -inward.dy));
      }
    }
    return directions;
  }

  static const List<List<_SampleDirection>> _ringDirections =
      <List<_SampleDirection>>[
        <_SampleDirection>[_SampleDirection(1, 0), _SampleDirection(0, 1)],
        <_SampleDirection>[_SampleDirection(-1, 0), _SampleDirection(1, 0)],
        <_SampleDirection>[_SampleDirection(-1, 0), _SampleDirection(0, 1)],
        <_SampleDirection>[_SampleDirection(0, -1), _SampleDirection(0, 1)],
        <_SampleDirection>[_SampleDirection(0, -1), _SampleDirection(-1, 0)],
        <_SampleDirection>[_SampleDirection(1, 0), _SampleDirection(-1, 0)],
        <_SampleDirection>[_SampleDirection(0, -1), _SampleDirection(1, 0)],
        <_SampleDirection>[_SampleDirection(0, 1), _SampleDirection(0, -1)],
      ];
  static const Map<int, _SampleDirection> _inwardDirections =
      <int, _SampleDirection>{
        1: _SampleDirection(0, 1),
        3: _SampleDirection(-1, 0),
        5: _SampleDirection(0, -1),
        7: _SampleDirection(1, 0),
      };

  static bool _pointsTowardBoardInterior(
    BoardPoint point,
    num deltaX,
    num deltaY,
  ) {
    final int? gridX = point.originalX;
    final int? gridY = point.originalY;
    if (gridX == null || gridY == null) {
      return true;
    }
    // Surrounding page content is not valid evidence for outer-ring nodes.
    return !(gridX == 0 && deltaX < 0) &&
        !(gridX == _maximumBoardCoordinate && deltaX > 0) &&
        !(gridY == 0 && deltaY < 0) &&
        !(gridY == _maximumBoardCoordinate && deltaY > 0);
  }

  static _LumaSplit? _findPieceLumaSplit(List<_PointEvidence> occupied) {
    if (occupied.length < 2) {
      return null;
    }
    final List<double> values =
        occupied.map((_PointEvidence item) => item.innerColor.luma).toList()
          ..sort();
    double largestGap = 0;
    int splitIndex = -1;
    for (int index = 0; index < values.length - 1; index++) {
      final double gap = values[index + 1] - values[index];
      if (gap > largestGap) {
        largestGap = gap;
        splitIndex = index;
      }
    }

    // A wide global range alone is not enough: the separation itself must be
    // clear so a single color under uneven lighting is not split in two.
    if (splitIndex < 0 || largestGap < 28) {
      return null;
    }
    final double lowerMean = _mean(
      values.sublist(0, splitIndex + 1),
      fallback: values.first,
    );
    final double upperMean = _mean(
      values.sublist(splitIndex + 1),
      fallback: values.last,
    );
    final double candidateThreshold =
        (values[splitIndex] + values[splitIndex + 1]) / 2;
    final List<double> upperLocalDeltas = <double>[
      for (final _PointEvidence item in occupied)
        if (item.innerColor.luma >= candidateThreshold)
          item.innerColor.luma - item.outerColor.luma,
    ];
    final double upperLocalDelta = _mean(upperLocalDeltas, fallback: 0);
    final bool conventionalLightClass = upperMean >= 135;
    final bool separatedGrayClass =
        largestGap >= 50 &&
        lowerMean <= 90 &&
        upperMean >= 105 &&
        upperLocalDelta >= -8;
    if (lowerMean > 125 || (!conventionalLightClass && !separatedGrayClass)) {
      return null;
    }
    return _LumaSplit(threshold: candidateThreshold, gap: largestGap);
  }

  static _PieceDecision _classifyOccupiedPoint(
    _PointEvidence item,
    _LumaSplit? split,
  ) {
    if (split != null) {
      final PieceColor color = item.innerColor.luma < split.threshold
          ? PieceColor.black
          : PieceColor.white;
      return _PieceDecision(color, (split.gap / 70).clamp(0.45, 1.0));
    }

    final double delta = item.innerColor.luma - item.outerColor.luma;
    if (item.innerColor.luma <= 100 || delta <= -16) {
      final double strength = math.max(100 - item.innerColor.luma, -delta);
      return _PieceDecision(
        PieceColor.black,
        (0.45 + strength / 120).clamp(0.45, 0.95),
      );
    }
    if (item.innerColor.luma >= 155 || delta >= 16) {
      final double strength = math.max(item.innerColor.luma - 155, delta);
      return _PieceDecision(
        PieceColor.white,
        (0.45 + strength / 120).clamp(0.45, 0.95),
      );
    }

    // Ambiguous mid-tone pieces are still surfaced for correction rather than
    // being silently converted to empty points.
    return _PieceDecision(
      delta < 0 ? PieceColor.black : PieceColor.white,
      0.35,
    );
  }

  static double _occupancyConfidence(double score) {
    final double distance = (score - occupancyThreshold).abs();
    return (0.45 + distance / 0.35).clamp(0.45, 1.0);
  }

  static Rgb _pixelRgb(img.Color color) =>
      Rgb(color.r.toInt(), color.g.toInt(), color.b.toInt());

  static Rgb _medianRgb(List<Rgb> values) {
    assert(values.isNotEmpty);
    final List<int> red = <int>[for (final Rgb value in values) value.r]
      ..sort();
    final List<int> green = <int>[for (final Rgb value in values) value.g]
      ..sort();
    final List<int> blue = <int>[for (final Rgb value in values) value.b]
      ..sort();
    final int middle = values.length ~/ 2;
    return Rgb(red[middle], green[middle], blue[middle]);
  }

  static double _perceptualDistance(Rgb first, Rgb second) {
    final double firstY = first.luma;
    final double secondY = second.luma;
    final double dy = firstY - secondY;
    final double du = (first.b - firstY) - (second.b - secondY);
    final double dv = (first.r - firstY) - (second.r - secondY);
    return math.sqrt(dy * dy + 0.5 * du * du + 0.5 * dv * dv);
  }

  static double _median(List<double> values) {
    assert(values.isNotEmpty);
    values.sort();
    final int middle = values.length ~/ 2;
    if (values.length.isOdd) {
      return values[middle];
    }
    return (values[middle - 1] + values[middle]) / 2;
  }

  static double _mean(List<double> values, {required double fallback}) {
    if (values.isEmpty) {
      return fallback;
    }
    return values.reduce((double a, double b) => a + b) / values.length;
  }

  static double _standardDeviation(
    List<double> values, {
    required double minimum,
  }) {
    if (values.length < 2) {
      return minimum;
    }
    final double mean = _mean(values, fallback: 0);
    final double variance =
        values
            .map((double value) => math.pow(value - mean, 2).toDouble())
            .reduce((double a, double b) => a + b) /
        values.length;
    return math.max(minimum, math.sqrt(variance));
  }
}

class _PointEvidence {
  const _PointEvidence({
    required this.index,
    required this.innerColor,
    required this.outerColor,
    required this.occupancyScore,
  });

  final int index;
  final Rgb innerColor;
  final Rgb outerColor;
  final double occupancyScore;
}

class _LumaSplit {
  const _LumaSplit({required this.threshold, required this.gap});

  final double threshold;
  final double gap;
}

class _PieceDecision {
  const _PieceDecision(this.color, this.confidence);

  final PieceColor color;
  final double confidence;
}

class _SampleDirection {
  const _SampleDirection(this.dx, this.dy);

  final double dx;
  final double dy;
}
