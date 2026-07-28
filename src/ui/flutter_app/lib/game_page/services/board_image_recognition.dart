// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../../shared/services/logger.dart';
import 'board_corner_detector.dart';
import 'board_recognition_classifier.dart';
import 'board_recognition_geometry.dart';
import 'board_recognition_models.dart';
import 'mill.dart';

export 'board_recognition_models.dart';

/// Recognizes a photographed Mill position after the user confirms its four
/// outer-ring corner intersections.
///
/// The expensive decode, projective rectification and point classification
/// run through [compute], keeping them off the UI isolate on native platforms.
abstract final class BoardImageRecognitionService {
  static List<BoardPoint> lastDetectedPoints = const <BoardPoint>[];
  static BoardRecognitionDebugInfo lastDebugInfo = BoardRecognitionDebugInfo();
  static int _processedImageWidth = 0;
  static int _processedImageHeight = 0;

  static int get processedImageWidth => _processedImageWidth;

  static int get processedImageHeight => _processedImageHeight;

  /// Prepares an oriented preview and waits for an automatic corner search.
  static Future<PreparedBoardImage?> prepareImage(Uint8List imageBytes) =>
      compute<Uint8List, PreparedBoardImage?>(
        _prepareBoardImage,
        imageBytes,
        debugLabel: 'prepare-board-image',
      );

  /// Prepares an oriented preview without waiting for automatic corner search.
  static Future<PreparedBoardImage?> prepareImageForPreview(
    Uint8List imageBytes,
  ) => compute<Uint8List, PreparedBoardImage?>(
    _prepareBoardImageForPreview,
    imageBytes,
    debugLabel: 'prepare-board-image-preview',
  );

  /// Suggests reliable outer-square corners for an already prepared preview.
  static Future<BoardImageCorners?> detectCorners(
    PreparedBoardImage source,
  ) async {
    try {
      return await compute<Uint8List, BoardImageCorners?>(
        _detectBoardCorners,
        source.bytes,
        debugLabel: 'detect-board-corners',
      );
    } catch (error, stackTrace) {
      logger.e('Board corner detection failed: $error\n$stackTrace');
      return null;
    }
  }

  /// Rectifies and classifies a prepared image.
  static Future<BoardRecognitionResult> recognizeBoardFromImage(
    PreparedBoardImage source, {
    required BoardImageCorners corners,
  }) async {
    if (!corners.isValid) {
      return BoardRecognitionResult.failure(
        failure: BoardRecognitionFailure.invalidCorners,
      );
    }

    try {
      final _RecognitionWorkerOutput output =
          await compute<_RecognitionRequest, _RecognitionWorkerOutput>(
            _recognizeBoardImage,
            _RecognitionRequest(source.bytes, corners),
            debugLabel: 'recognize-board-image',
          );
      final img.Image? originalImage = img.decodeImage(source.bytes);
      final img.Image? rectifiedImage = img.decodeImage(
        output.rectifiedImageBytes,
      );
      final int inset =
          (output.processedWidth * BoardRecognitionGeometry.canonicalPadding)
              .round();
      final BoardRecognitionDebugInfo debugInfo = BoardRecognitionDebugInfo(
        originalImage: originalImage,
        processedImage: rectifiedImage,
        boardRect: math.Rectangle<int>(
          inset,
          inset,
          output.processedWidth - 2 * inset,
          output.processedHeight - 2 * inset,
        ),
        boardColor: output.boardColor,
        characteristics: output.characteristics,
        colorProfile: output.colorProfile,
        boardPoints: output.boardPoints,
        linesDetectionImage: rectifiedImage,
      );

      lastDetectedPoints = output.boardPoints;
      lastDebugInfo = debugInfo;
      _processedImageWidth = output.processedWidth;
      _processedImageHeight = output.processedHeight;

      final bool hasPieces = output.pieces.values.any(
        (PieceColor color) =>
            color == PieceColor.white || color == PieceColor.black,
      );
      if (!hasPieces) {
        return BoardRecognitionResult.failure(
          failure: BoardRecognitionFailure.noPiecesDetected,
          rectifiedImageBytes: output.rectifiedImageBytes,
          boardPoints: output.boardPoints,
          processedWidth: output.processedWidth,
          processedHeight: output.processedHeight,
          debugInfo: debugInfo,
        );
      }

      return BoardRecognitionResult.success(
        pieces: output.pieces,
        confidences: output.confidences,
        rectifiedImageBytes: output.rectifiedImageBytes,
        boardPoints: output.boardPoints,
        processedWidth: output.processedWidth,
        processedHeight: output.processedHeight,
        debugInfo: debugInfo,
      );
    } catch (error, stackTrace) {
      logger.e('Board recognition failed: $error\n$stackTrace');
      lastDetectedPoints = const <BoardPoint>[];
      lastDebugInfo = BoardRecognitionDebugInfo();
      _processedImageWidth = 0;
      _processedImageHeight = 0;
      return BoardRecognitionResult.failure(
        failure: BoardRecognitionFailure.processingFailed,
      );
    }
  }
}

PreparedBoardImage? _prepareBoardImage(Uint8List bytes) =>
    BoardRecognitionGeometry.prepare(bytes);

PreparedBoardImage? _prepareBoardImageForPreview(Uint8List bytes) =>
    BoardRecognitionGeometry.prepare(bytes, detectCorners: false);

BoardImageCorners? _detectBoardCorners(Uint8List bytes) {
  final img.Image? decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw const FormatException('Prepared board image could not be decoded');
  }
  final BoardCornerDetection detection = BoardCornerDetector.detect(decoded);
  return detection.isReliable ? detection.corners : null;
}

_RecognitionWorkerOutput _recognizeBoardImage(_RecognitionRequest request) {
  final img.Image? decoded = img.decodeImage(request.bytes);
  if (decoded == null) {
    throw const FormatException('Prepared board image could not be decoded');
  }
  final img.Image rectified = BoardRecognitionGeometry.rectify(
    decoded,
    request.corners,
  );
  final List<BoardPoint> boardPoints =
      BoardRecognitionGeometry.createCanonicalBoardPoints();
  final BoardClassification classification =
      BoardRecognitionClassifier.classify(rectified, boardPoints);
  return _RecognitionWorkerOutput(
    pieces: classification.pieces,
    confidences: classification.confidences,
    rectifiedImageBytes: Uint8List.fromList(
      img.encodeJpg(rectified, quality: 96),
    ),
    boardPoints: boardPoints,
    processedWidth: rectified.width,
    processedHeight: rectified.height,
    characteristics: classification.characteristics,
    colorProfile: classification.colorProfile,
    boardColor: classification.boardColor,
  );
}

class _RecognitionRequest {
  const _RecognitionRequest(this.bytes, this.corners);

  final Uint8List bytes;
  final BoardImageCorners corners;
}

class _RecognitionWorkerOutput {
  const _RecognitionWorkerOutput({
    required this.pieces,
    required this.confidences,
    required this.rectifiedImageBytes,
    required this.boardPoints,
    required this.processedWidth,
    required this.processedHeight,
    required this.characteristics,
    required this.colorProfile,
    required this.boardColor,
  });

  final Map<int, PieceColor> pieces;
  final Map<int, double> confidences;
  final Uint8List rectifiedImageBytes;
  final List<BoardPoint> boardPoints;
  final int processedWidth;
  final int processedHeight;
  final ImageCharacteristics characteristics;
  final ColorProfile colorProfile;
  final Rgb boardColor;
}
