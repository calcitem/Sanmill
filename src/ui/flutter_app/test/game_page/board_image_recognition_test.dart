// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sanmill/game_page/services/board_corner_detector.dart';
import 'package:sanmill/game_page/services/board_image_recognition.dart';
import 'package:sanmill/game_page/services/board_recognition_classifier.dart';
import 'package:sanmill/game_page/services/board_recognition_geometry.dart';
import 'package:sanmill/game_page/services/mill.dart';

const String _capturedUiSamplePath =
    'test/game_page/fixtures/board_recognition/'
    'outlined_white_pieces_on_bright_board.jpg';
const BoardImageCorners _capturedUiSampleCorners = BoardImageCorners(
  topLeft: Offset(57 / 590, 308 / 1279),
  topRight: Offset(533 / 590, 308 / 1279),
  bottomRight: Offset(533 / 590, 784 / 1279),
  bottomLeft: Offset(57 / 590, 784 / 1279),
);
const Set<int> _capturedBlackPieces = <int>{1, 5, 9, 15, 18, 19, 20, 22};
const Set<int> _capturedWhitePieces = <int>{2, 4, 8, 11, 13, 14, 21, 23};
const String _outlinedNodeSamplePath =
    'test/game_page/fixtures/board_recognition/'
    'outlined_empty_nodes_on_gray_board.jpg';
const String _crowdedOutlinedNodeSamplePath =
    'test/game_page/fixtures/board_recognition/'
    'crowded_ring_pieces_with_outlined_empty_nodes.jpg';
const String _boardAboveUiCardsSamplePath =
    'test/game_page/fixtures/board_recognition/'
    'board_above_ui_cards.jpg';
const BoardImageCorners _boardAboveUiCardsCorners = BoardImageCorners(
  topLeft: Offset(84 / 591, 215 / 1280),
  topRight: Offset(507 / 591, 215 / 1280),
  bottomRight: Offset(507 / 591, 640 / 1280),
  bottomLeft: Offset(84 / 591, 640 / 1280),
);
const Set<int> _boardAboveUiCardsBlackPieces = <int>{12, 13, 15};
const Set<int> _boardAboveUiCardsWhitePieces = <int>{8, 9, 10, 11, 23};
const String _nestedRingSamplePath =
    'test/game_page/fixtures/board_recognition/'
    'nested_ring_pieces_on_gray_board.jpg';
const String _sparseTexturedPieceSamplePath =
    'test/game_page/fixtures/board_recognition/'
    'sparse_textured_pieces_on_wood_board.jpg';
const BoardImageCorners _sparseTexturedPieceSampleCorners = BoardImageCorners(
  topLeft: Offset(77 / 1023, 77 / 1023),
  topRight: Offset(947 / 1023, 77 / 1023),
  bottomRight: Offset(947 / 1023, 947 / 1023),
  bottomLeft: Offset(77 / 1023, 947 / 1023),
);
const String _numberedOuterBorderSamplePath =
    'test/game_page/fixtures/board_recognition/'
    'numbered_pieces_overlapping_outer_border.jpg';
const BoardImageCorners _numberedOuterBorderSampleCorners = BoardImageCorners(
  topLeft: Offset(77 / 1023, 76 / 1023),
  topRight: Offset(946 / 1023, 76 / 1023),
  bottomRight: Offset(946 / 1023, 944 / 1023),
  bottomLeft: Offset(77 / 1023, 944 / 1023),
);
const String _twoToneWoodSamplePath =
    'test/game_page/fixtures/board_recognition/'
    'two_tone_wood_texture_pieces.jpg';
const String _outerEdgePieceSamplePath =
    'test/game_page/fixtures/board_recognition/'
    'pieces_touching_all_four_outer_edges.jpg';
const BoardImageCorners _outerEdgePieceSampleCorners = BoardImageCorners(
  topLeft: Offset(50 / 686, 51 / 685),
  topRight: Offset(635 / 686, 51 / 685),
  bottomRight: Offset(635 / 686, 634 / 685),
  bottomLeft: Offset(50 / 686, 634 / 685),
);
const String _grayRingTimerSamplePath =
    'test/game_page/fixtures/board_recognition/'
    'gray_ring_pieces_with_center_timer.jpg';
const String _perspectivePhysicalPieceSamplePath =
    'test/game_page/fixtures/board_recognition/'
    'perspective_physical_concentric_pieces.jpg';
const String _matchingWoodPieceSamplePath =
    'test/game_page/fixtures/board_recognition/'
    'wood_pieces_matching_board_color.jpg';
const BoardImageCorners _matchingWoodPieceSampleCorners = BoardImageCorners(
  topLeft: Offset(294 / 960, 70 / 540),
  topRight: Offset(675 / 960, 64 / 540),
  bottomRight: Offset(742 / 960, 452 / 540),
  bottomLeft: Offset(239 / 960, 452 / 540),
);
const String _pageEdgeSamplePath =
    'test/game_page/fixtures/board_recognition/'
    'outer_square_near_page_edges.jpg';
const BoardImageCorners _pageEdgeSampleCorners = BoardImageCorners(
  topLeft: Offset(82 / 1072, 275 / 1440),
  topRight: Offset(851 / 1072, 283 / 1440),
  bottomRight: Offset(853 / 1072, 1041 / 1440),
  bottomLeft: Offset(87 / 1072, 1048 / 1440),
);
const String _octagonalPlaqueSamplePath =
    'test/game_page/fixtures/board_recognition/'
    'small_board_inside_octagonal_plaque.jpg';
const BoardImageCorners _octagonalPlaqueSampleCorners = BoardImageCorners(
  topLeft: Offset(234 / 640, 106 / 424),
  topRight: Offset(379 / 640, 106 / 424),
  bottomRight: Offset(379 / 640, 254 / 424),
  bottomLeft: Offset(233 / 640, 254 / 424),
);
const String _offCenterSmallBoardSamplePath =
    'test/game_page/fixtures/board_recognition/'
    'off_center_small_board_beside_game_box.jpg';
const BoardImageCorners _offCenterSmallBoardSampleCorners = BoardImageCorners(
  topLeft: Offset(0.476, 0.226),
  topRight: Offset(0.760, 0.226),
  bottomRight: Offset(0.760, 0.719),
  bottomLeft: Offset(0.478, 0.719),
);
const String _physicalHoleBoardSamplePath =
    'test/game_page/fixtures/board_recognition/'
    'physical_hole_board_on_patterned_background.jpg';
const BoardImageCorners _physicalHoleBoardSampleCorners = BoardImageCorners(
  topLeft: Offset(0.300, 0.373),
  topRight: Offset(0.643, 0.374),
  bottomRight: Offset(0.654, 0.640),
  bottomLeft: Offset(0.310, 0.637),
);
const Set<int> _nestedRingBlackPieces = <int>{10, 13, 14, 23};
const Set<int> _nestedRingWhitePieces = <int>{5, 7, 9, 11, 12};
const Set<int> _sparseTexturedPieceBlackPieces = <int>{13};
const Set<int> _sparseTexturedPieceWhitePieces = <int>{9, 11};
const Set<int> _numberedOuterBorderBlackPieces = <int>{
  3,
  5,
  12,
  13,
  15,
  16,
  20,
};
const Set<int> _numberedOuterBorderWhitePieces = <int>{
  4,
  6,
  8,
  9,
  10,
  11,
  22,
  23,
};
const Set<int> _twoToneWoodBlackPieces = <int>{8, 9, 11, 17, 21, 22};
const Set<int> _twoToneWoodWhitePieces = <int>{1, 10, 12, 13, 14, 15, 18, 20};
const Set<int> _outerEdgePieceBlackPieces = <int>{0, 6, 7, 13};
const Set<int> _outerEdgePieceWhitePieces = <int>{2, 3, 4, 8, 10, 17, 21, 23};
const Set<int> _grayRingTimerBlackPieces = <int>{
  6,
  7,
  8,
  11,
  13,
  14,
  17,
  18,
  21,
};
const Set<int> _grayRingTimerWhitePieces = <int>{
  0,
  4,
  5,
  9,
  15,
  16,
  19,
  20,
  22,
};
const Set<int> _perspectivePhysicalPieceBlackPieces = <int>{
  2,
  4,
  5,
  7,
  11,
  15,
  17,
  22,
};
const Set<int> _perspectivePhysicalPieceWhitePieces = <int>{
  3,
  6,
  8,
  9,
  10,
  13,
  19,
  21,
  23,
};
const Set<int> _matchingWoodPieceBlackPieces = <int>{
  1,
  4,
  6,
  10,
  13,
  15,
  16,
  19,
  21,
};
const Set<int> _matchingWoodPieceWhitePieces = <int>{
  2,
  5,
  7,
  9,
  11,
  14,
  18,
  20,
  23,
};
const Set<int> _outlinedNodeBlackPieces = <int>{12, 13, 15, 16};
const Set<int> _outlinedNodeWhitePieces = <int>{8, 9, 10, 11, 23};
const Set<int> _crowdedOutlinedNodeBlackPieces = <int>{2, 11, 13, 15, 19};
const Set<int> _crowdedOutlinedNodeWhitePieces = <int>{3, 4, 5, 6, 16, 18, 20};
const double _lowConfidenceReviewThreshold = 0.55;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BoardImageCorners', () {
    test('accepts an ordered convex quadrilateral', () {
      expect(BoardImageCorners.inset().isValid, isTrue);
    });

    test('rejects crossed corner ordering', () {
      const BoardImageCorners corners = BoardImageCorners(
        topLeft: Offset(0.1, 0.1),
        topRight: Offset(0.9, 0.9),
        bottomRight: Offset(0.9, 0.1),
        bottomLeft: Offset(0.1, 0.9),
      );
      expect(corners.isValid, isFalse);
    });
  });

  group('BoardRecognitionGeometry', () {
    test('creates the standard 24 canonical locations', () {
      final List<BoardPoint> points =
          BoardRecognitionGeometry.createCanonicalBoardPoints();

      expect(points, hasLength(24));
      expect(points[0].originalX, 0);
      expect(points[0].originalY, 0);
      expect(points[4].originalX, 6);
      expect(points[4].originalY, 6);
      expect(points[16].originalX, 2);
      expect(points[16].originalY, 2);
    });

    test('maps selected perspective corners to canonical outer corners', () {
      final img.Image source = _solidImage(420, 320, const Rgb(130, 130, 130));
      const BoardImageCorners corners = BoardImageCorners(
        topLeft: Offset(0.16, 0.18),
        topRight: Offset(0.84, 0.10),
        bottomRight: Offset(0.91, 0.86),
        bottomLeft: Offset(0.10, 0.91),
      );
      const List<Rgb> colors = <Rgb>[
        Rgb(240, 20, 20),
        Rgb(20, 240, 20),
        Rgb(20, 20, 240),
        Rgb(240, 220, 20),
      ];
      for (int index = 0; index < corners.points.length; index++) {
        final Offset point = corners.points[index];
        _fillDisk(
          source,
          (point.dx * (source.width - 1)).round(),
          (point.dy * (source.height - 1)).round(),
          10,
          colors[index],
        );
      }

      final img.Image rectified = BoardRecognitionGeometry.rectify(
        source,
        corners,
        outputSize: 320,
      );
      final List<BoardPoint> points =
          BoardRecognitionGeometry.createCanonicalBoardPoints(imageSize: 320);
      final List<int> cornerIndexes = <int>[0, 2, 4, 6];

      for (int index = 0; index < cornerIndexes.length; index++) {
        final BoardPoint point = points[cornerIndexes[index]];
        final img.Pixel pixel = rectified.getPixel(point.x, point.y);
        expect(
          _rgbDistance(
            Rgb(pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt()),
            colors[index],
          ),
          lessThan(12),
          reason: 'canonical corner ${cornerIndexes[index]}',
        );
      }
    });
  });

  group('BoardCornerDetector', () {
    test('locates the outer square in the captured UI sample', () {
      final img.Image? photo = img.decodeImage(
        File(_capturedUiSamplePath).readAsBytesSync(),
      );
      expect(photo, isNotNull);

      final BoardCornerDetection detection = BoardCornerDetector.detect(photo!);

      expect(detection.isReliable, isTrue);
      expect(
        _maximumCornerError(detection.corners, _capturedUiSampleCorners),
        lessThan(0.015),
        reason:
            'score=${detection.score}, confidence=${detection.confidence}, '
            'corners=${_cornerSummary(detection.corners)}',
      );
      expect(
        (detection.corners.topLeft.dx - _capturedUiSampleCorners.topLeft.dx)
            .abs(),
        lessThan(0.012),
      );
      expect(
        (detection.corners.bottomLeft.dx -
                _capturedUiSampleCorners.bottomLeft.dx)
            .abs(),
        lessThan(0.012),
      );
    });

    test('ignores UI cards below a photographed board', () {
      final img.Image? photo = img.decodeImage(
        File(_boardAboveUiCardsSamplePath).readAsBytesSync(),
      );
      expect(photo, isNotNull);

      final BoardCornerDetection detection = BoardCornerDetector.detect(photo!);

      expect(detection.isReliable, isTrue);
      expect(
        _maximumCornerError(detection.corners, _boardAboveUiCardsCorners),
        lessThan(0.012),
        reason:
            'score=${detection.score}, confidence=${detection.confidence}, '
            'corners=${_cornerSummary(detection.corners)}',
      );
    });

    test('keeps the full outer square around sparse textured pieces', () {
      final img.Image? photo = img.decodeImage(
        File(_sparseTexturedPieceSamplePath).readAsBytesSync(),
      );
      expect(photo, isNotNull);

      final BoardCornerDetection detection = BoardCornerDetector.detect(photo!);

      expect(detection.isReliable, isTrue);
      expect(
        _maximumCornerError(
          detection.corners,
          _sparseTexturedPieceSampleCorners,
        ),
        lessThan(0.025),
        reason:
            'score=${detection.score}, confidence=${detection.confidence}, '
            'corners=${_cornerSummary(detection.corners)}',
      );
    });

    test('keeps pieces overlapping the outer border inside the board', () {
      final img.Image? photo = img.decodeImage(
        File(_numberedOuterBorderSamplePath).readAsBytesSync(),
      );
      expect(photo, isNotNull);

      final BoardCornerDetection detection = BoardCornerDetector.detect(photo!);

      expect(detection.isReliable, isTrue);
      expect(
        _maximumCornerError(
          detection.corners,
          _numberedOuterBorderSampleCorners,
        ),
        lessThan(0.025),
        reason:
            'score=${detection.score}, confidence=${detection.confidence}, '
            'corners=${_cornerSummary(detection.corners)}',
      );
    });

    test('expands to pieces touching all four outer edges', () {
      final img.Image? photo = img.decodeImage(
        File(_outerEdgePieceSamplePath).readAsBytesSync(),
      );
      expect(photo, isNotNull);

      final BoardCornerDetection detection = BoardCornerDetector.detect(photo!);

      expect(detection.isReliable, isTrue);
      expect(
        _maximumCornerError(detection.corners, _outerEdgePieceSampleCorners),
        lessThan(0.025),
        reason:
            'score=${detection.score}, confidence=${detection.confidence}, '
            'corners=${_cornerSummary(detection.corners)}',
      );
    });

    test('keeps the outer square away from nearby page edges', () {
      _expectDetectedCorners(
        path: _pageEdgeSamplePath,
        expected: _pageEdgeSampleCorners,
        maximumError: 0.03,
      );
    });

    test('selects a small board inside an octagonal plaque', () {
      _expectDetectedCorners(
        path: _octagonalPlaqueSamplePath,
        expected: _octagonalPlaqueSampleCorners,
        maximumError: 0.04,
      );
    });

    test('selects an off-center small board beside a game box', () {
      _expectDetectedCorners(
        path: _offCenterSmallBoardSamplePath,
        expected: _offCenterSmallBoardSampleCorners,
        maximumError: 0.04,
      );
    });

    test('uses a hole lattice when physical board lines are faint', () {
      _expectPreparedDetectedCorners(
        path: _physicalHoleBoardSamplePath,
        expected: _physicalHoleBoardSampleCorners,
        maximumError: 0.03,
      );
    });

    test('locates a perspective board despite pieces and a shadow', () {
      const BoardImageCorners expected = BoardImageCorners(
        topLeft: Offset(0.15, 0.13),
        topRight: Offset(0.86, 0.20),
        bottomRight: Offset(0.79, 0.88),
        bottomLeft: Offset(0.11, 0.79),
      );
      final img.Image photo = _syntheticBoardPhoto(
        width: 520,
        height: 420,
        corners: expected,
        addShadow: true,
        pieceIndexes: const <int>{0, 3, 9, 14, 18, 22},
      );

      final BoardCornerDetection detection = BoardCornerDetector.detect(photo);

      expect(detection.isReliable, isTrue);
      expect(
        _maximumCornerError(detection.corners, expected),
        lessThan(0.045),
        reason:
            'score=${detection.score}, confidence=${detection.confidence}, '
            'corners=${detection.corners.points}',
      );
    });

    test('locates a rotated board with distracting background edges', () {
      const BoardImageCorners expected = BoardImageCorners(
        topLeft: Offset(0.29, 0.08),
        topRight: Offset(0.91, 0.35),
        bottomRight: Offset(0.70, 0.91),
        bottomLeft: Offset(0.08, 0.63),
      );
      final img.Image photo = _syntheticBoardPhoto(
        width: 560,
        height: 460,
        corners: expected,
        addClutter: true,
        pieceIndexes: const <int>{1, 4, 7, 11, 16, 20},
      );

      final BoardCornerDetection detection = BoardCornerDetector.detect(photo);

      expect(detection.isReliable, isTrue);
      expect(
        _maximumCornerError(detection.corners, expected),
        lessThan(0.055),
        reason:
            'score=${detection.score}, confidence=${detection.confidence}, '
            'corners=${_cornerSummary(detection.corners)}',
      );
    });

    test('locates an off-center dark board with light lines', () {
      const BoardImageCorners expected = BoardImageCorners(
        topLeft: Offset(0.06, 0.23),
        topRight: Offset(0.72, 0.08),
        bottomRight: Offset(0.81, 0.72),
        bottomLeft: Offset(0.14, 0.88),
      );
      final img.Image photo = _syntheticBoardPhoto(
        width: 540,
        height: 430,
        corners: expected,
        addShadow: true,
        addClutter: true,
        lightLines: true,
        pieceIndexes: const <int>{2, 5, 8, 13, 19, 23},
      );

      final BoardCornerDetection detection = BoardCornerDetector.detect(photo);

      expect(detection.isReliable, isTrue);
      expect(
        _maximumCornerError(detection.corners, expected),
        lessThan(0.06),
        reason:
            'score=${detection.score}, confidence=${detection.confidence}, '
            'corners=${detection.corners.points}',
      );
    });

    test("locates a Twelve Men's Morris board with diagonal lines", () {
      const BoardImageCorners expected = BoardImageCorners(
        topLeft: Offset(0.18, 0.12),
        topRight: Offset(0.88, 0.23),
        bottomRight: Offset(0.78, 0.90),
        bottomLeft: Offset(0.10, 0.76),
      );
      final img.Image photo = _syntheticBoardPhoto(
        width: 540,
        height: 440,
        corners: expected,
        addShadow: true,
        addClutter: true,
        diagonalLines: true,
        pieceIndexes: const <int>{0, 4, 8, 12, 16, 20},
      );

      final BoardCornerDetection detection = BoardCornerDetector.detect(photo);

      expect(detection.isReliable, isTrue);
      expect(
        _maximumCornerError(detection.corners, expected),
        lessThan(0.06),
        reason:
            'score=${detection.score}, confidence=${detection.confidence}, '
            'corners=${_cornerSummary(detection.corners)}',
      );
    });

    test('does not report reliable corners for a plain image', () {
      final BoardCornerDetection detection = BoardCornerDetector.detect(
        _solidImage(520, 420, const Rgb(150, 125, 90)),
      );

      expect(detection.isReliable, isFalse);
      expect(
        detection.confidence,
        lessThan(BoardCornerDetector.minimumReliableConfidence),
      );
    });
  });

  test('prepares a preview before detecting corners asynchronously', () async {
    final PreparedBoardImage? prepared =
        await BoardImageRecognitionService.prepareImageForPreview(
          File(_capturedUiSamplePath).readAsBytesSync(),
        );

    expect(prepared, isNotNull);
    expect(prepared!.detectedCorners, isNull);
    expect(prepared.cornerConfidence, 0);

    final BoardImageCorners? suggestion =
        await BoardImageRecognitionService.detectCorners(prepared);

    expect(suggestion, isNotNull);
    expect(
      _maximumCornerError(suggestion!, _capturedUiSampleCorners),
      lessThan(0.015),
    );
  });

  group('BoardRecognitionClassifier', () {
    test('recognizes pieces in the captured UI sample', () {
      final img.Image? photo = img.decodeImage(
        File(_capturedUiSamplePath).readAsBytesSync(),
      );
      expect(photo, isNotNull);
      final img.Image rectified = BoardRecognitionGeometry.rectify(
        photo!,
        _capturedUiSampleCorners,
      );
      final BoardClassification result = BoardRecognitionClassifier.classify(
        rectified,
        BoardRecognitionGeometry.createCanonicalBoardPoints(),
      );

      expect(
        _pieceIndexes(result.pieces, PieceColor.black),
        _capturedBlackPieces,
      );
      expect(
        _pieceIndexes(result.pieces, PieceColor.white),
        _capturedWhitePieces,
      );
    });

    test('does not classify outlined empty nodes as white pieces', () {
      final img.Image? photo = img.decodeImage(
        File(_outlinedNodeSamplePath).readAsBytesSync(),
      );
      expect(photo, isNotNull);
      const BoardImageCorners corners = BoardImageCorners(
        topLeft: Offset(52 / 590, 466 / 1279),
        topRight: Offset(408 / 590, 466 / 1279),
        bottomRight: Offset(408 / 590, 821 / 1279),
        bottomLeft: Offset(52 / 590, 821 / 1279),
      );
      final img.Image rectified = BoardRecognitionGeometry.rectify(
        photo!,
        corners,
      );
      final BoardClassification result = BoardRecognitionClassifier.classify(
        rectified,
        BoardRecognitionGeometry.createCanonicalBoardPoints(),
      );

      expect(
        _pieceIndexes(result.pieces, PieceColor.black),
        _outlinedNodeBlackPieces,
      );
      expect(
        _pieceIndexes(result.pieces, PieceColor.white),
        _outlinedNodeWhitePieces,
      );
    });

    test('recognizes wood pieces that match the board color', () {
      final img.Image? photo = img.decodeImage(
        File(_matchingWoodPieceSamplePath).readAsBytesSync(),
      );
      expect(photo, isNotNull);
      final img.Image rectified = BoardRecognitionGeometry.rectify(
        photo!,
        _matchingWoodPieceSampleCorners,
      );
      final BoardClassification result = BoardRecognitionClassifier.classify(
        rectified,
        BoardRecognitionGeometry.createCanonicalBoardPoints(),
      );

      expect(
        _pieceIndexes(result.pieces, PieceColor.black),
        _matchingWoodPieceBlackPieces,
      );
      expect(
        _pieceIndexes(result.pieces, PieceColor.white),
        _matchingWoodPieceWhitePieces,
        reason: 'confidences=${result.confidences}',
      );
    });

    test('recognizes black and white pieces without theme colors', () {
      const Set<int> black = <int>{0, 11, 20};
      const Set<int> white = <int>{2, 13, 22};
      final img.Image image = _syntheticBoard(
        blackPieces: black,
        whitePieces: white,
      );
      final List<BoardPoint> points =
          BoardRecognitionGeometry.createCanonicalBoardPoints();

      final BoardClassification result = BoardRecognitionClassifier.classify(
        image,
        points,
      );

      for (int index = 0; index < 24; index++) {
        final PieceColor expected = black.contains(index)
            ? PieceColor.black
            : white.contains(index)
            ? PieceColor.white
            : PieceColor.none;
        expect(result.pieces[index], expected, reason: 'point $index');
      }
    });

    test(
      "recognizes pieces on a Twelve Men's Morris board with diagonal lines",
      () {
        const Set<int> black = <int>{0, 9, 20};
        const Set<int> white = <int>{4, 13, 16};
        final BoardClassification result = BoardRecognitionClassifier.classify(
          _syntheticBoard(
            blackPieces: black,
            whitePieces: white,
            diagonalLines: true,
          ),
          BoardRecognitionGeometry.createCanonicalBoardPoints(),
        );

        expect(_pieceIndexes(result.pieces, PieceColor.black), black);
        expect(_pieceIndexes(result.pieces, PieceColor.white), white);
      },
    );

    test('does not invent a missing white-piece class', () {
      const Set<int> black = <int>{1, 8, 17, 23};
      final BoardClassification result = BoardRecognitionClassifier.classify(
        _syntheticBoard(blackPieces: black),
        BoardRecognitionGeometry.createCanonicalBoardPoints(),
      );

      expect(
        result.pieces.values.where(
          (PieceColor color) => color == PieceColor.black,
        ),
        hasLength(black.length),
      );
      expect(result.pieces.values, isNot(contains(PieceColor.white)));
    });

    test('keeps an empty board empty', () {
      final BoardClassification result = BoardRecognitionClassifier.classify(
        _syntheticBoard(),
        BoardRecognitionGeometry.createCanonicalBoardPoints(),
      );

      expect(
        result.pieces.values.every(
          (PieceColor color) => color == PieceColor.none,
        ),
        isTrue,
      );
    });
  });

  test(
    'service recognizes the captured UI sample from detected corners',
    () async {
      final BoardRecognitionResult result =
          await _recognizeFixtureThroughImportFlow(_capturedUiSamplePath);

      expect(result.failure, isNull);
      expect(
        _pieceIndexes(result.pieces, PieceColor.black),
        _capturedBlackPieces,
      );
      expect(
        _pieceIndexes(result.pieces, PieceColor.white),
        _capturedWhitePieces,
      );
    },
  );

  test(
    'service ignores outlined empty nodes in the captured web board',
    () async {
      final BoardRecognitionResult result =
          await _recognizeFixtureThroughImportFlow(_outlinedNodeSamplePath);

      expect(result.failure, isNull);
      expect(
        _pieceIndexes(result.pieces, PieceColor.black),
        _outlinedNodeBlackPieces,
      );
      expect(
        _pieceIndexes(result.pieces, PieceColor.white),
        _outlinedNodeWhitePieces,
      );
      expect(
        _lowConfidenceIndexes(result.confidences),
        isEmpty,
        reason: 'confidences=${result.confidences}',
      );
    },
  );

  test('service ignores outlined empty nodes on a crowded web board', () async {
    final BoardRecognitionResult result =
        await _recognizeFixtureThroughImportFlow(
          _crowdedOutlinedNodeSamplePath,
        );

    expect(result.failure, isNull);
    final Set<int> detectedBlack = _pieceIndexes(
      result.pieces,
      PieceColor.black,
    );
    final Set<int> detectedWhite = _pieceIndexes(
      result.pieces,
      PieceColor.white,
    );
    expect(
      detectedBlack,
      _crowdedOutlinedNodeBlackPieces,
      reason: 'white=$detectedWhite, confidences=${result.confidences}',
    );
    expect(
      detectedWhite,
      _crowdedOutlinedNodeWhitePieces,
      reason: 'black=$detectedBlack, confidences=${result.confidences}',
    );
    expect(
      _lowConfidenceIndexes(result.confidences),
      isEmpty,
      reason: 'confidences=${result.confidences}',
    );
  });

  test(
    'service recognizes a board above unrelated UI cards confidently',
    () async {
      final BoardRecognitionResult result =
          await _recognizeFixtureThroughImportFlow(
            _boardAboveUiCardsSamplePath,
          );

      expect(result.failure, isNull);
      expect(
        _lowConfidenceIndexes(result.confidences),
        isEmpty,
        reason: 'confidences=${result.confidences}',
      );
      expect(
        _pieceIndexes(result.pieces, PieceColor.black),
        _boardAboveUiCardsBlackPieces,
      );
      expect(
        _pieceIndexes(result.pieces, PieceColor.white),
        _boardAboveUiCardsWhitePieces,
      );
    },
  );

  test(
    'service recognizes nested ring pieces without uncertain empty nodes',
    () async {
      final BoardRecognitionResult result =
          await _recognizeFixtureThroughImportFlow(_nestedRingSamplePath);

      expect(result.failure, isNull);
      expect(
        _lowConfidenceIndexes(result.confidences),
        isEmpty,
        reason: 'confidences=${result.confidences}',
      );
      expect(
        _pieceIndexes(result.pieces, PieceColor.black),
        _nestedRingBlackPieces,
      );
      expect(
        _pieceIndexes(result.pieces, PieceColor.white),
        _nestedRingWhitePieces,
      );
    },
  );

  test(
    'service recognizes sparse textured pieces on a wood board',
    () => _expectFixtureRecognition(
      path: _sparseTexturedPieceSamplePath,
      blackPieces: _sparseTexturedPieceBlackPieces,
      whitePieces: _sparseTexturedPieceWhitePieces,
    ),
  );

  test('service recognizes wood pieces that match the board color', () async {
    final BoardRecognitionResult result =
        await _recognizeFixtureThroughImportFlow(_matchingWoodPieceSamplePath);

    expect(result.failure, isNull);
    expect(
      _pieceIndexes(result.pieces, PieceColor.black),
      _matchingWoodPieceBlackPieces,
    );
    expect(
      _pieceIndexes(result.pieces, PieceColor.white),
      _matchingWoodPieceWhitePieces,
    );
    expect(
      _lowConfidenceIndexes(result.confidences),
      <int>{7},
      reason: 'confidences=${result.confidences}',
    );
  });

  test(
    'service recognizes numbered pieces overlapping the outer border',
    () => _expectFixtureRecognition(
      path: _numberedOuterBorderSamplePath,
      blackPieces: _numberedOuterBorderBlackPieces,
      whitePieces: _numberedOuterBorderWhitePieces,
    ),
  );

  test(
    'service recognizes two-tone pieces on a wood board',
    () => _expectFixtureRecognition(
      path: _twoToneWoodSamplePath,
      blackPieces: _twoToneWoodBlackPieces,
      whitePieces: _twoToneWoodWhitePieces,
    ),
  );

  test(
    'service recognizes pieces touching all four outer edges',
    () => _expectFixtureRecognition(
      path: _outerEdgePieceSamplePath,
      blackPieces: _outerEdgePieceBlackPieces,
      whitePieces: _outerEdgePieceWhitePieces,
    ),
  );

  test(
    'service confidently recognizes gray rings around a timer',
    () => _expectFixtureRecognition(
      path: _grayRingTimerSamplePath,
      blackPieces: _grayRingTimerBlackPieces,
      whitePieces: _grayRingTimerWhitePieces,
    ),
  );

  test(
    'service recognizes perspective physical concentric pieces',
    () => _expectFixtureRecognition(
      path: _perspectivePhysicalPieceSamplePath,
      blackPieces: _perspectivePhysicalPieceBlackPieces,
      whitePieces: _perspectivePhysicalPieceWhitePieces,
    ),
  );

  test(
    'service recognizes a prepared straight-on board off the UI isolate',
    () async {
      const Set<int> black = <int>{0, 11, 20};
      const Set<int> white = <int>{2, 13, 22};
      final PreparedBoardImage? prepared =
          await BoardImageRecognitionService.prepareImage(
            img.encodePng(
              _syntheticBoard(blackPieces: black, whitePieces: white),
            ),
          );
      expect(prepared, isNotNull);
      expect(prepared!.detectedCorners, isNotNull);
      expect(prepared.cornerConfidence, greaterThanOrEqualTo(0.34));

      const double padding = BoardRecognitionGeometry.canonicalPadding;
      const BoardImageCorners corners = BoardImageCorners(
        topLeft: Offset(padding, padding),
        topRight: Offset(1 - padding, padding),
        bottomRight: Offset(1 - padding, 1 - padding),
        bottomLeft: Offset(padding, 1 - padding),
      );
      final BoardRecognitionResult result =
          await BoardImageRecognitionService.recognizeBoardFromImage(
            prepared,
            corners: corners,
          );

      expect(result.failure, isNull);
      expect(result.rectifiedImageBytes, isNotNull);
      for (final int index in black) {
        expect(result.pieces[index], PieceColor.black, reason: 'point $index');
      }
      for (final int index in white) {
        expect(result.pieces[index], PieceColor.white, reason: 'point $index');
      }
    },
  );
}

img.Image _syntheticBoardPhoto({
  required int width,
  required int height,
  required BoardImageCorners corners,
  bool addShadow = false,
  bool addClutter = false,
  bool lightLines = false,
  bool diagonalLines = false,
  Set<int> pieceIndexes = const <int>{},
}) {
  final img.Image image = img.Image(
    width: width,
    height: height,
    numChannels: 3,
  );
  final List<Offset> cornerPixels = corners.points
      .map(
        (Offset point) =>
            Offset(point.dx * (width - 1), point.dy * (height - 1)),
      )
      .toList(growable: false);

  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      final bool inside = _insideConvexQuad(
        Offset(x.toDouble(), y.toDouble()),
        cornerPixels,
      );
      final int shadow = addShadow ? ((x / width) * 58).round() : 0;
      if (inside) {
        image.setPixelRgb(
          x,
          y,
          math.max(30, (lightLines ? 78 : 192) - shadow),
          math.max(28, (lightLines ? 83 : 151) - shadow),
          math.max(24, (lightLines ? 88 : 96) - shadow),
        );
      } else {
        final int texture = ((x * 13 + y * 7) % 11) - 5;
        image.setPixelRgb(x, y, 112 + texture, 101 + texture, 87 + texture);
      }
    }
  }

  if (addClutter) {
    _drawPixelLine(
      image,
      const Offset(0, 42),
      Offset(width.toDouble(), 8),
      3,
      const Rgb(42, 46, 50),
    );
    _drawPixelLine(
      image,
      Offset(width - 30, 0),
      Offset(width - 4, height.toDouble()),
      4,
      const Rgb(224, 216, 195),
    );
    _drawPixelLine(
      image,
      Offset(0, height - 18),
      Offset(width * 0.45, height - 2),
      3,
      const Rgb(46, 51, 55),
    );
  }

  final _TestProjectiveMap transform = _TestProjectiveMap(corners);
  final List<BoardPoint> points = <BoardPoint>[
    for (final Offset gridPoint in BoardRecognitionGeometry.standardGridPoints)
      BoardPoint(
        (transform.map(gridPoint / 6).dx * (width - 1)).round(),
        (transform.map(gridPoint / 6).dy * (height - 1)).round(),
        12,
      ),
  ];
  _drawMillLines(
    image,
    points,
    lightLines ? const Rgb(226, 220, 198) : const Rgb(48, 35, 24),
    diagonalLines: diagonalLines,
  );
  for (final int index in pieceIndexes) {
    _fillDisk(
      image,
      points[index].x,
      points[index].y,
      11,
      index.isEven ? const Rgb(32, 34, 38) : const Rgb(236, 231, 215),
    );
  }
  return image;
}

bool _insideConvexQuad(Offset point, List<Offset> corners) {
  for (int index = 0; index < corners.length; index++) {
    final Offset start = corners[index];
    final Offset end = corners[(index + 1) % corners.length];
    final Offset edge = end - start;
    final Offset relative = point - start;
    if (edge.dx * relative.dy - edge.dy * relative.dx < 0) {
      return false;
    }
  }
  return true;
}

void _drawPixelLine(
  img.Image image,
  Offset start,
  Offset end,
  int radius,
  Rgb color,
) {
  final int steps = math.max(
    (end.dx - start.dx).abs().round(),
    (end.dy - start.dy).abs().round(),
  );
  for (int step = 0; step <= steps; step++) {
    final double t = steps == 0 ? 0 : step / steps;
    _fillDisk(
      image,
      (start.dx + (end.dx - start.dx) * t).round(),
      (start.dy + (end.dy - start.dy) * t).round(),
      radius,
      color,
    );
  }
}

double _maximumCornerError(
  BoardImageCorners actual,
  BoardImageCorners expected,
) {
  double maximum = 0;
  for (int index = 0; index < 4; index++) {
    maximum = math.max(
      maximum,
      (actual.points[index] - expected.points[index]).distance,
    );
  }
  return maximum;
}

String _cornerSummary(BoardImageCorners corners) => corners.points
    .map(
      (Offset point) =>
          '(${point.dx.toStringAsFixed(4)},${point.dy.toStringAsFixed(4)})',
    )
    .join(', ');

void _expectDetectedCorners({
  required String path,
  required BoardImageCorners expected,
  required double maximumError,
}) {
  final img.Image? photo = img.decodeImage(File(path).readAsBytesSync());
  expect(photo, isNotNull);

  final BoardCornerDetection detection = BoardCornerDetector.detect(photo!);

  expect(detection.isReliable, isTrue);
  expect(
    _maximumCornerError(detection.corners, expected),
    lessThan(maximumError),
    reason:
        'score=${detection.score}, confidence=${detection.confidence}, '
        'corners=${_cornerSummary(detection.corners)}',
  );
}

void _expectPreparedDetectedCorners({
  required String path,
  required BoardImageCorners expected,
  required double maximumError,
}) {
  final PreparedBoardImage? prepared = BoardRecognitionGeometry.prepare(
    File(path).readAsBytesSync(),
  );
  expect(prepared, isNotNull);
  expect(prepared!.detectedCorners, isNotNull);
  expect(
    _maximumCornerError(prepared.detectedCorners!, expected),
    lessThan(maximumError),
    reason:
        'confidence=${prepared.cornerConfidence}, '
        'corners=${_cornerSummary(prepared.detectedCorners!)}',
  );
}

Set<int> _pieceIndexes(Map<int, PieceColor> pieces, PieceColor color) => pieces
    .entries
    .where((MapEntry<int, PieceColor> entry) => entry.value == color)
    .map((MapEntry<int, PieceColor> entry) => entry.key)
    .toSet();

Set<int> _lowConfidenceIndexes(Map<int, double> confidences) => confidences
    .entries
    .where(
      (MapEntry<int, double> entry) =>
          entry.value < _lowConfidenceReviewThreshold,
    )
    .map((MapEntry<int, double> entry) => entry.key)
    .toSet();

Future<void> _expectFixtureRecognition({
  required String path,
  required Set<int> blackPieces,
  required Set<int> whitePieces,
}) async {
  final BoardRecognitionResult result =
      await _recognizeFixtureThroughImportFlow(path);

  expect(result.failure, isNull);
  expect(
    _pieceIndexes(result.pieces, PieceColor.black),
    blackPieces,
    reason: 'confidences=${result.confidences}',
  );
  expect(
    _pieceIndexes(result.pieces, PieceColor.white),
    whitePieces,
    reason: 'confidences=${result.confidences}',
  );
  expect(
    _lowConfidenceIndexes(result.confidences),
    isEmpty,
    reason: 'confidences=${result.confidences}',
  );
}

Future<BoardRecognitionResult> _recognizeFixtureThroughImportFlow(
  String path,
) async {
  final PreparedBoardImage? prepared =
      await BoardImageRecognitionService.prepareImageForPreview(
        File(path).readAsBytesSync(),
      );
  if (prepared == null) {
    throw StateError('Failed to prepare board recognition fixture: $path');
  }
  final BoardImageCorners? corners =
      await BoardImageRecognitionService.detectCorners(prepared);
  if (corners == null) {
    throw StateError('Failed to detect fixture corners: $path');
  }
  return BoardImageRecognitionService.recognizeBoardFromImage(
    prepared,
    corners: corners,
  );
}

class _TestProjectiveMap {
  _TestProjectiveMap(BoardImageCorners corners) {
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
    final double denominator = dx1 * dy2 - dx2 * dy1;
    _g = (dx3 * dy2 - dx2 * dy3) / denominator;
    _h = (dx1 * dy3 - dx3 * dy1) / denominator;
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

img.Image _syntheticBoard({
  Set<int> blackPieces = const <int>{},
  Set<int> whitePieces = const <int>{},
  bool diagonalLines = false,
}) {
  final img.Image image = img.Image(
    width: BoardRecognitionGeometry.canonicalImageSize,
    height: BoardRecognitionGeometry.canonicalImageSize,
    numChannels: 3,
  );
  for (int y = 0; y < image.height; y++) {
    for (int x = 0; x < image.width; x++) {
      final int light = ((x / image.width) * 14 + (y / image.height) * 8)
          .round();
      image.setPixelRgb(x, y, 166 + light, 132 + light, 82 + light);
    }
  }

  final List<BoardPoint> points =
      BoardRecognitionGeometry.createCanonicalBoardPoints();
  _drawMillLines(
    image,
    points,
    const Rgb(72, 52, 34),
    diagonalLines: diagonalLines,
  );
  for (final int index in blackPieces) {
    final BoardPoint point = points[index];
    _fillDisk(
      image,
      point.x,
      point.y,
      (point.radius * 0.82).round(),
      const Rgb(28, 31, 36),
    );
  }
  for (final int index in whitePieces) {
    final BoardPoint point = points[index];
    _fillDisk(
      image,
      point.x,
      point.y,
      (point.radius * 0.82).round(),
      const Rgb(238, 234, 218),
    );
  }
  return image;
}

void _drawMillLines(
  img.Image image,
  List<BoardPoint> points,
  Rgb color, {
  bool diagonalLines = false,
}) {
  for (int ring = 0; ring < 3; ring++) {
    for (int index = 0; index < 8; index++) {
      _drawLine(
        image,
        points[ring * 8 + index],
        points[ring * 8 + (index + 1) % 8],
        color,
      );
    }
  }
  for (final int index in <int>[1, 3, 5, 7]) {
    _drawLine(image, points[index], points[8 + index], color);
    _drawLine(image, points[8 + index], points[16 + index], color);
  }
  if (diagonalLines) {
    for (final int index in <int>[0, 2, 4, 6]) {
      _drawLine(image, points[index], points[8 + index], color);
      _drawLine(image, points[8 + index], points[16 + index], color);
    }
  }
}

void _drawLine(img.Image image, BoardPoint start, BoardPoint end, Rgb color) {
  final int steps = math.max((end.x - start.x).abs(), (end.y - start.y).abs());
  for (int step = 0; step <= steps; step++) {
    final double t = steps == 0 ? 0 : step / steps;
    final int x = (start.x + (end.x - start.x) * t).round();
    final int y = (start.y + (end.y - start.y) * t).round();
    _fillDisk(image, x, y, 2, color);
  }
}

img.Image _solidImage(int width, int height, Rgb color) {
  final img.Image image = img.Image(
    width: width,
    height: height,
    numChannels: 3,
  );
  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      image.setPixelRgb(x, y, color.r, color.g, color.b);
    }
  }
  return image;
}

void _fillDisk(
  img.Image image,
  int centerX,
  int centerY,
  int radius,
  Rgb color,
) {
  for (int y = centerY - radius; y <= centerY + radius; y++) {
    for (int x = centerX - radius; x <= centerX + radius; x++) {
      if (x < 0 || x >= image.width || y < 0 || y >= image.height) {
        continue;
      }
      final int dx = x - centerX;
      final int dy = y - centerY;
      if (dx * dx + dy * dy <= radius * radius) {
        image.setPixelRgb(x, y, color.r, color.g, color.b);
      }
    }
  }
}

double _rgbDistance(Rgb first, Rgb second) => math.sqrt(
  math.pow(first.r - second.r, 2) +
      math.pow(first.g - second.g, 2) +
      math.pow(first.b - second.b, 2),
);
