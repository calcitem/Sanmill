// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:image/image.dart' as img;

import 'board_recognition_models.dart';

/// Result of matching the known Mill line layout against a source image.
class BoardCornerDetection {
  const BoardCornerDetection({
    required this.corners,
    required this.confidence,
    required this.score,
  });

  final BoardImageCorners corners;
  final double confidence;
  final double score;

  bool get isReliable =>
      corners.isValid &&
      confidence >= BoardCornerDetector.minimumReliableConfidence;
}

/// Finds the outer-square intersections without a native vision dependency.
///
/// The detector downsamples the image, builds a directional Sobel field and
/// optimizes a projective quadrilateral against all 32 adjacent-node segments
/// shared by Nine and Twelve Men's Morris boards. Optional diagonal connectors
/// do not replace those segments. Matching continuous, bilateral line ridges
/// makes it less likely to lock onto pieces, labels or decorative edges.
abstract final class BoardCornerDetector {
  static const double minimumReliableConfidence = 0.34;
  static const int _maximumAnalysisDimension = 300;

  static const List<Offset> _boardPoints = <Offset>[
    Offset.zero,
    Offset(0.5, 0),
    Offset(1, 0),
    Offset(1, 0.5),
    Offset(1, 1),
    Offset(0.5, 1),
    Offset(0, 1),
    Offset(0, 0.5),
    Offset(1 / 6, 1 / 6),
    Offset(0.5, 1 / 6),
    Offset(5 / 6, 1 / 6),
    Offset(5 / 6, 0.5),
    Offset(5 / 6, 5 / 6),
    Offset(0.5, 5 / 6),
    Offset(1 / 6, 5 / 6),
    Offset(1 / 6, 0.5),
    Offset(1 / 3, 1 / 3),
    Offset(0.5, 1 / 3),
    Offset(2 / 3, 1 / 3),
    Offset(2 / 3, 0.5),
    Offset(2 / 3, 2 / 3),
    Offset(0.5, 2 / 3),
    Offset(1 / 3, 2 / 3),
    Offset(1 / 3, 0.5),
  ];

  static final List<_BoardSegment> _segments = _createSegments();

  static const List<double> _lineSamplePositions = <double>[
    0.28,
    0.39,
    0.50,
    0.61,
    0.72,
  ];

  /// Returns a scored suggestion. Callers should use [isReliable] before
  /// replacing their safe fallback corners.
  static BoardCornerDetection detect(img.Image source) {
    if (source.width < 32 || source.height < 32) {
      return const BoardCornerDetection(
        corners: BoardImageCorners(
          topLeft: Offset(0.12, 0.12),
          topRight: Offset(0.88, 0.12),
          bottomRight: Offset(0.88, 0.88),
          bottomLeft: Offset(0.12, 0.88),
        ),
        confidence: 0,
        score: 0,
      );
    }

    final img.Image analysisImage = _resizeForAnalysis(source);
    final _ImageField field = _ImageField.fromImage(analysisImage);
    final List<_ScoredCorners> seeds = _createSeeds(field)
      ..sort(
        (_ScoredCorners first, _ScoredCorners second) =>
            second.score.compareTo(first.score),
      );

    final List<_ScoredCorners> starts = <_ScoredCorners>[];
    for (final _ScoredCorners seed in seeds) {
      final bool distinct = starts.every(
        (_ScoredCorners selected) =>
            _cornerDistance(seed.corners, selected.corners) > 0.035,
      );
      if (distinct) {
        starts.add(seed);
      }
      if (starts.length == 8) {
        break;
      }
    }

    _ScoredCorners best = starts.first;
    double markerReliability = 0;
    for (final _ScoredCorners start in starts) {
      final _ScoredCorners optimized = _optimize(field, start);
      if (optimized.score > best.score) {
        best = optimized;
      }
    }
    best = _refineSelectedCandidate(field, best);
    final _ScoredCorners? compact = _findCompactBoardCandidate(field);
    if (compact != null) {
      final double selectedEnhancedScore = _scorePattern(
        field,
        best.corners,
        enhanced: true,
      );
      final double compactLegacyScore = _scorePattern(
        field,
        compact.corners,
        minimumSideFraction: 0.30,
      );
      final double selectedNodeScore = _scoreNodePattern(
        field,
        _ProjectiveMap(best.corners),
      );
      final double compactNodeScore = _scoreNodePattern(
        field,
        _ProjectiveMap(compact.corners),
      );
      final bool hasStrongLineTopology =
          compact.score >= 1.30 &&
          compact.score >= selectedEnhancedScore + 0.40 &&
          compactLegacyScore >= 0.90;
      // Physical boards can encode faint or colored lines but retain a clear
      // 24-node lattice of holes or pegs. Permit a compact candidate only when
      // that complete lattice improves decisively over the larger frame.
      final bool hasNodeLatticeSeed =
          compact.score >= 0.62 &&
          compact.score >= selectedEnhancedScore + 0.20 &&
          compactLegacyScore >= 0.50 &&
          compactNodeScore >= 0.64 &&
          compactNodeScore >= selectedNodeScore + 0.16;
      if (hasStrongLineTopology) {
        best = _ScoredCorners(compact.corners, compactLegacyScore);
      } else if (hasNodeLatticeSeed) {
        final double initialCenteredScore = _scoreCenteredNodePattern(
          field,
          _ProjectiveMap(compact.corners),
        );
        final _ScoredCorners centered = _refineCenteredNodeCandidate(
          field,
          compact,
        );
        final double centeredNodeScore = _scoreCenteredNodePattern(
          field,
          _ProjectiveMap(centered.corners),
        );
        final double centeredEnhancedScore = _scorePattern(
          field,
          centered.corners,
          enhanced: true,
          minimumSideFraction: 0.30,
        );
        final double centeredLegacyScore = _scorePattern(
          field,
          centered.corners,
          minimumSideFraction: 0.30,
        );
        final bool hasCenteredNodeLattice =
            centeredNodeScore >= 0.60 &&
            centeredNodeScore >= initialCenteredScore + 0.18 &&
            centeredEnhancedScore >= selectedEnhancedScore + 0.07 &&
            centeredLegacyScore >= 0.34;
        if (hasCenteredNodeLattice) {
          best = _ScoredCorners(centered.corners, centeredLegacyScore);
          markerReliability =
              0.55 * _normalize(centeredNodeScore, lower: 0.58, upper: 0.82) +
              0.25 *
                  _normalize(
                    centeredNodeScore - initialCenteredScore,
                    lower: 0.12,
                    upper: 0.35,
                  ) +
              0.20 *
                  _normalize(
                    centeredEnhancedScore - selectedEnhancedScore,
                    lower: 0.05,
                    upper: 0.18,
                  );
        }
      }
    }

    final List<double> seedScores =
        seeds
            .map((_ScoredCorners candidate) => candidate.score)
            .toList(growable: false)
          ..sort();
    final double seedMedian = seedScores[seedScores.length ~/ 2];
    final double decoyScore = _scorePattern(
      field,
      best.corners,
      patternScale: 0.90,
      minimumSideFraction: math.min(
        0.48,
        _minimumSideFraction(best.corners, field),
      ),
    );
    final double absoluteQuality = _normalize(
      best.score,
      lower: 0.30,
      upper: 0.82,
    );
    final double patternSeparation = _normalize(
      best.score - decoyScore,
      lower: 0.015,
      upper: 0.20,
    );
    final double searchImprovement = _normalize(
      best.score - seedMedian,
      lower: 0.02,
      upper: 0.24,
    );
    final double confidence = math.max(
      markerReliability,
      0.50 * absoluteQuality +
          0.35 * patternSeparation +
          0.15 * searchImprovement,
    );

    return BoardCornerDetection(
      corners: best.corners,
      confidence: confidence.clamp(0.0, 1.0),
      score: best.score,
    );
  }

  static img.Image _resizeForAnalysis(img.Image source) {
    final int largest = math.max(source.width, source.height);
    if (largest <= _maximumAnalysisDimension) {
      return source;
    }
    final double scale = _maximumAnalysisDimension / largest;
    return img.copyResize(
      source,
      width: math.max(1, (source.width * scale).round()),
      height: math.max(1, (source.height * scale).round()),
      interpolation: img.Interpolation.average,
    );
  }

  static List<_ScoredCorners> _createSeeds(_ImageField field) {
    const List<double> fillFractions = <double>[0.56, 0.68, 0.80, 0.91];
    const List<double> aspectRatios = <double>[0.82, 1.0, 1.18];
    const List<Offset> centers = <Offset>[
      Offset(0.50, 0.50),
      Offset(0.38, 0.50),
      Offset(0.44, 0.50),
      Offset(0.56, 0.50),
      Offset(0.62, 0.50),
      // Portrait screenshots commonly place the board above or below center.
      Offset(0.50, 0.32),
      Offset(0.50, 0.44),
      Offset(0.50, 0.56),
      Offset(0.50, 0.68),
    ];
    const List<double> angles = <double>[
      -0.40,
      -0.24,
      -0.12,
      0,
      0.12,
      0.24,
      0.40,
    ];

    final double shorterDimension = math
        .min(field.width, field.height)
        .toDouble();
    final List<_ScoredCorners> candidates = <_ScoredCorners>[];
    for (final double fill in fillFractions) {
      for (final double aspect in aspectRatios) {
        final double width = shorterDimension * fill * math.sqrt(aspect);
        final double height = shorterDimension * fill / math.sqrt(aspect);
        if (width > field.width * 0.96 || height > field.height * 0.96) {
          continue;
        }
        for (final Offset center in centers) {
          for (final double angle in angles) {
            final BoardImageCorners corners = _rotatedRectangle(
              center: Offset(center.dx * field.width, center.dy * field.height),
              width: width,
              height: height,
              angle: angle,
              imageWidth: field.width,
              imageHeight: field.height,
            );
            if (!corners.isValid) {
              continue;
            }
            candidates.add(
              _ScoredCorners(corners, _scorePattern(field, corners)),
            );
          }
        }
      }
    }

    if (candidates.isEmpty) {
      final BoardImageCorners fallback = BoardImageCorners.inset();
      candidates.add(_ScoredCorners(fallback, _scorePattern(field, fallback)));
    }
    return candidates;
  }

  static _ScoredCorners _refineSelectedCandidate(
    _ImageField field,
    _ScoredCorners selected,
  ) {
    const double maximumDistance = 0.075;
    const double seedStep = 12;
    const List<Offset> directions = <Offset>[
      Offset(-1, 0),
      Offset(1, 0),
      Offset(0, -1),
      Offset(0, 1),
      Offset(-1, -1),
      Offset(1, -1),
      Offset(1, 1),
      Offset(-1, 1),
    ];
    final List<_ScoredCorners> seeds = <_ScoredCorners>[
      _ScoredCorners(
        selected.corners,
        _scorePattern(field, selected.corners, enhanced: true),
      ),
    ];
    for (int cornerIndex = 0; cornerIndex < 4; cornerIndex++) {
      for (final Offset direction in directions) {
        final Offset current = selected.corners.points[cornerIndex];
        final BoardImageCorners corners = selected.corners.replace(
          cornerIndex,
          Offset(
            current.dx + direction.dx * seedStep / field.width,
            current.dy + direction.dy * seedStep / field.height,
          ),
        );
        if (!_isPlausible(corners, field) ||
            _maximumCornerDistance(corners, selected.corners) >
                maximumDistance) {
          continue;
        }
        seeds.add(
          _ScoredCorners(
            corners,
            _scorePattern(field, corners, enhanced: true),
          ),
        );
      }
    }
    seeds.sort(
      (_ScoredCorners first, _ScoredCorners second) =>
          second.score.compareTo(first.score),
    );
    _ScoredCorners refined = seeds.first;
    for (final _ScoredCorners seed in seeds.take(5)) {
      final _ScoredCorners candidate = _optimize(
        field,
        seed,
        enhanced: true,
        stepPixels: const <double>[6, 3, 1.5],
        anchor: selected.corners,
        maximumAnchorDistance: maximumDistance,
      );
      if (candidate.score > refined.score) {
        refined = candidate;
      }
    }
    final double selectedEnhancedScore = _scorePattern(
      field,
      selected.corners,
      enhanced: true,
    );
    if (refined.score <= selectedEnhancedScore + 0.08) {
      return selected;
    }
    final double legacyScore = _scorePattern(field, refined.corners);
    if (legacyScore < selected.score * 0.82) {
      return selected;
    }
    return _ScoredCorners(refined.corners, legacyScore);
  }

  static _ScoredCorners? _findCompactBoardCandidate(_ImageField field) {
    const List<double> fillFractions = <double>[0.34, 0.42, 0.50];
    const List<double> aspectRatios = <double>[0.82, 1.0, 1.18];
    const List<Offset> centers = <Offset>[
      Offset(0.50, 0.50),
      Offset(0.38, 0.50),
      Offset(0.62, 0.50),
      Offset(0.50, 0.32),
      Offset(0.50, 0.44),
      Offset(0.50, 0.56),
      Offset(0.50, 0.68),
    ];
    const List<double> angles = <double>[
      -0.40,
      -0.24,
      -0.12,
      0,
      0.12,
      0.24,
      0.40,
    ];
    final double shorterDimension = math
        .min(field.width, field.height)
        .toDouble();
    final List<_ScoredCorners> seeds = <_ScoredCorners>[];
    for (final double fill in fillFractions) {
      for (final double aspect in aspectRatios) {
        final double width = shorterDimension * fill * math.sqrt(aspect);
        final double height = shorterDimension * fill / math.sqrt(aspect);
        for (final Offset center in centers) {
          for (final double angle in angles) {
            final BoardImageCorners corners = _rotatedRectangle(
              center: Offset(center.dx * field.width, center.dy * field.height),
              width: width,
              height: height,
              angle: angle,
              imageWidth: field.width,
              imageHeight: field.height,
            );
            final double score = _scorePattern(
              field,
              corners,
              enhanced: true,
              minimumSideFraction: 0.30,
            );
            if (score > 0) {
              seeds.add(_ScoredCorners(corners, score));
            }
          }
        }
      }
    }
    if (seeds.isEmpty) {
      return null;
    }
    seeds.sort(
      (_ScoredCorners first, _ScoredCorners second) =>
          second.score.compareTo(first.score),
    );
    final List<_ScoredCorners> starts = <_ScoredCorners>[];
    for (final _ScoredCorners seed in seeds) {
      if (starts.every(
        (_ScoredCorners selected) =>
            _cornerDistance(seed.corners, selected.corners) > 0.035,
      )) {
        starts.add(seed);
      }
      if (starts.length == 6) {
        break;
      }
    }
    _ScoredCorners best = starts.first;
    for (final _ScoredCorners start in starts) {
      final _ScoredCorners optimized = _optimize(
        field,
        start,
        enhanced: true,
        minimumSideFraction: 0.30,
        stepPixels: const <double>[12, 6, 3, 1.5],
      );
      if (optimized.score > best.score) {
        best = optimized;
      }
    }
    return best;
  }

  static _ScoredCorners _refineCenteredNodeCandidate(
    _ImageField field,
    _ScoredCorners start,
  ) {
    const double maximumDistance = 0.05;
    const List<Offset> directions = <Offset>[
      Offset(-1, 0),
      Offset(1, 0),
      Offset(0, -1),
      Offset(0, 1),
      Offset(-1, -1),
      Offset(1, -1),
      Offset(1, 1),
      Offset(-1, 1),
    ];
    final BoardImageCorners anchor = start.corners;
    _ScoredCorners best = _ScoredCorners(
      start.corners,
      _scoreCenteredNodeCandidate(field, start.corners),
    );
    for (final double step in const <double>[6, 3, 1.5, 0.75]) {
      for (int pass = 0; pass < 3; pass++) {
        bool improved = false;
        for (int cornerIndex = 0; cornerIndex < 4; cornerIndex++) {
          _ScoredCorners cornerBest = best;
          for (final Offset direction in directions) {
            final Offset current = best.corners.points[cornerIndex];
            final BoardImageCorners candidate = best.corners.replace(
              cornerIndex,
              Offset(
                current.dx + direction.dx * step / field.width,
                current.dy + direction.dy * step / field.height,
              ),
            );
            if (!_isPlausible(candidate, field, minimumSideFraction: 0.30) ||
                _maximumCornerDistance(candidate, anchor) > maximumDistance) {
              continue;
            }
            final double score = _scoreCenteredNodeCandidate(field, candidate);
            if (score > cornerBest.score + 1e-6) {
              cornerBest = _ScoredCorners(candidate, score);
            }
          }
          if (cornerBest.score > best.score + 1e-6) {
            best = cornerBest;
            improved = true;
          }
        }
        if (!improved) {
          break;
        }
      }
    }
    return best;
  }

  static double _scoreCenteredNodeCandidate(
    _ImageField field,
    BoardImageCorners corners,
  ) {
    // Keep faint line topology in the objective so circular decorations
    // cannot move an otherwise coherent node lattice away from the board.
    return _scoreCenteredNodePattern(field, _ProjectiveMap(corners)) +
        0.75 *
            _scorePattern(
              field,
              corners,
              enhanced: true,
              minimumSideFraction: 0.30,
            );
  }

  static List<_BoardSegment> _createSegments() {
    final List<_BoardSegment> segments = <_BoardSegment>[];
    const List<double> ringWeights = <double>[1.10, 1.0, 0.78];
    for (int ring = 0; ring < 3; ring++) {
      for (int point = 0; point < 8; point++) {
        segments.add(
          _BoardSegment(
            _boardPoints[ring * 8 + point],
            _boardPoints[ring * 8 + (point + 1) % 8],
            ringWeights[ring],
          ),
        );
      }
    }
    for (final int point in <int>[1, 3, 5, 7]) {
      segments
        ..add(_BoardSegment(_boardPoints[point], _boardPoints[8 + point], 0.85))
        ..add(
          _BoardSegment(
            _boardPoints[8 + point],
            _boardPoints[16 + point],
            0.72,
          ),
        );
    }
    return List<_BoardSegment>.unmodifiable(segments);
  }

  static BoardImageCorners _rotatedRectangle({
    required Offset center,
    required double width,
    required double height,
    required double angle,
    required int imageWidth,
    required int imageHeight,
  }) {
    final double cosine = math.cos(angle);
    final double sine = math.sin(angle);

    Offset rotate(double x, double y) => Offset(
      (center.dx + x * cosine - y * sine) / imageWidth,
      (center.dy + x * sine + y * cosine) / imageHeight,
    );

    return BoardImageCorners(
      topLeft: rotate(-width / 2, -height / 2),
      topRight: rotate(width / 2, -height / 2),
      bottomRight: rotate(width / 2, height / 2),
      bottomLeft: rotate(-width / 2, height / 2),
    );
  }

  static _ScoredCorners _optimize(
    _ImageField field,
    _ScoredCorners start, {
    bool enhanced = false,
    double minimumSideFraction = 0.48,
    List<double> stepPixels = const <double>[24, 12, 6, 3, 1.5],
    BoardImageCorners? anchor,
    double maximumAnchorDistance = double.infinity,
  }) {
    _ScoredCorners best = start;
    const List<Offset> directions = <Offset>[
      Offset(-1, 0),
      Offset(1, 0),
      Offset(0, -1),
      Offset(0, 1),
      Offset(-1, -1),
      Offset(1, -1),
      Offset(1, 1),
      Offset(-1, 1),
    ];

    for (final double step in stepPixels) {
      for (int pass = 0; pass < 2; pass++) {
        bool improved = false;
        for (int cornerIndex = 0; cornerIndex < 4; cornerIndex++) {
          _ScoredCorners cornerBest = best;
          for (final Offset direction in directions) {
            final Offset current = best.corners.points[cornerIndex];
            final Offset moved = Offset(
              current.dx + direction.dx * step / field.width,
              current.dy + direction.dy * step / field.height,
            );
            final BoardImageCorners candidate = best.corners.replace(
              cornerIndex,
              moved,
            );
            if (!_isPlausible(
                  candidate,
                  field,
                  minimumSideFraction: minimumSideFraction,
                ) ||
                (anchor != null &&
                    _maximumCornerDistance(candidate, anchor) >
                        maximumAnchorDistance)) {
              continue;
            }
            final double score = _scorePattern(
              field,
              candidate,
              enhanced: enhanced,
              minimumSideFraction: minimumSideFraction,
            );
            if (score > cornerBest.score + 1e-6) {
              cornerBest = _ScoredCorners(candidate, score);
            }
          }
          if (cornerBest.score > best.score + 1e-6) {
            best = cornerBest;
            improved = true;
          }
        }
        if (!improved) {
          break;
        }
      }
    }

    if (enhanced) {
      // Moving both corners of one side together lets the refinement reject a
      // nearby parallel page or frame edge without distorting the other three
      // already aligned sides.
      for (final double step in stepPixels) {
        for (int pass = 0; pass < 2; pass++) {
          bool improved = false;
          for (int side = 0; side < 4; side++) {
            _ScoredCorners sideBest = best;
            for (final double direction in const <double>[-1, 1]) {
              final BoardImageCorners candidate = _moveSide(
                best.corners,
                side,
                direction * step,
                field,
              );
              if (!_isPlausible(
                    candidate,
                    field,
                    minimumSideFraction: minimumSideFraction,
                  ) ||
                  (anchor != null &&
                      _maximumCornerDistance(candidate, anchor) >
                          maximumAnchorDistance)) {
                continue;
              }
              final double score = _scorePattern(
                field,
                candidate,
                enhanced: true,
                minimumSideFraction: minimumSideFraction,
              );
              if (score > sideBest.score + 1e-6) {
                sideBest = _ScoredCorners(candidate, score);
              }
            }
            if (sideBest.score > best.score + 1e-6) {
              best = sideBest;
              improved = true;
            }
          }
          if (!improved) {
            break;
          }
        }
      }
    }

    // Coordinate descent cannot expand two opposite sides simultaneously.
    // Refine the already optimized result with paired normal movements while
    // preserving the original solution whenever no higher score is found.
    for (final double step in stepPixels) {
      for (int pass = 0; pass < 2; pass++) {
        bool improved = false;
        for (final List<int> oppositeSides in const <List<int>>[
          <int>[0, 2],
          <int>[1, 3],
        ]) {
          _ScoredCorners pairBest = best;
          for (final double direction in const <double>[-1, 1]) {
            final BoardImageCorners candidate = _moveOppositeSides(
              best.corners,
              oppositeSides.first,
              oppositeSides.last,
              direction * step,
              field,
            );
            if (!_isPlausible(
                  candidate,
                  field,
                  minimumSideFraction: minimumSideFraction,
                ) ||
                (anchor != null &&
                    _maximumCornerDistance(candidate, anchor) >
                        maximumAnchorDistance)) {
              continue;
            }
            final double score = _scorePattern(
              field,
              candidate,
              enhanced: enhanced,
              minimumSideFraction: minimumSideFraction,
            );
            if (score > pairBest.score + 1e-6) {
              pairBest = _ScoredCorners(candidate, score);
            }
          }
          if (pairBest.score > best.score + 1e-6) {
            best = pairBest;
            improved = true;
          }
        }
        if (!improved) {
          break;
        }
      }
    }
    return best;
  }

  static BoardImageCorners _moveSide(
    BoardImageCorners corners,
    int side,
    double distance,
    _ImageField field,
  ) {
    assert(side >= 0 && side < 4);
    final List<Offset> points = corners.points;
    final int next = (side + 1) % points.length;
    final Offset start = Offset(
      points[side].dx * field.width,
      points[side].dy * field.height,
    );
    final Offset end = Offset(
      points[next].dx * field.width,
      points[next].dy * field.height,
    );
    final Offset tangent = end - start;
    if (tangent.distance < 1) {
      return corners;
    }
    final Offset inwardNormal = Offset(
      -tangent.dy / tangent.distance,
      tangent.dx / tangent.distance,
    );
    final Offset movement = Offset(
      inwardNormal.dx * distance / field.width,
      inwardNormal.dy * distance / field.height,
    );
    points[side] += movement;
    points[next] += movement;
    return BoardImageCorners(
      topLeft: points[0],
      topRight: points[1],
      bottomRight: points[2],
      bottomLeft: points[3],
    );
  }

  static BoardImageCorners _moveOppositeSides(
    BoardImageCorners corners,
    int firstSide,
    int secondSide,
    double distance,
    _ImageField field,
  ) {
    assert(firstSide >= 0 && firstSide < 4);
    assert(secondSide >= 0 && secondSide < 4);
    final List<Offset> points = corners.points;

    for (final int side in <int>[firstSide, secondSide]) {
      final int next = (side + 1) % points.length;
      final Offset start = Offset(
        points[side].dx * field.width,
        points[side].dy * field.height,
      );
      final Offset end = Offset(
        points[next].dx * field.width,
        points[next].dy * field.height,
      );
      final Offset tangent = end - start;
      if (tangent.distance < 1) {
        return corners;
      }
      final Offset inwardNormal = Offset(
        -tangent.dy / tangent.distance,
        tangent.dx / tangent.distance,
      );
      final Offset movement = Offset(
        inwardNormal.dx * distance / field.width,
        inwardNormal.dy * distance / field.height,
      );
      points[side] += movement;
      points[next] += movement;
    }

    return BoardImageCorners(
      topLeft: points[0],
      topRight: points[1],
      bottomRight: points[2],
      bottomLeft: points[3],
    );
  }

  static bool _isPlausible(
    BoardImageCorners corners,
    _ImageField field, {
    double minimumSideFraction = 0.48,
  }) {
    if (!corners.isValid) {
      return false;
    }
    final List<Offset> pixels = corners.points
        .map(
          (Offset point) =>
              Offset(point.dx * field.width, point.dy * field.height),
        )
        .toList(growable: false);
    final List<double> sides = <double>[
      for (int index = 0; index < 4; index++)
        (pixels[(index + 1) % 4] - pixels[index]).distance,
    ];
    final double minimumSide = sides.reduce(math.min);
    final double maximumSide = sides.reduce(math.max);
    final Offset? diagonalFractions = _diagonalIntersectionFractions(corners);
    return diagonalFractions != null &&
        diagonalFractions.dx >= 0.18 &&
        diagonalFractions.dx <= 0.82 &&
        diagonalFractions.dy >= 0.18 &&
        diagonalFractions.dy <= 0.82 &&
        minimumSide >=
            math.min(field.width, field.height) * minimumSideFraction &&
        maximumSide / minimumSide <= 3.5;
  }

  static double _scorePattern(
    _ImageField field,
    BoardImageCorners corners, {
    double patternScale = 1,
    bool enhanced = false,
    double minimumSideFraction = 0.48,
  }) {
    if (!_isPlausible(
      corners,
      field,
      minimumSideFraction: minimumSideFraction,
    )) {
      return 0;
    }

    final _ProjectiveMap transform = _ProjectiveMap(corners);
    double weightedScore = 0;
    double totalWeight = 0;
    final List<double> segmentScores = <double>[];
    final List<double> segmentSignedContrasts = <double>[];
    final List<double> outerExtentScores = <double>[];
    for (
      int segmentIndex = 0;
      segmentIndex < _segments.length;
      segmentIndex++
    ) {
      final _BoardSegment segment = _segments[segmentIndex];
      final Offset start = _scalePatternPoint(segment.start, patternScale);
      final Offset end = _scalePatternPoint(segment.end, patternScale);
      final Offset sourceStart = transform.map(start);
      final Offset sourceEnd = transform.map(end);
      final Offset pixelStart = Offset(
        sourceStart.dx * (field.width - 1),
        sourceStart.dy * (field.height - 1),
      );
      final Offset pixelEnd = Offset(
        sourceEnd.dx * (field.width - 1),
        sourceEnd.dy * (field.height - 1),
      );
      final Offset tangent = pixelEnd - pixelStart;
      if (tangent.distance < 8) {
        continue;
      }
      final Offset normal = Offset(
        -tangent.dy / tangent.distance,
        tangent.dx / tangent.distance,
      );
      final List<double> edgeResponses = <double>[];
      final List<double> signedContrasts = <double>[];
      for (final double position in _lineSamplePositions) {
        final Offset canonical = Offset.lerp(start, end, position)!;
        final Offset mapped = transform.map(canonical);
        final Offset pixel = Offset(
          mapped.dx * (field.width - 1),
          mapped.dy * (field.height - 1),
        );
        final _LineEvidence evidence = _lineEvidence(field, pixel, normal);
        edgeResponses.add(evidence.directionalEdge);
        signedContrasts.add(evidence.signedContrast);
      }
      if (segmentIndex < 8) {
        for (final double position in const <double>[0.12, 0.88]) {
          final Offset canonical = Offset.lerp(start, end, position)!;
          final Offset mapped = transform.map(canonical);
          final Offset pixel = Offset(
            mapped.dx * (field.width - 1),
            mapped.dy * (field.height - 1),
          );
          final _LineEvidence evidence = _lineEvidence(field, pixel, normal);
          outerExtentScores.add(
            0.20 * evidence.directionalEdge +
                0.85 * evidence.signedContrast.abs(),
          );
        }
      }
      edgeResponses.sort();

      double middleEdge = 0;
      for (int index = 1; index < edgeResponses.length - 1; index++) {
        middleEdge += edgeResponses[index];
      }
      middleEdge /= edgeResponses.length - 2;
      final double edgeContinuity = 0.64 * edgeResponses[1] + 0.36 * middleEdge;

      final double meanSignedContrast = _mean(signedContrasts);
      final double meanAbsoluteContrast = _mean(
        signedContrasts
            .map((double value) => value.abs())
            .toList(growable: false),
      );
      final double polarityConsistency =
          meanSignedContrast.abs() / (meanAbsoluteContrast + 1e-6);
      final double contrastContinuity =
          meanSignedContrast.abs().clamp(0.0, 2.0) *
          (0.45 + 0.55 * polarityConsistency);
      final double segmentScore =
          0.20 * edgeContinuity + 0.85 * contrastContinuity;
      segmentScores.add(segmentScore);
      segmentSignedContrasts.add(meanSignedContrast);
      weightedScore += segmentScore * segment.weight;
      totalWeight += segment.weight;
    }
    if (totalWeight == 0 || segmentScores.length != _segments.length) {
      return 0;
    }

    final List<double> groupScores = <double>[
      _mean(segmentScores.sublist(0, 8)),
      _mean(segmentScores.sublist(8, 16)),
      _mean(segmentScores.sublist(16, 24)),
      _mean(segmentScores.sublist(24, 32)),
    ]..sort();
    final double continuityScore =
        0.76 * (weightedScore / totalWeight) + 0.24 * groupScores[1];
    final double globalSignedContrast = _mean(segmentSignedContrasts);
    final double globalAbsoluteContrast = _mean(
      segmentSignedContrasts
          .map((double value) => value.abs())
          .toList(growable: false),
    );
    final double globalPolarityConsistency =
        globalSignedContrast.abs() / (globalAbsoluteContrast + 1e-6);
    final double polarityWeightedContinuity =
        continuityScore * (0.35 + 0.65 * globalPolarityConsistency);
    outerExtentScores.sort();
    final double outerExtentScore = _mean(
      outerExtentScores.sublist(2, outerExtentScores.length - 2),
    );
    final double nodePatternScore = _scoreNodePattern(field, transform);
    final double topologyScore =
        0.55 * polarityWeightedContinuity +
        0.30 * outerExtentScore +
        0.15 * nodePatternScore;
    final Offset diagonalFractions = _diagonalIntersectionFractions(corners)!;
    final double diagonalImbalance = math.max(
      (diagonalFractions.dx - 0.5).abs(),
      (diagonalFractions.dy - 0.5).abs(),
    );
    final double geometryWeight =
        1 - 0.35 * _normalize(diagonalImbalance, lower: 0.10, upper: 0.32);
    return (enhanced ? topologyScore : continuityScore) * geometryWeight;
  }

  static double _minimumSideFraction(
    BoardImageCorners corners,
    _ImageField field,
  ) {
    final List<Offset> pixels = corners.points
        .map(
          (Offset point) =>
              Offset(point.dx * field.width, point.dy * field.height),
        )
        .toList(growable: false);
    double minimumSide = double.infinity;
    for (int index = 0; index < pixels.length; index++) {
      minimumSide = math.min(
        minimumSide,
        (pixels[(index + 1) % pixels.length] - pixels[index]).distance,
      );
    }
    return minimumSide / math.min(field.width, field.height);
  }

  static double _scoreNodePattern(_ImageField field, _ProjectiveMap transform) {
    const int angleSamples = 16;
    const List<double> radiusScales = <double>[0.018, 0.032, 0.050];
    final List<double> nodeScores = <double>[];

    for (final Offset canonicalPoint in _boardPoints) {
      int edgeAngles = 0;
      for (int angleIndex = 0; angleIndex < angleSamples; angleIndex++) {
        final double angle = angleIndex * 2 * math.pi / angleSamples;
        final Offset direction = Offset(math.cos(angle), math.sin(angle));
        double strongestEdge = 0;
        for (final double radius in radiusScales) {
          final Offset mapped = transform.map(
            canonicalPoint + direction * radius,
          );
          strongestEdge = math.max(
            strongestEdge,
            field.edgeMagnitudeAt(
              mapped.dx * (field.width - 1),
              mapped.dy * (field.height - 1),
            ),
          );
        }
        if (strongestEdge >= 0.32) {
          edgeAngles++;
        }
      }
      nodeScores.add(edgeAngles / angleSamples);
    }

    final List<double> ringScores = <double>[
      _mean(nodeScores.sublist(0, 8)),
      _mean(nodeScores.sublist(8, 16)),
      _mean(nodeScores.sublist(16, 24)),
    ]..sort();
    return 0.65 * ringScores[0] + 0.35 * ringScores[1];
  }

  static double _scoreCenteredNodePattern(
    _ImageField field,
    _ProjectiveMap transform,
  ) {
    const int angleSamples = 16;
    const List<double> radiusScales = <double>[
      0.018,
      0.025,
      0.033,
      0.043,
      0.055,
      0.068,
    ];
    final List<double> nodeScores = <double>[];
    for (final Offset canonicalPoint in _boardPoints) {
      double bestRadiusScore = 0;
      for (final double radius in radiusScales) {
        final List<double> responses = <double>[];
        for (int angleIndex = 0; angleIndex < angleSamples; angleIndex++) {
          final double angle = angleIndex * 2 * math.pi / angleSamples;
          final Offset canonicalDirection = Offset(
            math.cos(angle),
            math.sin(angle),
          );
          final Offset mappedCenter = transform.map(canonicalPoint);
          final Offset mapped = transform.map(
            canonicalPoint + canonicalDirection * radius,
          );
          final Offset radial = Offset(
            (mapped.dx - mappedCenter.dx) * (field.width - 1),
            (mapped.dy - mappedCenter.dy) * (field.height - 1),
          );
          if (radial.distance < 1e-6) {
            responses.add(0);
            continue;
          }
          // A centered hole or peg has edge gradients normal to its radial
          // spokes. Plain line crossings and off-center circles do not.
          responses.add(
            field.directionalEdgeAt(
              mapped.dx * (field.width - 1),
              mapped.dy * (field.height - 1),
              radial / radial.distance,
            ),
          );
        }
        responses.sort();
        final int supportedAngles = responses
            .where((double response) => response >= 0.28)
            .length;
        final double angularCoverage = supportedAngles / angleSamples;
        final double lowerQuartileStrength = _normalize(
          responses[angleSamples ~/ 4],
          lower: 0.10,
          upper: 0.55,
        );
        bestRadiusScore = math.max(
          bestRadiusScore,
          0.65 * lowerQuartileStrength + 0.35 * angularCoverage,
        );
      }
      nodeScores.add(bestRadiusScore);
    }
    final List<double> ringScores = <double>[
      _mean(nodeScores.sublist(0, 8)),
      _mean(nodeScores.sublist(8, 16)),
      _mean(nodeScores.sublist(16, 24)),
    ]..sort();
    nodeScores.sort();
    // Score the weakest nodes and rings so a few pieces or decorations cannot
    // masquerade as the complete 24-point Mill topology.
    return 0.55 * _mean(nodeScores.sublist(0, 20)) +
        0.30 * ringScores[0] +
        0.15 * ringScores[1];
  }

  static Offset _scalePatternPoint(Offset point, double scale) =>
      Offset(0.5 + (point.dx - 0.5) * scale, 0.5 + (point.dy - 0.5) * scale);

  static _LineEvidence _lineEvidence(
    _ImageField field,
    Offset point,
    Offset normal,
  ) {
    double strongestEdge = 0;
    for (int offset = -3; offset <= 3; offset++) {
      strongestEdge = math.max(
        strongestEdge,
        field.directionalEdgeAt(
          point.dx + normal.dx * offset,
          point.dy + normal.dy * offset,
          normal,
        ),
      );
    }
    final double distantEdge =
        (field.directionalEdgeAt(
              point.dx - normal.dx * 7,
              point.dy - normal.dy * 7,
              normal,
            ) +
            field.directionalEdgeAt(
              point.dx + normal.dx * 7,
              point.dy + normal.dy * 7,
              normal,
            )) /
        2;
    final double edgeResponse = math.max(0, strongestEdge - 0.30 * distantEdge);

    final double lineLuma =
        (field.lumaAt(point.dx - normal.dx, point.dy - normal.dy) +
            field.lumaAt(point.dx, point.dy) +
            field.lumaAt(point.dx + normal.dx, point.dy + normal.dy)) /
        3;
    final double negativeSideLuma =
        (field.lumaAt(point.dx - normal.dx * 5, point.dy - normal.dy * 5) +
            field.lumaAt(point.dx - normal.dx * 7, point.dy - normal.dy * 7)) /
        2;
    final double positiveSideLuma =
        (field.lumaAt(point.dx + normal.dx * 5, point.dy + normal.dy * 5) +
            field.lumaAt(point.dx + normal.dx * 7, point.dy + normal.dy * 7)) /
        2;
    final double darkRidge = math.min(
      negativeSideLuma - lineLuma,
      positiveSideLuma - lineLuma,
    );
    final double lightRidge = math.min(
      lineLuma - negativeSideLuma,
      lineLuma - positiveSideLuma,
    );
    final double signedRidge = darkRidge >= lightRidge
        ? math.max(0.0, darkRidge)
        : -math.max(0.0, lightRidge);
    return _LineEvidence(
      edgeResponse.clamp(0.0, 2.0),
      (signedRidge / field.contrastScale).clamp(-2.0, 2.0),
    );
  }

  static double _cornerDistance(
    BoardImageCorners first,
    BoardImageCorners second,
  ) {
    double total = 0;
    for (int index = 0; index < 4; index++) {
      total += (first.points[index] - second.points[index]).distance;
    }
    return total / 4;
  }

  static double _maximumCornerDistance(
    BoardImageCorners first,
    BoardImageCorners second,
  ) {
    double maximum = 0;
    for (int index = 0; index < 4; index++) {
      maximum = math.max(
        maximum,
        (first.points[index] - second.points[index]).distance,
      );
    }
    return maximum;
  }

  static Offset? _diagonalIntersectionFractions(BoardImageCorners corners) {
    final Offset firstStart = corners.topLeft;
    final Offset firstDirection = corners.bottomRight - firstStart;
    final Offset secondStart = corners.topRight;
    final Offset secondDirection = corners.bottomLeft - secondStart;
    final double denominator = _cross(firstDirection, secondDirection);
    if (denominator.abs() < 1e-9) {
      return null;
    }
    final Offset betweenStarts = secondStart - firstStart;
    return Offset(
      _cross(betweenStarts, secondDirection) / denominator,
      _cross(betweenStarts, firstDirection) / denominator,
    );
  }

  static double _cross(Offset first, Offset second) =>
      first.dx * second.dy - first.dy * second.dx;

  static double _mean(List<double> values) =>
      values.reduce((double first, double second) => first + second) /
      values.length;

  static double _normalize(
    double value, {
    required double lower,
    required double upper,
  }) => ((value - lower) / (upper - lower)).clamp(0.0, 1.0);
}

class _BoardSegment {
  const _BoardSegment(this.start, this.end, this.weight);

  final Offset start;
  final Offset end;
  final double weight;
}

class _ScoredCorners {
  const _ScoredCorners(this.corners, this.score);

  final BoardImageCorners corners;
  final double score;
}

class _LineEvidence {
  const _LineEvidence(this.directionalEdge, this.signedContrast);

  final double directionalEdge;
  final double signedContrast;
}

class _ImageField {
  _ImageField({
    required this.width,
    required this.height,
    required this.luma,
    required this.gradientX,
    required this.gradientY,
    required this.contrastScale,
  });

  factory _ImageField.fromImage(img.Image image) {
    final int width = image.width;
    final int height = image.height;
    final Float32List luma = Float32List(width * height);
    int pixelIndex = 0;
    for (final img.Pixel pixel in image) {
      luma[pixelIndex++] =
          0.299 * pixel.r.toDouble() +
          0.587 * pixel.g.toDouble() +
          0.114 * pixel.b.toDouble();
    }

    final Float32List rawGradientX = Float32List(width * height);
    final Float32List rawGradientY = Float32List(width * height);
    final List<double> edgeSamples = <double>[];
    for (int y = 1; y < height - 1; y++) {
      for (int x = 1; x < width - 1; x++) {
        final int index = y * width + x;
        final double gx =
            -luma[index - width - 1] +
            luma[index - width + 1] -
            2 * luma[index - 1] +
            2 * luma[index + 1] -
            luma[index + width - 1] +
            luma[index + width + 1];
        final double gy =
            -luma[index - width - 1] -
            2 * luma[index - width] -
            luma[index - width + 1] +
            luma[index + width - 1] +
            2 * luma[index + width] +
            luma[index + width + 1];
        final double scaledX = gx / 8;
        final double scaledY = gy / 8;
        final double magnitude = scaledX.abs() + scaledY.abs();
        rawGradientX[index] = scaledX;
        rawGradientY[index] = scaledY;
        if (magnitude > 0.5) {
          edgeSamples.add(magnitude);
        }
      }
    }
    edgeSamples.sort();
    final double edgeScale = edgeSamples.isEmpty
        ? 8
        : math.max(
            8,
            edgeSamples[(edgeSamples.length * 0.90).floor().clamp(
              0,
              edgeSamples.length - 1,
            )],
          );
    final Float32List gradientX = Float32List(width * height);
    final Float32List gradientY = Float32List(width * height);
    for (int index = 0; index < rawGradientX.length; index++) {
      gradientX[index] = (rawGradientX[index] / edgeScale).clamp(-2.0, 2.0);
      gradientY[index] = (rawGradientY[index] / edgeScale).clamp(-2.0, 2.0);
    }

    double mean = 0;
    for (final double value in luma) {
      mean += value;
    }
    mean /= luma.length;
    double variance = 0;
    for (final double value in luma) {
      final double difference = value - mean;
      variance += difference * difference;
    }
    final double standardDeviation = math.sqrt(variance / luma.length);

    return _ImageField(
      width: width,
      height: height,
      luma: luma,
      gradientX: gradientX,
      gradientY: gradientY,
      contrastScale: math.max(18, standardDeviation * 0.55),
    );
  }

  final int width;
  final int height;
  final Float32List luma;
  final Float32List gradientX;
  final Float32List gradientY;
  final double contrastScale;

  double directionalEdgeAt(double x, double y, Offset normal) {
    final double horizontal = _sample(gradientX, x, y);
    final double vertical = _sample(gradientY, x, y);
    return (horizontal * normal.dx + vertical * normal.dy).abs();
  }

  double edgeMagnitudeAt(double x, double y) {
    final double horizontal = _sample(gradientX, x, y);
    final double vertical = _sample(gradientY, x, y);
    return horizontal.abs() + vertical.abs();
  }

  double lumaAt(double x, double y) => _sample(
    luma,
    x.clamp(0.0, (width - 1).toDouble()),
    y.clamp(0.0, (height - 1).toDouble()),
  );

  double _sample(Float32List values, double x, double y) {
    if (x < 0 || y < 0 || x > width - 1 || y > height - 1) {
      return 0;
    }
    final int left = x.floor();
    final int top = y.floor();
    final int right = math.min(left + 1, width - 1);
    final int bottom = math.min(top + 1, height - 1);
    final double horizontal = x - left;
    final double vertical = y - top;
    final double topValue =
        values[top * width + left] * (1 - horizontal) +
        values[top * width + right] * horizontal;
    final double bottomValue =
        values[bottom * width + left] * (1 - horizontal) +
        values[bottom * width + right] * horizontal;
    return topValue * (1 - vertical) + bottomValue * vertical;
  }
}

/// Projective mapping from canonical board coordinates into the source image.
class _ProjectiveMap {
  _ProjectiveMap(BoardImageCorners corners) {
    final Offset topLeft = corners.topLeft;
    final Offset topRight = corners.topRight;
    final Offset bottomRight = corners.bottomRight;
    final Offset bottomLeft = corners.bottomLeft;
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

  Offset map(Offset point) {
    final double denominator = _g * point.dx + _h * point.dy + 1;
    return Offset(
      (_a * point.dx + _b * point.dy + _c) / denominator,
      (_d * point.dx + _e * point.dy + _f) / denominator,
    );
  }
}
