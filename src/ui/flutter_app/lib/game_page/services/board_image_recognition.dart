// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// board_image_recognition.dart

// ignore_for_file: avoid_classes_with_only_static_members

import 'dart:async';
import 'dart:collection'; // Needed for Queue in CCA
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

import '../../shared/database/database.dart';
import '../../shared/services/logger.dart';
import 'mill.dart'; // Assuming PieceColor is defined here

/// Debug information container, storing results from various processing stages
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

  /// Original image
  final img.Image? originalImage;

  /// Preprocessed image
  final img.Image? processedImage;

  /// Detected board area rectangle
  final math.Rectangle<int>? boardRect;

  /// Estimated board color
  final Rgb? boardColor;

  /// Image characteristics
  final ImageCharacteristics? characteristics;

  /// Color profile
  final ColorProfile? colorProfile;

  /// Board mask (used for segmentation)
  final List<List<bool>>? boardMask;

  /// Detected board points
  final List<BoardPoint> boardPoints;

  /// Added debug image for line detection (if implemented)
  final img.Image? linesDetectionImage;

  /// Creates a copy of this object, updating specified fields
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

  /// Converts an image to Uint8List for display in Flutter
  static Uint8List? imageToBytes(img.Image? image) {
    if (image == null) {
      return null;
    }
    return Uint8List.fromList(img.encodeJpg(image));
  }
}

/// Helper structure for points in connected components analysis
class _Point {
  _Point(this.x, this.y);

  final int x, y;
}

/// A service for recognizing pieces on a mill board from an image.
/// Uses lightweight image processing to identify the position of pieces
/// on a Nine Men's Morris board.
///
/// Enhanced with adaptive thresholding for varied lighting conditions
/// and automatic board detection for different board styles and orientations.
class BoardImageRecognitionService {
  // Constants for image processing
  static const int _processingWidth =
      800; // Width to resize image for processing
  static const double _pieceThreshold =
      0.25; // Adjusted threshold for piece detection
  static const double _contrastEnhancementFactor =
      1.8; // Increased contrast enhancement
  static const double _boardColorDistanceThreshold =
      28.0; // Threshold for determining board color
  static const double _pieceColorMatchThreshold =
      30.0; // Threshold for matching configured piece colors

  // Store the last detected board points and image processing dimensions
  static List<BoardPoint> _lastDetectedPoints = <BoardPoint>[];
  static int _processedImageWidth = 0;
  static int _processedImageHeight = 0;

  // Add storage for debug information
  static BoardRecognitionDebugInfo _lastDebugInfo = BoardRecognitionDebugInfo();

  // Add mutable parameters that can be adjusted at runtime
  /// Contrast enhancement factor used during image processing
  static double contrastEnhancementFactor = _contrastEnhancementFactor;

  /// Threshold for detecting pieces in the image
  static double pieceThreshold = _pieceThreshold;

  /// Threshold for determining if a color is close to the board color
  static double boardColorDistanceThreshold = _boardColorDistanceThreshold;

  /// Threshold for matching colors to configured piece colors
  static double pieceColorMatchThreshold = _pieceColorMatchThreshold;

  /// Brightness threshold for white pieces
  static int whiteBrightnessThreshold = _whiteBrightnessThresholdBase;

  /// Brightness threshold for black pieces
  static int blackBrightnessThreshold = _blackBrightnessThresholdBase;

  /// Threshold for black piece saturation
  static double blackSaturationThreshold = _blackSaturationThreshold;

  /// Threshold for black piece color variance
  static int blackColorVarianceThreshold = _blackColorVarianceThreshold;

  /// Updates the recognition parameters used by the service
  ///
  /// These parameters affect how the board and pieces are detected in images
  static void updateParameters({
    double? contrastEnhancementFactor,
    double? pieceThreshold,
    double? boardColorDistanceThreshold,
    double? pieceColorMatchThreshold,
    int? whiteBrightnessThreshold,
    int? blackBrightnessThreshold,
    double? blackSaturationThreshold,
    int? blackColorVarianceThreshold,
  }) {
    if (contrastEnhancementFactor != null) {
      BoardImageRecognitionService.contrastEnhancementFactor =
          contrastEnhancementFactor;
    }
    if (pieceThreshold != null) {
      BoardImageRecognitionService.pieceThreshold = pieceThreshold;
    }
    if (boardColorDistanceThreshold != null) {
      BoardImageRecognitionService.boardColorDistanceThreshold =
          boardColorDistanceThreshold;
    }
    if (pieceColorMatchThreshold != null) {
      BoardImageRecognitionService.pieceColorMatchThreshold =
          pieceColorMatchThreshold;
    }
    if (whiteBrightnessThreshold != null) {
      BoardImageRecognitionService.whiteBrightnessThreshold =
          whiteBrightnessThreshold;
    }
    if (blackBrightnessThreshold != null) {
      BoardImageRecognitionService.blackBrightnessThreshold =
          blackBrightnessThreshold;
    }
    if (blackSaturationThreshold != null) {
      BoardImageRecognitionService.blackSaturationThreshold =
          blackSaturationThreshold;
    }
    if (blackColorVarianceThreshold != null) {
      BoardImageRecognitionService.blackColorVarianceThreshold =
          blackColorVarianceThreshold;
    }

    logger.i("Recognition parameters updated");
  }

  // Getter method for the last detected board points
  // ignore: unnecessary_getters_setters
  static List<BoardPoint> get lastDetectedPoints => _lastDetectedPoints;

  // Expose processed image dimensions
  static int get processedImageWidth => _processedImageWidth;

  static int get processedImageHeight => _processedImageHeight;

  // Expose debug information
  // ignore: unnecessary_getters_setters
  static BoardRecognitionDebugInfo get lastDebugInfo => _lastDebugInfo;

  // More sensitive color detection thresholds
  static const int _whiteBrightnessThresholdBase = 170;
  static const int _blackBrightnessThresholdBase = 135;

  // Edge detection parameters (Placeholder - values might need adjustment)
  // (No specific parameters used in the current stubbed version)

  // Board geometry constants
// Board typically occupies 85% of the image (Used in legacy?)
// Space between rings (Used in legacy?)

  // Parameters related to black piece color detection
  static const double _blackSaturationThreshold =
      0.25; // Black piece saturation threshold, values below this are considered neutral
  static const int _blackColorVarianceThreshold =
      40; // Maximum difference threshold for RGB channels

  // Position tolerance parameters
// Position tolerance radius for finding optimal points

  /// Analyze the provided image and return the detected board state.
  ///
  /// The returned board state will be a map from point indices (0-23) to piece colors
  /// (white, black, or none).
  static Future<Map<int, PieceColor>> recognizeBoardFromImage(
      Uint8List imageBytes) async {
    // Default to all points being empty
    final Map<int, PieceColor> result = <int, PieceColor>{};
    for (int i = 0; i < 24; i++) {
      result[i] = PieceColor.none;
    }

    try {
      // Decode the image
      final img.Image? decodedImage = img.decodeImage(imageBytes);
      if (decodedImage == null) {
        logger.e("Failed to decode image for board recognition");
        return result;
      }

      // Create a new debug info object, save the original image
      // Create a copy to ensure the image is saved correctly
      final img.Image originalImageCopy = img.copyResize(decodedImage,
          width: decodedImage.width, height: decodedImage.height);

      _lastDebugInfo = BoardRecognitionDebugInfo(
        originalImage: originalImageCopy,
      );

      // Resize image for faster processing if needed
      img.Image processImage = _resizeForProcessing(decodedImage);

      // Keep a copy of the unprocessed resized image for color analysis
      final img.Image unprocessedImage = img.copyResize(processImage,
          width: processImage.width, height: processImage.height);

      // Save processed image dimensions
      _processedImageWidth = processImage.width;
      _processedImageHeight = processImage.height;

      // Update debug info - Create a copy to ensure the image is saved
      final img.Image resizedImageCopy = img.copyResize(processImage,
          width: processImage.width, height: processImage.height);

      _lastDebugInfo = _lastDebugInfo.copyWith(
        processedImage: resizedImageCopy,
      );

      // Pre-process image to enhance features - now using static parameters
      processImage = _enhanceImageForProcessing(
        processImage,
        contrastEnhancementFactor: contrastEnhancementFactor,
      );

      // Update debug info with the processed image - Create a copy
      final img.Image enhancedImageCopy = img.copyResize(processImage,
          width: processImage.width, height: processImage.height);

      _lastDebugInfo = _lastDebugInfo.copyWith(
        processedImage: enhancedImageCopy,
      );

      // Analyze image characteristics to calibrate detection thresholds - using static parameters
      final ImageCharacteristics characteristics = _analyzeImageCharacteristics(
        processImage,
        whiteBrightnessThresholdBase: whiteBrightnessThreshold,
        blackBrightnessThresholdBase: blackBrightnessThreshold,
        pieceThreshold: pieceThreshold,
      );
      logger.i(
          "Image analysis: brightness=${characteristics.averageBrightness.toStringAsFixed(1)}, "
          "isDark=${characteristics.isDarkBackground}, contrast=${characteristics.isHighContrast}");

      // Update debug info
      _lastDebugInfo = _lastDebugInfo.copyWith(
        characteristics: characteristics,
      );

      // For very low contrast images, apply additional contrast enhancement
      if (!characteristics.isHighContrast &&
          characteristics.contrastRatio < 1.5) {
        logger
            .i("Low contrast image detected, applying additional enhancement");
        // *** METHOD NEEDS IMPLEMENTATION ***
        processImage = _enhanceLowContrastImage(processImage);

        // Update debug info with the processed image - Create a copy
        final img.Image enhancedContrastImageCopy = img.copyResize(processImage,
            width: processImage.width, height: processImage.height);

        _lastDebugInfo = _lastDebugInfo.copyWith(
          processedImage: enhancedContrastImageCopy,
        );
      }

      // Automatically find the board bounding box
      final math.Rectangle<int>? boardRect =
          _findBoardBoundingBox(processImage);

      // --- Check if detected board is too small ---
      math.Rectangle<int>? finalBoardRect = boardRect;
      if (finalBoardRect != null &&
          (finalBoardRect.width < 200 || finalBoardRect.height < 200)) {
        logger.w(
            "Detected board area (${finalBoardRect.width}x${finalBoardRect.height}) is smaller than 200x200. Discarding and using full image.");
        finalBoardRect = null; // Discard the small rectangle
      }

      // --- Final Fallback: Use Full Image if Detection Failed or Result Was Too Small ---
      if (finalBoardRect == null) {
        // Log only if it wasn't already logged as too small
        if (boardRect != null) {
          // boardRect was not null initially, but discarded due to size
        } else {
          logger.w(
              "Board detection failed using all methods. Falling back to using the entire image as the board area.");
        }

        // Determine the largest square that fits within the processed image
        final int squareSize =
            math.min(_processedImageWidth, _processedImageHeight);

        // Center the square within the processed image dimensions
        final int leftOffset = (_processedImageWidth - squareSize) ~/ 2;
        final int topOffset = (_processedImageHeight - squareSize) ~/ 2;

        finalBoardRect =
            math.Rectangle<int>(leftOffset, topOffset, squareSize, squareSize);

        // Update debug info to reflect fallback
        _lastDebugInfo = _lastDebugInfo.copyWith(boardRect: finalBoardRect);
      } else {
        // finalBoardRect is the valid, sufficiently large rectangle detected earlier
        logger.i("Board bounding box found and validated: $finalBoardRect");
        // Debug info for boardRect is already updated within _findBoardBoundingBox
      }

      // --- Proceed with point generation and analysis using finalBoardRect ---

      // Generate standard board points based on the final detected rectangle
      final List<BoardPoint> boardPoints = createRefinedBoardPoints(
          processImage, finalBoardRect); // Use finalBoardRect here

      // Save detected board points
      _lastDetectedPoints = boardPoints;

      // Update debug info with board points
      _lastDebugInfo = _lastDebugInfo.copyWith(
        boardPoints: boardPoints,
      );

      // Estimate the board color for piece detection using the final rectangle
      final Rgb boardColor = _estimateBoardColor(
          unprocessedImage, finalBoardRect); // Use finalBoardRect

      // Update debug info with board color
      _lastDebugInfo = _lastDebugInfo.copyWith(
        boardColor: boardColor,
      );

      // First pass: scan points to determine dominant colors and thresholds
      // Use unprocessed image for more accurate color profile
      final ColorProfile colorProfile =
          _buildColorProfile(unprocessedImage, boardPoints);
      logger.i(
          "Color profile: white=${colorProfile.whiteMean.toStringAsFixed(1)}, "
          "black=${colorProfile.blackMean.toStringAsFixed(1)}, empty=${colorProfile.emptyMean.toStringAsFixed(1)}");

      // Update debug info with color profile
      _lastDebugInfo = _lastDebugInfo.copyWith(
        colorProfile: colorProfile,
      );

      // Second pass: use refined thresholds to accurately classify each point
      // Use unprocessed image for actual piece detection

      // Get configured piece colors
      final Color configuredWhiteColor = DB().colorSettings.whitePieceColor;
      final Color configuredBlackColor = DB().colorSettings.blackPieceColor;
      final Rgb configuredWhiteRgb = _rgbFromColor(configuredWhiteColor);
      final Rgb configuredBlackRgb = _rgbFromColor(configuredBlackColor);

      for (int i = 0; i < 24 && i < boardPoints.length; i++) {
        final BoardPoint point = boardPoints[i];
        final PieceColor detectedColor = _detectPieceAtPoint(
            unprocessedImage,
            point,
            characteristics,
            colorProfile,
            boardColor,
            configuredWhiteRgb,
            configuredBlackRgb,
            pieceColorMatchThreshold: pieceColorMatchThreshold,
            boardColorDistanceThreshold: boardColorDistanceThreshold,
            blackSaturationThreshold: blackSaturationThreshold,
            blackColorVarianceThreshold: blackColorVarianceThreshold);
        result[i] = detectedColor;
      }

      // Post-process to enforce game rules and improve consistency
      final Map<int, PieceColor> enhancedResult =
          _applyConsistencyRules(result);

      // Log recognition results
      int whiteCount = 0, blackCount = 0;
      for (final PieceColor color in enhancedResult.values) {
        if (color == PieceColor.white) {
          whiteCount++;
        }
        if (color == PieceColor.black) {
          blackCount++;
        }
      }
      logger.i("FINAL COUNT   white=$whiteCount, black=$blackCount   "
          "(detected from ${boardPoints.length} lattice points)");

      return enhancedResult;
    } catch (e, stacktrace) {
      logger.e("Error recognizing board: $e\n$stacktrace");
      return result; // Return default result on error
    }
  }

  // --- Placeholder / Stub Implementations for Missing Methods ---

  /// Placeholder: Enhance contrast for low-contrast images.
  static img.Image _enhanceLowContrastImage(img.Image image) {
    logger.w(
        "_enhanceLowContrastImage is not implemented. Returning original image.");
    // Basic contrast adjustment as a placeholder
    return img.adjustColor(image, contrast: 1.5); // Apply some contrast
  }

  /// Placeholder: Estimate the dominant background color of the board.
  static Rgb _estimateBoardColor(
      img.Image image, math.Rectangle<int>? boardRect) {
    logger.w("_estimateBoardColor is not implemented. Returning default grey.");
    if (boardRect == null) {
      return const Rgb(128, 128, 128);
    }

    // Simple estimation: Average color of a few points near the center, avoiding grid lines
    int rSum = 0, gSum = 0, bSum = 0, count = 0;
    final int centerX = boardRect.left + boardRect.width ~/ 2;
    final int centerY = boardRect.top + boardRect.height ~/ 2;
    final int offset = boardRect.width ~/ 10; // Sample away from center

    final List<math.Point<int>> samplePoints = <math.Point<int>>[
      math.Point<int>(centerX + offset, centerY + offset),
      math.Point<int>(centerX - offset, centerY + offset),
      math.Point<int>(centerX + offset, centerY - offset),
      math.Point<int>(centerX - offset, centerY - offset),
    ];

    for (final math.Point<int> p in samplePoints) {
      if (p.x >= 0 && p.x < image.width && p.y >= 0 && p.y < image.height) {
        final img.Pixel pixel = image.getPixel(p.x, p.y);
        rSum += pixel.r.toInt();
        gSum += pixel.g.toInt();
        bSum += pixel.b.toInt();
        count++;
      }
    }

    if (count > 0) {
      return Rgb(rSum ~/ count, gSum ~/ count, bSum ~/ count);
    } else {
      return const Rgb(128, 128, 128); // Default grey
    }
  }

  /// Placeholder: Detect the color of a piece at a specific board point.
  static PieceColor _detectPieceAtPoint(
    img.Image image,
    BoardPoint point,
    ImageCharacteristics characteristics,
    ColorProfile colorProfile,
    Rgb boardColor,
    Rgb configuredWhiteRgb,
    Rgb configuredBlackRgb, {
    double? pieceColorMatchThreshold,
    double? boardColorDistanceThreshold,
    double? blackSaturationThreshold,
    int? blackColorVarianceThreshold,
  }) {
    // Use provided values or fall back to static variables
    final double pColorMatchThreshold = pieceColorMatchThreshold ??
        BoardImageRecognitionService.pieceColorMatchThreshold;
    final double bColorDistanceThreshold = boardColorDistanceThreshold ??
        BoardImageRecognitionService.boardColorDistanceThreshold;
    final double bSaturationThreshold = blackSaturationThreshold ??
        BoardImageRecognitionService.blackSaturationThreshold;
    final int bColorVarianceThreshold = blackColorVarianceThreshold ??
        BoardImageRecognitionService.blackColorVarianceThreshold;

    int brightnessSum = 0;
    int sampleCount = 0;
    final int sampleRadius =
        (point.radius * 0.6).round().clamp(1, 10); // Sample smaller area

    // Additional color statistics for improved detection
    int rSum = 0, gSum = 0, bSum = 0;
    double saturationSum = 0;
    int colorVarianceSum = 0;

    for (int dy = -sampleRadius; dy <= sampleRadius; dy++) {
      for (int dx = -sampleRadius; dx <= sampleRadius; dx++) {
        if (dx * dx + dy * dy <= sampleRadius * sampleRadius) {
          final int sx = point.x + dx;
          final int sy = point.y + dy;
          if (sx >= 0 && sx < image.width && sy >= 0 && sy < image.height) {
            final img.Pixel pixel = image.getPixel(sx, sy);
            final int brightness = _calculateBrightness(pixel);
            brightnessSum += brightness;

            // Accumulate color info
            rSum += pixel.r.toInt();
            gSum += pixel.g.toInt();
            bSum += pixel.b.toInt();
            saturationSum += _calculateSaturation(pixel);
            colorVarianceSum += _calculateColorVariance(pixel);

            sampleCount++;
          }
        }
      }
    }

    if (sampleCount == 0) {
      return PieceColor.none;
    }

    final double avgBrightness = brightnessSum / sampleCount.toDouble();
    final Rgb avgRgb =
        Rgb(rSum ~/ sampleCount, gSum ~/ sampleCount, bSum ~/ sampleCount);
    final double avgSaturation = saturationSum / sampleCount.toDouble();
    final double avgColorVariance = colorVarianceSum / sampleCount.toDouble();

    // --- Add check: Force empty if color is very close to board and far from pieces ---
    // Get configured board background color
    final Color configuredBoardColor = DB().colorSettings.boardBackgroundColor;
    final Rgb configuredBoardRgb = _rgbFromColor(configuredBoardColor);

    // Calculate distances
    final double distToBoard = avgRgb.distanceTo(configuredBoardRgb);
    final double distToWhitePiece = avgRgb.distanceTo(configuredWhiteRgb);
    final double distToBlackPiece = avgRgb.distanceTo(configuredBlackRgb);

    // Define thresholds for this check
    const double boardProximityThreshold =
        25.0; // How close to board color to be considered board
    const double pieceDistanceThreshold =
        45.0; // How far from piece colors to be considered not a piece

    // Apply the rule
    if (distToBoard < boardProximityThreshold &&
        distToWhitePiece > pieceDistanceThreshold &&
        distToBlackPiece > pieceDistanceThreshold) {
      logger.d(
          "Point at (${point.x}, ${point.y}): OVERRIDE to EMPTY. Color $avgRgb is very close to board bg $configuredBoardRgb (dist: ${distToBoard.toStringAsFixed(1)}) and far from pieces (W: ${distToWhitePiece.toStringAsFixed(1)}, B: ${distToBlackPiece.toStringAsFixed(1)}).");
      return PieceColor.none;
    }
    // --- End of board color override check ---

    // --- Original classification logic based on brightness distance ---
    final double distToWhite = (avgBrightness - colorProfile.whiteMean).abs();
    final double distToBlack = (avgBrightness - colorProfile.blackMean).abs();
    final double distToEmpty = (avgBrightness - colorProfile.emptyMean).abs();

    // Use standard deviations for normalization, ensuring they are not zero
    final double whiteStd = math.max(1.0, colorProfile.whiteStd);
    final double blackStd = math.max(1.0, colorProfile.blackStd);
    final double emptyStd = math.max(1.0, colorProfile.emptyStd);

    // Normalized distances (lower is better)
    final double normDistWhite = distToWhite / whiteStd;
    final double normDistBlack = distToBlack / blackStd;
    final double normDistEmpty = distToEmpty / emptyStd;

    // --- Calculate evidence scores --- //
    // Base scores on inverse normalized distance
    double whiteScore = 1.0 / (normDistWhite + 0.1);
    double blackScore = 1.0 / (normDistBlack + 0.1);
    double emptyScore = 1.0 / (normDistEmpty + 0.1);

    // --- Adjust scores based on color properties --- //

    // 1. Black Piece Check:
    // Calculate distance to configured black color
    final double distToConfigBlack = avgRgb.distanceTo(configuredBlackRgb);
    final bool configBlackMatch = distToConfigBlack < pColorMatchThreshold;

    // Significantly boost black score if color properties match black characteristics
    if (avgBrightness <
            colorProfile.blackMean + blackStd * 1.5 && // Check brightness range
        avgSaturation <
            bSaturationThreshold * 255 && // Check saturation (scaled)
        avgColorVariance < bColorVarianceThreshold * 1.5) {
      // Check variance (allow some margin)
      blackScore *= 2.0; // Moderate boost for properties match
      logger.d(
          "  Point (${point.x}, ${point.y}): Moderate evidence for BLACK based on color properties (sat: ${avgSaturation.toStringAsFixed(1)}, var: ${avgColorVariance.toStringAsFixed(1)})");
      // If it also matches configured color, boost even more
      if (configBlackMatch) {
        blackScore *= 2.0; // Additional strong boost for configured color match
        logger.d(
            "  Point (${point.x}, ${point.y}): Strong boost for BLACK due to configured color match (dist: ${distToConfigBlack.toStringAsFixed(1)})");
      }
    }
    // If properties don't match black, but it matches configured color strongly, still give a boost
    else if (configBlackMatch) {
      blackScore *= 2.0; // Strong boost just for configured match
      logger.d(
          "  Point (${point.x}, ${point.y}): Strong boost for BLACK due to configured color match (dist: ${distToConfigBlack.toStringAsFixed(1)})");
    }

    // 2. White Piece Check:
    // Calculate distance to configured white color
    final double distToConfigWhite = avgRgb.distanceTo(configuredWhiteRgb);
    final bool configWhiteMatch = distToConfigWhite < pColorMatchThreshold;

    // Boost white score if brightness is high
    if (avgBrightness > colorProfile.whiteMean - whiteStd * 0.5) {
      whiteScore *= 1.2; // Slight boost for high brightness
    }
    // Boost significantly if it matches configured white color
    if (configWhiteMatch) {
      whiteScore *= 2.5; // Strong boost for configured match
      logger.d(
          "  Point (${point.x}, ${point.y}): Strong boost for WHITE due to configured color match (dist: ${distToConfigWhite.toStringAsFixed(1)})");
    }

    // 3. Empty Point Check (Board Color):
    // Boost empty score if the average color is very close to the estimated board color
    final double distToBoardColor = avgRgb.distanceTo(boardColor);
    if (distToBoardColor < bColorDistanceThreshold * 0.75) {
      // Use a stricter threshold here
      emptyScore *= 2.0;
      logger.d(
          "  Point (${point.x}, ${point.y}): Strong evidence for EMPTY based on board color proximity (dist: ${distToBoardColor.toStringAsFixed(1)})");
    }
    // Also boost empty score slightly if it's close in brightness
    else if (normDistEmpty < 0.8) {
      // If brightness is close to empty mean
      emptyScore *= 1.2;
    }

    // Determine final classification based on highest score
    PieceColor result;
    if (whiteScore > blackScore && whiteScore > emptyScore) {
      result = PieceColor.white;
    } else if (blackScore > whiteScore && blackScore > emptyScore) {
      // Additional check: ensure black score isn't just slightly higher than empty
      // And brightness is significantly lower than empty
      if (blackScore > emptyScore * 1.2 ||
          avgBrightness < colorProfile.emptyMean - emptyStd * 0.5) {
        result = PieceColor.black;
      } else {
        result = PieceColor
            .none; // Prefer empty if black score is marginal and brightness not low enough
        logger.d(
            "  Point (${point.x}, ${point.y}): Classified as EMPTY despite high black score due to marginal difference/brightness.");
      }
    } else {
      result = PieceColor.none;
    }

    // Log detailed detection information for debugging
    logger.d(
        "Point at (${point.x}, ${point.y}): brightness=${avgBrightness.toStringAsFixed(1)}, "
        "rgb=$avgRgb, sat=${avgSaturation.toStringAsFixed(1)}, var=${avgColorVariance.toStringAsFixed(1)}, "
        "distBoard=${distToBoardColor.toStringAsFixed(1)} | "
        "distConf(W/B): ${distToConfigWhite.toStringAsFixed(1)}/${distToConfigBlack.toStringAsFixed(1)} | " // Added config distances
        "normDists(W/B/E): ${normDistWhite.toStringAsFixed(2)}/${normDistBlack.toStringAsFixed(2)}/${normDistEmpty.toStringAsFixed(2)} | "
        "scores(W/B/E): ${whiteScore.toStringAsFixed(2)}/${blackScore.toStringAsFixed(2)}/${emptyScore.toStringAsFixed(2)} => $result");

    return result;
  }

  /// Placeholder: Apply game rules or consistency checks to the detected state.
  static Map<int, PieceColor> _applyConsistencyRules(
      Map<int, PieceColor> detectedState) {
    logger.w(
        "_applyConsistencyRules is not implemented. Returning original state.");
    // Example: Could check piece counts (<= 9), enforce adjacency rules, etc.
    return detectedState;
  }

  /// Placeholder: Morphological dilation.
  static List<List<bool>> _dilate(List<List<bool>> mask, int radius) {
    logger.w("_dilate is not implemented. Returning original mask.");
    if (mask.isEmpty || mask[0].isEmpty) {
      return mask;
    }
    // Basic implementation needed here using a structuring element
    // For now, just return the input to allow compilation
    return mask;
  }

  /// Placeholder: Morphological erosion.
  static List<List<bool>> _erode(List<List<bool>> mask, int radius) {
    logger.w("_erode is not implemented. Returning original mask.");
    if (mask.isEmpty || mask[0].isEmpty) {
      return mask;
    }
    // Basic implementation needed here using a structuring element
    // For now, just return the input to allow compilation
    return mask;
  }

  // --- End Placeholder Methods ---

  /// Resize the image to a processable size while maintaining aspect ratio
  static img.Image _resizeForProcessing(img.Image original) {
    if (original.width <= _processingWidth &&
        original.height <= _processingWidth) {
      return original; // No need to resize small images
    }

    // Calculate new dimensions maintaining aspect ratio
    int newWidth, newHeight;
    if (original.width > original.height) {
      newWidth = _processingWidth;
      newHeight = (_processingWidth * original.height / original.width).round();
    } else {
      newHeight = _processingWidth;
      newWidth = (_processingWidth * original.width / original.height).round();
    }

    // Resize the image using average interpolation for potentially better quality
    return img.copyResize(original,
        width: newWidth,
        height: newHeight,
        interpolation: img.Interpolation.average);
  }

  /// Enhance image for better feature detection by improving contrast and reducing noise
  ///
  /// @param inputImage The image to enhance
  /// @param contrastEnhancementFactor Custom contrast enhancement factor
  /// @return Enhanced image
  static img.Image _enhanceImageForProcessing(
    img.Image inputImage, {
    double? contrastEnhancementFactor,
  }) {
    // Use the passed parameter or fall back to static variable
    final double usedFactor = contrastEnhancementFactor ??
        BoardImageRecognitionService.contrastEnhancementFactor;

    // Create a copy to work with
    // No need to copyRotate with angle 0, just copy is fine
    final img.Image enhancedImage = img.Image.from(inputImage); // Simple copy

    // First apply noise reduction (Gaussian blur) - radius 1 is very mild
    final img.Image denoised = img.gaussianBlur(enhancedImage, radius: 1);

    // Apply contrast enhancement to make pieces stand out more
    return img.adjustColor(
      denoised,
      contrast: usedFactor,
    );
  }

  /// Analyze image characteristics to determine appropriate thresholds for piece detection
  ///
  /// @param image The image to analyze
  /// @param whiteBrightnessThresholdBase Base threshold for white pieces brightness
  /// @param blackBrightnessThresholdBase Base threshold for black pieces brightness
  /// @param pieceThreshold Custom piece detection threshold
  /// @return ImageCharacteristics object with analysis results
  static ImageCharacteristics _analyzeImageCharacteristics(
    img.Image image, {
    int? whiteBrightnessThresholdBase,
    int? blackBrightnessThresholdBase,
    double? pieceThreshold,
  }) {
    // Use provided values or fall back to static variables
    final int whiteThresholdBase = whiteBrightnessThresholdBase ??
        BoardImageRecognitionService.whiteBrightnessThreshold;
    final int blackThresholdBase = blackBrightnessThresholdBase ??
        BoardImageRecognitionService.blackBrightnessThreshold;
    final double pThreshold =
        pieceThreshold ?? BoardImageRecognitionService.pieceThreshold;

    int totalBrightness = 0;
    int pixelCount = 0;

    double minBrightness = 255;
    double maxBrightness = 0;

    // Sample the image at regular intervals for performance
    const int step = 5;
    for (int y = 0; y < image.height; y += step) {
      for (int x = 0; x < image.width; x += step) {
        final img.Pixel pixel = image.getPixel(x, y);
        final int brightness = _calculateBrightness(pixel);

        totalBrightness += brightness;
        pixelCount++;
        minBrightness = math.min(minBrightness, brightness.toDouble());
        maxBrightness = math.max(maxBrightness, brightness.toDouble());
      }
    }

    // Calculate average brightness
    final double avgBrightness =
        pixelCount > 0 ? totalBrightness / pixelCount : 128;

    // Calculate statistics to determine lighting conditions

    // Contrast Ratio (simplified: max/min, avoiding division by zero)
    final double contrastRatio = (maxBrightness - minBrightness) /
        (avgBrightness + 1); // Another way to estimate contrast

    // Determine dominant colors and image properties
    // Adjusted logic: Consider average brightness more strongly
    final bool isDarkBackground = avgBrightness < 110; // Lowered threshold
    final bool isHighContrast =
        (maxBrightness - minBrightness) > 100; // Simpler contrast check

    // Adaptively adjust threshold baseline based on image characteristics
    final int whiteThreshold = isDarkBackground
        ? whiteThresholdBase - 15 // Less reduction for dark
        : whiteThresholdBase +
            (avgBrightness > 160 ? 20 : 0); // Increase more if very bright

    final int blackThreshold = isDarkBackground
        ? blackThresholdBase - 15 // Less reduction for dark
        : blackThresholdBase +
            (avgBrightness < 130 ? -15 : 0); // Decrease more if quite dim

    // Ensure sufficient gap between black and white thresholds to avoid overlap
    final int adjustedBlackThreshold =
        math.min(blackThreshold, whiteThreshold - 40); // Increased gap

    // Adjust piece detection threshold slightly based on contrast
    final double adjustedPieceThreshold =
        isHighContrast ? pThreshold - 0.05 : pThreshold;

    return ImageCharacteristics(
        averageBrightness: avgBrightness,
        isDarkBackground: isDarkBackground,
        isHighContrast: isHighContrast,
        whiteBrightnessThreshold: whiteThreshold,
        blackBrightnessThreshold: adjustedBlackThreshold,
        pieceDetectionThreshold: adjustedPieceThreshold,
        contrastRatio: contrastRatio // Use the calculated ratio
        );
  }

  /// Calculate brightness of a pixel using a weighted method (Luma-like)
  static int _calculateBrightness(img.Pixel pixel) {
    // Standard Luma calculation (Rec. 601)
    return (0.299 * pixel.r.toInt() +
            0.587 * pixel.g.toInt() +
            0.114 * pixel.b.toInt())
        .round();
  }

  /// Calculate pixel saturation (HSL/HSV definition)
  static double _calculateSaturation(img.Pixel pixel) {
    final int r = pixel.r.toInt();
    final int g = pixel.g.toInt();
    final int b = pixel.b.toInt();

    final int maxChannel = math.max(r, math.max(g, b));
    final int minChannel = math.min(r, math.min(g, b));
    final int delta = maxChannel - minChannel;

    // Avoid division by zero for black/grey
    if (delta == 0) {
      return 0.0;
    }

    // Calculate lightness/luminance (average of max and min)
    final double lightness = (maxChannel + minChannel) / 2.0;

    // Calculate saturation
    if (lightness < 128) {
      // Use maxChannel for darker colors
      return (delta * 255.0) /
          (maxChannel +
              minChannel); // Scale to ~0-255 range similar to brightness
    } else {
      // Use 255-minChannel for lighter colors
      return (delta * 255.0) /
          (510 - maxChannel - minChannel); // Scale to ~0-255 range
    }
    // Alternative simple calculation (less accurate perceptually)
    // if (maxChannel == 0) return 0.0;
    // return (delta / maxChannel.toDouble());
  }

  /// Calculate the variance of RGB channels for a pixel (max - min)
  static int _calculateColorVariance(img.Pixel pixel) {
    final int r = pixel.r.toInt();
    final int g = pixel.g.toInt();
    final int b = pixel.b.toInt();

    final int maxChannel = math.max(r, math.max(g, b));
    final int minChannel = math.min(r, math.min(g, b));

    // Return the difference between the maximum and minimum channel values
    return maxChannel - minChannel;
  }

  /// Helper function to extract a percentile range from a sorted list.
  static List<int> _takePercentile(List<int> sorted, double from, double to) {
    if (sorted.isEmpty) {
      return <int>[];
    }

    int startIndex = (sorted.length * from.clamp(0.0, 1.0)).floor();
    int endIndex = (sorted.length * to.clamp(0.0, 1.0)).floor();

    // Make sure the start index is less than the end index and both are in the valid range
    startIndex = startIndex.clamp(0, sorted.length - 1);
    endIndex = endIndex.clamp(startIndex + 1, sorted.length);

    return sorted.sublist(startIndex, endIndex);
  }

  /// Build a color profile from the board to improve piece detection
  static ColorProfile _buildColorProfile(
      img.Image image, List<BoardPoint> points) {
    final List<int> whiteBrightness = <int>[];
    final List<int> blackBrightness = <int>[];
    final List<int> emptyBrightness = <int>[];
    final List<int> allBrightness = <int>[];

    // Get image characteristics for dynamic thresholding during profile build
    // final ImageCharacteristics characteristics = // No longer using global characteristics here
    //     _analyzeImageCharacteristics(image);

    logger.i("Building color profile from ${points.length} board points");

    // Collect average brightness for all points first
    final Map<int, int> pointIndexToBrightness = <int, int>{};
    final List<int> allAvgBrightness = <int>[];

    for (int i = 0; i < points.length; i++) {
      final BoardPoint point = points[i];
      // ... (sampling logic remains the same) ...
      int localBrightnessSum = 0;
      int sampleCount = 0;
      final List<int> pointColors = <int>[]; // Keep for debug logging if needed

      final int sampleRadius = (point.radius * 0.7).round().clamp(2, 12);
      for (int dx = -sampleRadius; dx <= sampleRadius; dx += 1) {
        for (int dy = -sampleRadius; dy <= sampleRadius; dy += 1) {
          if (dx * dx + dy * dy <= sampleRadius * sampleRadius) {
            final int sx = point.x + dx;
            final int sy = point.y + dy;

            if (sx >= 0 && sx < image.width && sy >= 0 && sy < image.height) {
              final img.Pixel pixel = image.getPixel(sx, sy);
              final int brightness = _calculateBrightness(pixel);
              localBrightnessSum += brightness;
              sampleCount++;
              pointColors.add(brightness);
            }
          }
        }
      }

      if (sampleCount > 0) {
        final int avgBrightness = localBrightnessSum ~/ sampleCount;
        pointIndexToBrightness[i] = avgBrightness;
        allAvgBrightness.add(avgBrightness);
      }
    }

    if (allAvgBrightness.isEmpty) {
      logger.w(
          "No brightness samples collected for color profile. Returning default.");
      return ColorProfile(
          whiteMean: 200,
          blackMean: 50,
          emptyMean: 128,
          whiteStd: 30,
          blackStd: 30,
          emptyStd: 30);
    }

    // Sort brightness values to use quantiles for initial classification
    allAvgBrightness.sort();

    // Estimate quantile thresholds (e.g., darkest 30%, brightest 30%)
    // Adjust these percentages based on expected board state if needed
    final int q30Index = (allAvgBrightness.length * 0.30)
        .round()
        .clamp(0, allAvgBrightness.length - 1);
    final int q70Index = (allAvgBrightness.length * 0.70)
        .round()
        .clamp(0, allAvgBrightness.length - 1);
    final int blackThreshold = allAvgBrightness[q30Index];
    final int whiteThreshold = allAvgBrightness[q70Index];

    logger.i(
        "Initial classification thresholds based on distribution: Black <= $blackThreshold, White >= $whiteThreshold");

    // Initial classification based on distribution
    for (final int pointIndex in pointIndexToBrightness.keys) {
      final int avgBrightness = pointIndexToBrightness[pointIndex]!;
      allBrightness.add(avgBrightness); // Still collect all for fallback

      if (avgBrightness >= whiteThreshold) {
        whiteBrightness.add(avgBrightness);
        logger.d(
            "  Point $pointIndex (brightness $avgBrightness) -> Initial WHITE");
      } else if (avgBrightness <= blackThreshold) {
        blackBrightness.add(avgBrightness);
        logger.d(
            "  Point $pointIndex (brightness $avgBrightness) -> Initial BLACK");
      } else {
        emptyBrightness.add(avgBrightness);
        logger.d(
            "  Point $pointIndex (brightness $avgBrightness) -> Initial EMPTY");
      }
    }

    // --- Fallback handling remains the same ---
    // Sort all collected brightness values for percentile calculation (used in fallback)
    allBrightness.sort();

    // Log the overall brightness distribution
    logger.i("All brightness values (sorted): ${allBrightness.join(', ')}");
    if (allBrightness.isNotEmpty) {
      final double min = allBrightness.first.toDouble();
      final double max = allBrightness.last.toDouble();
      final double median = allBrightness[allBrightness.length ~/ 2].toDouble();
      final double q1 = allBrightness[allBrightness.length ~/ 4].toDouble();
      final double q3 = allBrightness[3 * allBrightness.length ~/ 4].toDouble();
      logger.i(
          "Brightness distribution: min=$min, Q1=$q1, median=$median, Q3=$q3, max=$max");
    }

    // If black or white samples are empty, take the darkest/brightest 15%
    // from all samples as pseudo-samples.
    if (blackBrightness.isEmpty && allBrightness.length > 5) {
      // Add minimum size check
      logger.w(
          "No black samples found for profile, using darkest 15% as fallback.");
      blackBrightness
          .addAll(_takePercentile(allBrightness, 0.0, 0.15)); // darkest 15 %
    }
    if (whiteBrightness.isEmpty && allBrightness.length > 5) {
      // Add minimum size check
      logger.w(
          "No white samples found for profile, using brightest 15% as fallback.");
      whiteBrightness
          .addAll(_takePercentile(allBrightness, 0.85, 1.0)); // brightest 15 %
    }

    // If empty samples are empty (rare, e.g., full board), use the middle 20% as fallback.
    if (emptyBrightness.isEmpty && allBrightness.length > 5) {
      // Add minimum size check
      logger.w(
          "No empty samples found for profile, using middle 20% as fallback.");
      emptyBrightness.addAll(_takePercentile(allBrightness, 0.4, 0.6));
    }

    // Calculate means for each class
    final double whiteMean = _calculateMean(whiteBrightness);
    final double blackMean = _calculateMean(blackBrightness);
    final double emptyMean = _calculateMean(emptyBrightness);

    // Calculate standard deviations
    // Ensure std dev is not zero, provide a minimum value
    final double whiteStd =
        math.max(15.0, _calculateStdDev(whiteBrightness, whiteMean));
    final double blackStd =
        math.max(15.0, _calculateStdDev(blackBrightness, blackMean));
    final double emptyStd =
        math.max(15.0, _calculateStdDev(emptyBrightness, emptyMean));

    // Log detailed statistics
    logger.i("Color profile statistics:");
    logger.i(
        "  WHITE: mean=$whiteMean, std=$whiteStd, samples=${whiteBrightness.length}");
    logger.i(
        "  BLACK: mean=$blackMean, std=$blackStd, samples=${blackBrightness.length}");
    logger.i(
        "  EMPTY: mean=$emptyMean, std=$emptyStd, samples=${emptyBrightness.length}");

    // Log classification thresholds
    logger.i("Classification thresholds:");
    logger.i("  WHITE threshold: >${whiteMean - whiteStd}");
    logger.i("  BLACK threshold: <${blackMean + blackStd}");
    logger
        .i("  EMPTY range: ${emptyMean - emptyStd} to ${emptyMean + emptyStd}");

    return ColorProfile(
        whiteMean: whiteMean,
        blackMean: blackMean,
        emptyMean: emptyMean,
        whiteStd: whiteStd,
        blackStd: blackStd,
        emptyStd: emptyStd);
  }

  /// Calculate mean of a list of values
  static double _calculateMean(List<int> values) {
    if (values.isEmpty) {
      return 128.0; // Default to mid-gray if no samples
    }
    // Use fold for conciseness
    return values.fold<int>(0, (int sum, int item) => sum + item) /
        values.length;
  }

  /// Calculate standard deviation of a list of values
  static double _calculateStdDev(List<int> values, double mean) {
    if (values.length < 2) {
      // Need at least 2 values for standard deviation
      return 30.0; // Default to reasonable value if not enough samples
    }

    double sumSquaredDiff = 0.0;
    for (final int value in values) {
      final double diff = value - mean;
      sumSquaredDiff += diff * diff;
    }
    // Use N-1 for sample standard deviation if appropriate, but N is fine for profile
    return math.sqrt(sumSquaredDiff / values.length);
  }

  /// Check if a color is likely to be board color (wooden/neutral) based on HSV/RGB properties
  /// or matches the configured board background color
  static bool _isLikelyBoardColor(Rgb c) {
    // Reduce the distance threshold from the configured chessboard background color to improve matching accuracy
    final Color boardBackgroundColor =
        DB().colorSettings.boardBackgroundColor; // Nullable
    if (boardBackgroundColor != null) {
      // Reduce the threshold from 35 to 25 to improve detection accuracy
      if (_colorDistance(c, _rgbFromColor(boardBackgroundColor)) < 25) {
        return true;
      }
    }

    // If the chessboard color is not configured or does not match, try to use the general color feature judgment
    // Convert RGB to HSV for more robust color space analysis
    final double r = c.r / 255.0;
    final double g = c.g / 255.0;
    final double b = c.b / 255.0;
    final double maxC = math.max(r, math.max(g, b));
    final double minC = math.min(r, math.min(g, b));
    final double delta = maxC - minC;

    // Value (Brightness) check first - avoid very dark or very bright colors
    final double v = maxC; // Value is the max component
    if (v < 0.2 || v > 0.95) {
      return false;
    }

    // Saturation check - board colors are usually not highly saturated
    final double s = maxC == 0 ? 0 : delta / maxC;
    if (s > 0.65) {
      // Allow slightly higher saturation but exclude vivid colors
      return false;
    }

    // Hue check - typical wood colors are in the orange/brown/yellow range
    // But also consider greyish tones if saturation is low
    if (s < 0.15) {
      // Low saturation - likely greyish/neutral tone
      // Accept mid-range brightness neutrals (avoids pure black/white lines)
      return v > 0.3 && v < 0.85;
    } else {
      // Calculate Hue for more saturated colors
      double h = 0;
      if (delta == 0) {
        // Should not happen due to saturation check, but safe guard
        h = 0;
      } else if (maxC == r) {
        h = ((g - b) / delta) % 6;
      } else if (maxC == g) {
        h = ((b - r) / delta) + 2;
      } else {
        // maxC == b
        h = ((r - g) / delta) + 4;
      }
      h = (h * 60 + 360) % 360; // Hue in degrees [0, 360)

      // Allow wider range for wood-like hues (yellows, oranges, some reds)
      // Hue range for wood tones: ~15 to 60 degrees
      return h >= 15 && h <= 65; // Adjusted range
    }
  }

  /// Convert Flutter's Color to internal Rgb representation
  static Rgb _rgbFromColor(Color color) {
    // Convert the new double-based channel values (0.0 – 1.0) to 0–255 ints.
    int toInt8(double channel) => (channel * 255).round().clamp(0, 255);
    return Rgb(
      toInt8(color.r),
      toInt8(color.g),
      toInt8(color.b),
    );
  }

  /// Calculate Euclidean distance between two RGB colors
  static double _colorDistance(Rgb a, Rgb b) {
    final double dr = (a.r - b.r).toDouble();
    final double dg = (a.g - b.g).toDouble();
    final double db = (a.b - b.b).toDouble();
    return math.sqrt(dr * dr + dg * dg + db * db);
  }

  /// Board border detection method using color settings
  static math.Rectangle<int>? _findBoardBoundingBoxUsingColorSettings(
      img.Image imgSrc) {
    logger.i("Using color settings to find board boundary...");

    // Get board background and line colors from settings
    final Color boardBackgroundColor = DB().colorSettings.boardBackgroundColor;
    final Color boardLineColor = DB().colorSettings.boardLineColor;
    final Rgb boardBgRgb = _rgbFromColor(boardBackgroundColor);
    final Rgb boardLineRgb = _rgbFromColor(boardLineColor);

    logger.i("Board background color: $boardBgRgb, line color: $boardLineRgb");

    final int imgHeight = imgSrc.height;
    final int imgWidth = imgSrc.width;

    // Step 1: Create board mask using background color
    final List<List<bool>> boardMask = List<List<bool>>.generate(
        imgHeight, (_) => List<bool>.filled(imgWidth, false));

    // Background color distance threshold
    const double bgColorThreshold = 30.0;

    // Create background mask
    for (int y = 0; y < imgHeight; y++) {
      for (int x = 0; x < imgWidth; x++) {
        final img.Pixel pixel = imgSrc.getPixel(x, y);
        final Rgb rgb = Rgb(pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt());

        // Check if pixel is close to board background color
        if (_colorDistance(rgb, boardBgRgb) < bgColorThreshold) {
          boardMask[y][x] = true;
        }
      }
    }

    // Step 2: Find largest connected component as board area
    final List<List<int>> labels = List<List<int>>.generate(
        imgHeight, (_) => List<int>.filled(imgWidth, 0));
    int nextLabel = 1;
    int largestLabel = 0;
    int maxComponentSize = 0;

    // Use BFS to find connected components
    for (int y = 0; y < imgHeight; y++) {
      for (int x = 0; x < imgWidth; x++) {
        if (boardMask[y][x] && labels[y][x] == 0) {
          int currentSize = 0;
          final Queue<_Point> queue = Queue<_Point>();

          queue.add(_Point(x, y));
          labels[y][x] = nextLabel;

          while (queue.isNotEmpty) {
            final _Point current = queue.removeFirst();
            currentSize++;

            // Check 8 adjacent pixels
            for (int dy = -1; dy <= 1; dy++) {
              for (int dx = -1; dx <= 1; dx++) {
                if (dx == 0 && dy == 0) {
                  continue;
                }
                final int nx = current.x + dx;
                final int ny = current.y + dy;

                if (nx >= 0 &&
                    nx < imgWidth &&
                    ny >= 0 &&
                    ny < imgHeight &&
                    boardMask[ny][nx] &&
                    labels[ny][nx] == 0) {
                  labels[ny][nx] = nextLabel;
                  queue.add(_Point(nx, ny));
                }
              }
            }
          }

          // Update largest component
          if (currentSize > maxComponentSize) {
            maxComponentSize = currentSize;
            largestLabel = nextLabel;
          }
          nextLabel++;
        }
      }
    }

    // Get largest component's bounding box
    if (largestLabel == 0) {
      logger.w(
          "No valid board background area found, trying line color detection");
      return null;
    }

    // Calculate largest component's bounding box
    int minX = imgWidth, minY = imgHeight, maxX = 0, maxY = 0;

    for (int y = 0; y < imgHeight; y++) {
      for (int x = 0; x < imgWidth; x++) {
        if (labels[y][x] == largestLabel) {
          minX = math.min(minX, x);
          minY = math.min(minY, y);
          maxX = math.max(maxX, x);
          maxY = math.max(maxY, y);
        }
      }
    }

    // Step 3: Detect line positions to refine board boundary
    // Line color threshold
    const double lineColorThreshold = 35.0;

    // Track line positions
    final List<int> horizontalLinePositions = <int>[];
    final List<int> verticalLinePositions = <int>[];

    // Scan for horizontal lines
    for (int y = minY; y <= maxY; y++) {
      int linePixels = 0;
      for (int x = minX; x <= maxX; x++) {
        final img.Pixel pixel = imgSrc.getPixel(x, y);
        final Rgb rgb = Rgb(pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt());

        if (_colorDistance(rgb, boardLineRgb) < lineColorThreshold) {
          linePixels++;
        }
      }

      // If this row has enough line pixels, consider it a horizontal line
      if (linePixels > (maxX - minX + 1) * 0.3) {
        horizontalLinePositions.add(y);
      }
    }

    // Scan for vertical lines
    for (int x = minX; x <= maxX; x++) {
      int linePixels = 0;
      for (int y = minY; y <= maxY; y++) {
        final img.Pixel pixel = imgSrc.getPixel(x, y);
        final Rgb rgb = Rgb(pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt());

        if (_colorDistance(rgb, boardLineRgb) < lineColorThreshold) {
          linePixels++;
        }
      }

      // If this column has enough line pixels, consider it a vertical line
      if (linePixels > (maxY - minY + 1) * 0.3) {
        verticalLinePositions.add(x);
      }
    }

    // Sort line positions
    horizontalLinePositions.sort();
    verticalLinePositions.sort();

    // Decide board boundaries
    int leftBorder, topBorder, rightBorder, bottomBorder;
    int finalSize;

    // Check if enough lines were found
    if (horizontalLinePositions.length < 2 ||
        verticalLinePositions.length < 2) {
      logger
          .w("Not enough lines detected, using connected component boundaries");
      leftBorder = minX;
      topBorder = minY;
      rightBorder = maxX;
      bottomBorder = maxY;
    } else {
      // Use outermost lines as boundaries
      leftBorder = verticalLinePositions.first;
      rightBorder = verticalLinePositions.last;
      topBorder = horizontalLinePositions.first;
      bottomBorder = horizontalLinePositions.last;
    }

    // Step 4: Convert to strict square boundary
    // Calculate width and height
    final int width = rightBorder - leftBorder + 1;
    final int height = bottomBorder - topBorder + 1;

    // Choose larger dimension for square size to ensure complete board coverage
    finalSize = math.max(width, height);

    // Limit size if it exceeds image boundaries
    if (leftBorder + finalSize > imgWidth ||
        topBorder + finalSize > imgHeight) {
      finalSize = math.min(imgWidth - leftBorder, imgHeight - topBorder);
    }

    // Ensure square contains entire board
    if (leftBorder + finalSize < rightBorder) {
      // If right border exceeds square, shift square left
      final int shift = rightBorder - (leftBorder + finalSize);
      if (leftBorder - shift >= 0) {
        leftBorder -= shift;
      } else {
        // If left shift would exceed boundary, expand square size
        finalSize = rightBorder - leftBorder + 1;
      }
    }

    if (topBorder + finalSize < bottomBorder) {
      // If bottom border exceeds square, shift square up
      final int shift = bottomBorder - (topBorder + finalSize);
      if (topBorder - shift >= 0) {
        topBorder -= shift;
      } else {
        // If up shift would exceed boundary, expand square size
        finalSize = bottomBorder - topBorder + 1;
      }
    }

    // Ensure size doesn't exceed image boundaries
    finalSize = math.min(finalSize, imgWidth - leftBorder);
    finalSize = math.min(finalSize, imgHeight - topBorder);

    logger.i(
        "Board boundary detected using color settings: ($leftBorder, $topBorder, $finalSize, $finalSize) [strict square]");

    // Update debug info
    final math.Rectangle<int> boardRect =
        math.Rectangle<int>(leftBorder, topBorder, finalSize, finalSize);
    _lastDebugInfo = _lastDebugInfo.copyWith(boardRect: boardRect);

    // Generate standard board grid based on detected rectangle
    _generateStandardBoardGrid(boardRect, imgSrc);

    // Calculate board points with refined positions
    final List<BoardPoint> refinedPoints =
        createRefinedBoardPoints(imgSrc, boardRect);
    _lastDebugInfo = _lastDebugInfo.copyWith(boardPoints: refinedPoints);
    _lastDetectedPoints = refinedPoints;

    return boardRect;
  }

  /// Detect board bounding box using background color, morphological operations (stubs), and largest component finding.
  static math.Rectangle<int>? _findBoardBoundingBox(img.Image imgSrc) {
    // First try using color settings detection
    final math.Rectangle<int>? colorSettingsResult =
        _findBoardBoundingBoxUsingColorSettings(imgSrc);
    if (colorSettingsResult != null) {
      logger.i("Successfully detected board boundary using color settings");

      // Generate standard board grid based on detected rectangle
      _generateStandardBoardGrid(colorSettingsResult, imgSrc);

      // Calculate refined board points
      final List<BoardPoint> refinedPoints =
          createRefinedBoardPoints(imgSrc, colorSettingsResult);
      _lastDebugInfo = _lastDebugInfo.copyWith(boardPoints: refinedPoints);
      _lastDetectedPoints = refinedPoints;

      return colorSettingsResult;
    }

    // If color settings detection failed, fall back to original method
    logger.i(
        "Color settings detection failed, falling back to original method...");

    // Original detection method code...
    // 1. Define scan area (slightly inset from borders)
    final int imgHeight = imgSrc.height;
    final int imgWidth = imgSrc.width;
    final int scanStartY = (imgHeight * 0.02).toInt(); // Start slightly lower
    final int scanHeight = imgHeight -
        2 * scanStartY; // Reduce height slightly from top and bottom
    final int scanStartX = (imgWidth * 0.02).toInt(); // Start slightly inwards
    final int scanWidth =
        imgWidth - 2 * scanStartX; // Reduce width slightly from sides

    if (scanHeight <= 20 || scanWidth <= 20) {
      // Need a minimum size
      logger.w(
          "Image too small or scan area invalid for bounding box detection.");
      return null;
    }

    // 2. Create binary mask based on likely board color
    List<List<bool>> mask = List<List<bool>>.generate(
        imgHeight,
        (_) => List<bool>.filled(
            imgWidth, false)); // Use full image size for mask indices
    for (int y = scanStartY; y < scanStartY + scanHeight; y++) {
      for (int x = scanStartX; x < scanStartX + scanWidth; x++) {
        // Check bounds before getPixel (should be redundant but safe)
        if (x >= 0 && x < imgWidth && y >= 0 && y < imgHeight) {
          final img.Pixel pixel = imgSrc.getPixel(x, y);
          final Rgb rgb =
              Rgb(pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt());
          if (_isLikelyBoardColor(rgb)) {
            mask[y][x] = true;
          }
        }
      }
    }

    // 3. Morphological operations (using stubs for now)
    // These would typically connect nearby regions and remove noise.
    // Actual implementation needed for _dilate and _erode.
    mask = _dilate(mask, 3); // Stub - returns original
    mask = _erode(mask, 2); // Stub - returns original
    mask = _dilate(mask, 3); // Stub - returns original

    // Update debug info with the mask after potential morphology
    _lastDebugInfo = _lastDebugInfo.copyWith(boardMask: mask);

    // 4. Find the largest connected component using Breadth-First Search (BFS)
    final List<List<int>> labels = List<List<int>>.generate(
        imgHeight, (_) => List<int>.filled(imgWidth, 0));
    int nextLabel = 1;
    int largestLabel = 0;
    int maxComponentSize = 0;
    // Keep track of a point within the largest component

    for (int y = scanStartY; y < scanStartY + scanHeight; y++) {
      for (int x = scanStartX; x < scanStartX + scanWidth; x++) {
        if (mask[y][x] && labels[y][x] == 0) {
          int currentSize = 0;
          final Queue<_Point> queue = Queue<_Point>();
          final List<_Point> currentComponentPoints =
              <_Point>[]; // Store points of current component

          queue.add(_Point(x, y));
          labels[y][x] = nextLabel;

          while (queue.isNotEmpty) {
            final _Point current = queue.removeFirst();
            currentSize++;
            currentComponentPoints.add(current); // Add point to list

            // Check 8 neighbors
            for (int dy = -1; dy <= 1; dy++) {
              for (int dx = -1; dx <= 1; dx++) {
                if (dx == 0 && dy == 0) {
                  continue;
                }
                final int nx = current.x + dx;
                final int ny = current.y + dy;

                // Check bounds and if it's part of the mask and unlabeled
                if (nx >= 0 &&
                    nx < imgWidth &&
                    ny >= 0 &&
                    ny < imgHeight &&
                    mask[ny][nx] &&
                    labels[ny][nx] == 0) {
                  labels[ny][nx] = nextLabel;
                  queue.add(_Point(nx, ny));
                }
              }
            }
          } // End of BFS for one component

          // Check if this component is the largest found so far
          if (currentSize > maxComponentSize) {
            maxComponentSize = currentSize;
            largestLabel = nextLabel;
            if (currentComponentPoints.isNotEmpty) {
              // Store start point
            }
          }
          nextLabel++;
        }
      }
    } // End of component search loops

    // 5. Calculate bounding box of the largest component
    if (largestLabel == 0) {
      logger.w("No significant connected components found for the board.");
      return null; // No component found
    }

    // Need to re-run BFS or iterate through labels to find all points of the largest component
    int minX = imgWidth, minY = imgHeight, maxX = 0, maxY = 0;
    bool foundPoints = false;

    // Re-iterate or use stored points if CCA stored them per label
    // Simple re-iteration here:
    for (int y = 0; y < imgHeight; y++) {
      for (int x = 0; x < imgWidth; x++) {
        if (labels[y][x] == largestLabel) {
          minX = math.min(minX, x);
          minY = math.min(minY, y);
          maxX = math.max(maxX, x);
          maxY = math.max(maxY, y);
          foundPoints = true;
        }
      }
    }

    if (!foundPoints) {
      logger.w("Largest component label found, but no points associated?");
      return null;
    }

    // Add some padding to the bounding box? Optional.
    const int padding = 2;
    minX = math.max(0, minX - padding);
    minY = math.max(0, minY - padding);
    maxX = math.min(imgWidth - 1, maxX + padding);
    maxY = math.min(imgHeight - 1, maxY + padding);

    // Calculate width and height
    final int width = maxX - minX + 1;
    final int height = maxY - minY + 1;

    // Choose larger dimension for square size to ensure complete board coverage
    int finalSize = math.max(width, height);

    // Calculate center point to center the square
    final int centerX = minX + width ~/ 2;
    final int centerY = minY + height ~/ 2;

    // Calculate square's top-left from center point
    int adjustedMinX = centerX - finalSize ~/ 2;
    int adjustedMinY = centerY - finalSize ~/ 2;

    // Ensure boundaries are within image
    if (adjustedMinX < 0) {
      adjustedMinX = 0;
    }
    if (adjustedMinY < 0) {
      adjustedMinY = 0;
    }
    if (adjustedMinX + finalSize > imgWidth) {
      adjustedMinX = imgWidth - finalSize;
    }
    if (adjustedMinY + finalSize > imgHeight) {
      adjustedMinY = imgHeight - finalSize;
    }

    // Ensure size doesn't exceed image boundaries (if previous adjustments caused overflow)
    finalSize = math.min(finalSize, imgWidth - adjustedMinX);
    finalSize = math.min(finalSize, imgHeight - adjustedMinY);

    logger.i(
        "Detected board bounding box via CCA: ($adjustedMinX, $adjustedMinY, $finalSize, $finalSize), [strict square]");

    // Update debug info with the final calculated rectangle
    final math.Rectangle<int> boardRect =
        math.Rectangle<int>(adjustedMinX, adjustedMinY, finalSize, finalSize);
    _lastDebugInfo = _lastDebugInfo.copyWith(boardRect: boardRect);

    // Generate the standard grid mask based on this rectangle
    _generateStandardBoardGrid(boardRect, imgSrc);

    // Calculate refined board points
    final List<BoardPoint> refinedPoints =
        createRefinedBoardPoints(imgSrc, boardRect);
    _lastDebugInfo = _lastDebugInfo.copyWith(boardPoints: refinedPoints);
    _lastDetectedPoints = refinedPoints;

    return boardRect;
  }

  /// Creates 24 board points from the detected board rectangle and refines their positions
  /// based on the detected lines.
  static List<BoardPoint> createRefinedBoardPoints(
      img.Image image, math.Rectangle<int> rect) {
    // First, get the initial board points
    final List<BoardPoint> initialPoints = createBoardPointsFromRect(rect);

    if (initialPoints.isEmpty) {
      return initialPoints; // Return empty list if initial creation failed
    }

    // Then try to adjust them to match line intersections

    try {
      final List<BoardPoint> adjustedPoints = initialPoints;

      // Adjust points to match line intersections if the board has enough lines detected
      // Get the 7x7 grid points that are on the actual intersections of lines
      final List<Offset> gridPositions = <Offset>[];

      // Calculate board margin (external margin before the actual board starts)
      // Use 8% margin to match createBoardPointsFromRect
      const double boardMarginRatio = 0.08;
      final double boardMargin = rect.width * boardMarginRatio;

      // Calculate the distance between grid lines
      final double gridSpacing = (rect.width - 2 * boardMargin) / 6.0;

      // Generate all 7x7 grid intersection points
      for (int row = 0; row < 7; row++) {
        for (int col = 0; col < 7; col++) {
          final double x = rect.left + boardMargin + col * gridSpacing;
          final double y = rect.top + boardMargin + row * gridSpacing;
          gridPositions.add(Offset(x, y));
        }
      }

      // For each board point, find the closest grid intersection
      for (int i = 0; i < initialPoints.length; i++) {
        final BoardPoint point = initialPoints[i];
        double minDistance = double.infinity;
        int bestIndex = -1;

        for (int j = 0; j < gridPositions.length; j++) {
          final Offset gridPos = gridPositions[j];
          final double distance = math.sqrt(math.pow(point.x - gridPos.dx, 2) +
              math.pow(point.y - gridPos.dy, 2));

          if (distance < minDistance) {
            minDistance = distance;
            bestIndex = j;
          }
        }

        if (bestIndex >= 0) {
          final Offset bestPos = gridPositions[bestIndex];
          adjustedPoints[i] = BoardPoint(bestPos.dx.round(), bestPos.dy.round(),
              point.radius, point.originalX, point.originalY);
        }
      }

      logger.i(
          "Refined ${adjustedPoints.length} board points to match grid intersections with ${boardMarginRatio * 100}% margin");
      return adjustedPoints;
    } catch (e) {
      logger.e("Error refining board points: $e");
      return initialPoints; // Return initial points if refinement fails
    }
  }

  /// Generates a standard Nine Men's Morris grid mask within the detected board rectangle.
  /// Updates the debug info with this grid mask.
  static void _generateStandardBoardGrid(
      math.Rectangle<int>? boardRect, img.Image processedImage) {
    if (boardRect == null) {
      logger.w("Cannot generate standard grid mask without a board rectangle.");
      return;
    }
    logger.i("Generating standard 7x7 grid mask based on board rectangle.");

    // Create a new mask initialized to false
    final List<List<bool>> gridMask = List<List<bool>>.generate(
        processedImage.height,
        (_) => List<bool>.filled(processedImage.width, false));

    final int left = boardRect.left;
    final int top = boardRect.top;

    // Use the width and height of the board rectangle (should be equal, i.e. square)
    final int size = boardRect.width; // Square area size

    if (size < 6) {
      logger.w("Board rectangle size ($size) too small to generate grid.");
      return; // Avoid division by zero or small numbers
    }

    final double segmentSize =
        size / 6.0; // Divide into six equal parts to get space for seven lines
    final int lineWidth =
        math.max(1, (size * 0.01).round()); // Line width ~1% of size

    // Generate horizontal lines
    for (int i = 0; i < 7; i++) {
      final int y = top + (i * segmentSize).round();
      // Draw line with thickness
      for (int dy = -lineWidth ~/ 2; dy <= lineWidth ~/ 2; dy++) {
        final int lineY = y + dy;
        if (lineY >= 0 && lineY < processedImage.height) {
          // Draw across the width
          for (int x = left; x < left + size; x++) {
            if (x >= 0 && x < processedImage.width) {
              gridMask[lineY][x] = true;
            }
          }
        }
      }
    }

    // Generate vertical lines
    for (int i = 0; i < 7; i++) {
      final int x = left + (i * segmentSize).round();
      // Draw line with thickness
      for (int dx = -lineWidth ~/ 2; dx <= lineWidth ~/ 2; dx++) {
        final int lineX = x + dx;
        if (lineX >= 0 && lineX < processedImage.width) {
          // Draw down the height
          for (int y = top; y < top + size; y++) {
            if (y >= 0 && y < processedImage.height) {
              gridMask[y][lineX] = true;
            }
          }
        }
      }
    }

    // Add the outer border of the chessboard to more clearly mark the chessboard boundary
    // Top border
    for (int x = left; x < left + size; x++) {
      for (int y = top; y < top + lineWidth; y++) {
        if (x >= 0 &&
            x < processedImage.width &&
            y >= 0 &&
            y < processedImage.height) {
          gridMask[y][x] = true;
        }
      }
    }

    // Bottom border
    for (int x = left; x < left + size; x++) {
      for (int y = top + size - lineWidth; y < top + size; y++) {
        if (x >= 0 &&
            x < processedImage.width &&
            y >= 0 &&
            y < processedImage.height) {
          gridMask[y][x] = true;
        }
      }
    }

    // Left border
    for (int y = top; y < top + size; y++) {
      for (int x = left; x < left + lineWidth; x++) {
        if (x >= 0 &&
            x < processedImage.width &&
            y >= 0 &&
            y < processedImage.height) {
          gridMask[y][x] = true;
        }
      }
    }

    // Right border
    for (int y = top; y < top + size; y++) {
      for (int x = left + size - lineWidth; x < left + size; x++) {
        if (x >= 0 &&
            x < processedImage.width &&
            y >= 0 &&
            y < processedImage.height) {
          gridMask[y][x] = true;
        }
      }
    }

    // Update debug info with the generated grid mask
    _lastDebugInfo = _lastDebugInfo.copyWith(
      boardMask: gridMask,
    );
  }

  // === Public wrapper methods & setters added for external access ===
  /// Expose `_resizeForProcessing` as a public method.
  static img.Image resizeForProcessing(img.Image original) =>
      _resizeForProcessing(original);

  /// Expose `_enhanceImageForProcessing` as a public method with optional custom contrast factor.
  static img.Image enhanceImageForProcessing(
    img.Image inputImage, {
    double? contrastEnhancementFactor,
  }) =>
      _enhanceImageForProcessing(inputImage,
          contrastEnhancementFactor: contrastEnhancementFactor);

  /// Expose `_analyzeImageCharacteristics` as a public method with optional custom thresholds.
  static ImageCharacteristics analyzeImageCharacteristics(
    img.Image image, {
    int? whiteBrightnessThresholdBase,
    int? blackBrightnessThresholdBase,
    double? pieceThreshold,
  }) =>
      _analyzeImageCharacteristics(
        image,
        whiteBrightnessThresholdBase: whiteBrightnessThresholdBase,
        blackBrightnessThresholdBase: blackBrightnessThresholdBase,
        pieceThreshold: pieceThreshold,
      );

  /// Expose `_estimateBoardColor` as a public method.
  static Rgb estimateBoardColor(
          img.Image image, math.Rectangle<int>? boardRect) =>
      _estimateBoardColor(image, boardRect);

  /// Expose `_buildColorProfile` as a public method.
  static ColorProfile buildColorProfile(
          img.Image image, List<BoardPoint> points) =>
      _buildColorProfile(image, points);

  /// Expose `_detectPieceAtPoint` as a public method with optional custom thresholds.
  static PieceColor detectPieceAtPoint(
    img.Image image,
    BoardPoint point,
    ImageCharacteristics characteristics,
    ColorProfile colorProfile,
    Rgb boardColor,
    Rgb configuredWhiteRgb,
    Rgb configuredBlackRgb, {
    double? pieceColorMatchThreshold,
    double? boardColorDistanceThreshold,
    double? blackSaturationThreshold,
    int? blackColorVarianceThreshold,
  }) =>
      _detectPieceAtPoint(
        image,
        point,
        characteristics,
        colorProfile,
        boardColor,
        configuredWhiteRgb,
        configuredBlackRgb,
        pieceColorMatchThreshold: pieceColorMatchThreshold,
        boardColorDistanceThreshold: boardColorDistanceThreshold,
        blackSaturationThreshold: blackSaturationThreshold,
        blackColorVarianceThreshold: blackColorVarianceThreshold,
      );

  /// Expose `_applyConsistencyRules` as a public method.
  static Map<int, PieceColor> applyConsistencyRules(
          Map<int, PieceColor> detectedState) =>
      _applyConsistencyRules(detectedState);

  /// Expose `_rgbFromColor` as a public helper.
  static Rgb rgbFromColor(Color color) => _rgbFromColor(color);

  /// Setter to allow external overwriting of debug info (used by debug screens).
  static set lastDebugInfo(BoardRecognitionDebugInfo info) =>
      _lastDebugInfo = info;

  /// Setter to allow external overwriting of last detected points (used by debug screens).
  static set lastDetectedPoints(List<BoardPoint> points) =>
      _lastDetectedPoints = points;
// === End of public wrappers ===
}

/// Creates the 24 standard Nine Men's Morris board points based on a bounding rectangle.
/// Takes into account the board margin used in the actual game board rendering.
List<BoardPoint> createBoardPointsFromRect(math.Rectangle<int> rect) {
  final List<BoardPoint> points = <BoardPoint>[];
  rect.width.toDouble();
  rect.height.toDouble();

  // Use the width of the square board (should be equal to height since we enforced square shape)
  final double size = rect.width.toDouble();

  if (size < 10) {
    // Check for minimum reasonable size
    logger.e("Board rectangle too small ($rect) to create points.");
    return <BoardPoint>[];
  }

  // Calculate the board margin that corresponds to the space between the outer ring and the board edge
  // Reduce margin from 12.5% to 8% for more accurate point placement
  // This places points closer to the outer edge, matching the actual board layout better
  const double boardMarginRatio = 0.08;
  final double effectiveBoardMargin = size * boardMarginRatio;

  // Calculate the playable area size (excluding margins)
  final double playableSize = size - (effectiveBoardMargin * 2);

  // The playable area is divided into 6 segments (7 lines)
  final double segmentSize = playableSize / 6.0;

  // Calculate offset to center the grid within the detected rectangle
  final double offsetX = rect.left + effectiveBoardMargin;
  final double offsetY = rect.top + effectiveBoardMargin;

  // Calculate radius for sampling around each point, slightly smaller than segment gap
  final double pointRadius = segmentSize * 0.35;

  // Standard Nine Men's Morris points in 0-6 coordinate system, ordered 0-23 (clockwise per ring)
  const List<Offset> stdPoints = <Offset>[
    // Outer ring (0-7) - Indices 0, 3, 6 correspond to corners/midpoints
    Offset.zero, Offset(3, 0), Offset(6, 0), Offset(6, 3),
    Offset(6, 6), Offset(3, 6), Offset(0, 6), Offset(0, 3),
    // Middle ring (8-15) - Indices 1, 3, 5
    Offset(1, 1), Offset(3, 1), Offset(5, 1), Offset(5, 3),
    Offset(5, 5), Offset(3, 5), Offset(1, 5), Offset(1, 3),
    // Inner ring (16-23) - Indices 2, 3, 4
    Offset(2, 2), Offset(3, 2), Offset(4, 2), Offset(4, 3),
    Offset(4, 4), Offset(3, 4), Offset(2, 4), Offset(2, 3),
  ];

  // Map grid coordinates (0-6) to pixel coordinates based on segmentSize and offset
  for (int i = 0; i < stdPoints.length; i++) {
    final Offset gridPos = stdPoints[i];
    // Convert from grid coordinates to actual pixel positions
    final double px = offsetX + gridPos.dx * segmentSize;
    final double py = offsetY + gridPos.dy * segmentSize;

    // Store original grid coordinates for debugging
    points.add(BoardPoint(px.round(), py.round(), pointRadius,
        gridPos.dx.toInt(), gridPos.dy.toInt()));
  }

  // Log if the number of points is unexpected
  if (points.length != 24) {
    logger.w(
        "Created ${points.length} points from rect, expected 24. Rect: $rect");
  } else {
    logger.i(
        "Successfully created 24 board points with adjusted margin. Using margin: $effectiveBoardMargin px (${boardMarginRatio * 100}% of board size)");
  }

  return points;
}

/// Adjust board points to match line intersections using the board line color.
/// This method should be called with the detected points and the source image.
List<BoardPoint> adjustPointsToLineIntersections(
    List<BoardPoint> initialPoints, img.Image image, Color boardLineColor) {
  if (initialPoints.isEmpty || image == null) {
    return initialPoints;
  }

  // Convert Flutter's Color to internal Rgb representation
  final Rgb lineRgb =
      BoardImageRecognitionService._rgbFromColor(boardLineColor);
  const double lineColorThreshold =
      35.0; // Threshold for considering a pixel as part of a line
  const int searchRadius =
      10; // Search radius around the initial point position

  final List<BoardPoint> adjustedPoints = <BoardPoint>[];

  for (int i = 0; i < initialPoints.length; i++) {
    final BoardPoint point = initialPoints[i];

    // Check if the point is inside the image
    if (point.x < 0 ||
        point.x >= image.width ||
        point.y < 0 ||
        point.y >= image.height) {
      adjustedPoints.add(point); // Keep the original point if outside bounds
      continue;
    }

    // Initialize variables to track the best intersection
    int bestX = point.x;
    int bestY = point.y;
    int maxLinePixelCount = 0;

    // Search in a square area around the initial point
    for (int dy = -searchRadius; dy <= searchRadius; dy++) {
      for (int dx = -searchRadius; dx <= searchRadius; dx++) {
        final int x = point.x + dx;
        final int y = point.y + dy;

        // Make sure the search area is within image bounds
        if (x < 0 || x >= image.width || y < 0 || y >= image.height) {
          continue;
        }

        // Count the number of line pixels in horizontal and vertical directions
        int horizontalLinePixels = 0;
        int verticalLinePixels = 0;

        // Check horizontal line
        for (int hx = x - 5; hx <= x + 5; hx++) {
          if (hx < 0 || hx >= image.width) {
            continue;
          }
          final img.Pixel pixel = image.getPixel(hx, y);
          final Rgb rgb =
              Rgb(pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt());

          // Calculate Euclidean distance between colors
          final double dr = (rgb.r - lineRgb.r).toDouble();
          final double dg = (rgb.g - lineRgb.g).toDouble();
          final double db = (rgb.b - lineRgb.b).toDouble();
          final double colorDistance = math.sqrt(dr * dr + dg * dg + db * db);

          if (colorDistance < lineColorThreshold) {
            horizontalLinePixels++;
          }
        }

        // Check vertical line
        for (int vy = y - 5; vy <= y + 5; vy++) {
          if (vy < 0 || vy >= image.height) {
            continue;
          }
          final img.Pixel pixel = image.getPixel(x, vy);
          final Rgb rgb =
              Rgb(pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt());

          // Calculate Euclidean distance between colors
          final double dr = (rgb.r - lineRgb.r).toDouble();
          final double dg = (rgb.g - lineRgb.g).toDouble();
          final double db = (rgb.b - lineRgb.b).toDouble();
          final double colorDistance = math.sqrt(dr * dr + dg * dg + db * db);

          if (colorDistance < lineColorThreshold) {
            verticalLinePixels++;
          }
        }

        // If this position has more line pixels, it's likely a better intersection
        final int totalLinePixels = horizontalLinePixels + verticalLinePixels;
        if (totalLinePixels > maxLinePixelCount) {
          maxLinePixelCount = totalLinePixels;
          bestX = x;
          bestY = y;
        }
      }
    }

    // Create an adjusted point with the best coordinates found
    adjustedPoints.add(BoardPoint(
        bestX, bestY, point.radius, point.originalX, point.originalY));
  }

  logger.i(
      "Adjusted ${adjustedPoints.length} board points to match line intersections");
  return adjustedPoints;
}

/// Advanced method to detect precise board layout from an image after finding the board rectangle.
/// This method uses the board's line color and geometry to detect the exact grid.
math.Rectangle<int>? detectBoardGridFromImage(
    img.Image image, math.Rectangle<int> boardRect, Color boardLineColor) {
  if (image == null || boardRect == null) {
    return boardRect;
  }

  // Convert Flutter's Color to internal Rgb representation
  final Rgb lineRgb =
      BoardImageRecognitionService._rgbFromColor(boardLineColor);
  const double lineColorThreshold = 35.0;

  // List to store detected horizontal and vertical line positions
  final List<int> horizontalLinesList = <int>[];
  final List<int> verticalLinesList = <int>[];

  // Scan for horizontal lines
  for (int y = boardRect.top; y <= boardRect.top + boardRect.height; y++) {
    int linePixelCount = 0;
    for (int x = boardRect.left; x <= boardRect.left + boardRect.width; x++) {
      if (x < 0 || x >= image.width || y < 0 || y >= image.height) {
        continue;
      }
      final img.Pixel pixel = image.getPixel(x, y);
      final Rgb rgb = Rgb(pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt());

      // Calculate Euclidean distance between colors
      final double dr = (rgb.r - lineRgb.r).toDouble();
      final double dg = (rgb.g - lineRgb.g).toDouble();
      final double db = (rgb.b - lineRgb.b).toDouble();
      final double colorDistance = math.sqrt(dr * dr + dg * dg + db * db);

      if (colorDistance < lineColorThreshold) {
        linePixelCount++;
      }
    }

    // If we found a significant number of line pixels, consider this a grid line
    if (linePixelCount > boardRect.width * 0.3) {
      horizontalLinesList.add(y);
    }
  }

  // Scan for vertical lines
  for (int x = boardRect.left; x <= boardRect.left + boardRect.width; x++) {
    int linePixelCount = 0;
    for (int y = boardRect.top; y <= boardRect.top + boardRect.height; y++) {
      if (x < 0 || x >= image.width || y < 0 || y >= image.height) {
        continue;
      }
      final img.Pixel pixel = image.getPixel(x, y);
      final Rgb rgb = Rgb(pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt());

      // Calculate Euclidean distance between colors
      final double dr = (rgb.r - lineRgb.r).toDouble();
      final double dg = (rgb.g - lineRgb.g).toDouble();
      final double db = (rgb.b - lineRgb.b).toDouble();
      final double colorDistance = math.sqrt(dr * dr + dg * dg + db * db);

      if (colorDistance < lineColorThreshold) {
        linePixelCount++;
      }
    }

    // If we found a significant number of line pixels, consider this a grid line
    if (linePixelCount > boardRect.height * 0.3) {
      verticalLinesList.add(x);
    }
  }

  // Need at least 7 lines in each direction for a standard 7x7 grid
  if (horizontalLinesList.length < 7 || verticalLinesList.length < 7) {
    logger.w(
        "Could not detect complete grid. H-lines: ${horizontalLinesList.length}, V-lines: ${verticalLinesList.length}");
    return boardRect; // Return the original rect if we can't detect the full grid
  }

  // Filter lines to get exactly 7 lines (if we detected more)
  List<int> horizontalLines = horizontalLinesList;
  List<int> verticalLines = verticalLinesList;

  if (horizontalLines.length > 7 || verticalLines.length > 7) {
    // We need to select 7 most prominent lines
    horizontalLines.sort();
    verticalLines.sort();

    // Determine spacing between lines to identify the most likely 7 lines
    if (horizontalLines.length > 7) {
      // Use clustering or equal spacing to find the 7 most likely lines
      horizontalLines = _selectRepresentativeLines(horizontalLines, 7);
    }

    if (verticalLines.length > 7) {
      verticalLines = _selectRepresentativeLines(verticalLines, 7);
    }
  }

  // Create a refined board rectangle based on the detected grid
  final int left = verticalLines.first;
  final int right = verticalLines.last;
  final int top = horizontalLines.first;
  final int bottom = horizontalLines.last;

  final int width = right - left;
  final int height = bottom - top;

  // Ensure we have a square grid
  final int size = math.max(width, height);

  logger.i(
      "Detected grid lines: H=${horizontalLines.length}, V=${verticalLines.length}");
  logger.i("Refined board rectangle: ($left, $top, $size, $size)");

  return math.Rectangle<int>(left, top, size, size);
}

/// Helper method to select n most representative lines from a larger set
List<int> _selectRepresentativeLines(List<int> lines, int n) {
  if (lines.length <= n) {
    return lines;
  }

  // For simplicity, we'll just pick evenly spaced lines
  // A more sophisticated approach would use clustering

  final List<int> result = <int>[];
  final double step = (lines.length - 1) / (n - 1);

  for (int i = 0; i < n; i++) {
    final int index = (i * step).round();
    result.add(lines[index]);
  }

  return result;
}

/// Represents a point on the board for recognition purposes
class BoardPoint {
  BoardPoint(this.x, this.y, this.radius, [this.originalX, this.originalY]);

  final int x; // Pixel X coordinate
  final int y; // Pixel Y coordinate
  final double radius; // Estimated radius around the point for sampling
  final int? originalX; // Original grid coordinate (0-6) if known
  final int? originalY; // Original grid coordinate (0-6) if known
}

/// Holds characteristics of the image that affect recognition parameters
class ImageCharacteristics {
  ImageCharacteristics(
      {required this.averageBrightness,
      required this.isDarkBackground,
      required this.isHighContrast,
      required this.whiteBrightnessThreshold,
      required this.blackBrightnessThreshold,
      required this.pieceDetectionThreshold,
      required this.contrastRatio});

  final double averageBrightness;
  final bool isDarkBackground;
  final bool isHighContrast;
  final int whiteBrightnessThreshold; // Calculated threshold for white pieces
  final int blackBrightnessThreshold; // Calculated threshold for black pieces
  final double pieceDetectionThreshold; // General threshold adjustment factor?
  final double contrastRatio; // Calculated contrast ratio metric
}

/// Stores color statistics of white, black, and empty points for adaptive thresholding
class ColorProfile {
  ColorProfile(
      {required this.whiteMean,
      required this.blackMean,
      required this.emptyMean,
      required this.whiteStd,
      required this.blackStd,
      required this.emptyStd});

  final double whiteMean; // Average brightness of detected white samples
  final double blackMean; // Average brightness of detected black samples
  final double emptyMean; // Average brightness of detected empty samples
  final double whiteStd; // Standard deviation of white samples
  final double blackStd; // Standard deviation of black samples
  final double emptyStd; // Standard deviation of empty samples
}

/// A simple RGB color representation for color distance calculations
class Rgb {
  const Rgb(this.r, this.g, this.b);

  final int r, g, b; // 0-255 range

  /// Calculate Euclidean distance to another RGB color
  double distanceTo(Rgb other) {
    final int dr = r - other.r, dg = g - other.g, db = b - other.b;
    return math.sqrt(dr * dr + dg * dg + db * db);
  }

  @override
  String toString() => 'RGB($r, $g, $b)';
}

/// Extension to convert Rgb to an img.Pixel (using a safe method)
extension RgbToPixelExtension on Rgb {
  img.Pixel toPixel() {
    // Use the result of the existing getPixel method to create pixels,
    // avoiding direct construction which might change across library versions.
    // This is slightly inefficient but safer.
    final img.Image dummyImage = img.Image(width: 1, height: 1);
    // Set RGBA, ensuring values are clamped to valid 0-255 range. Alpha is full.
    dummyImage.setPixelRgba(
        0, 0, r.clamp(0, 255), g.clamp(0, 255), b.clamp(0, 255), 255);
    return dummyImage.getPixel(0, 0);
  }
}

/// Simple data class representing an optimal sampling point (unused in current version)
class OptimalSamplingPoint {
  OptimalSamplingPoint(this.x, this.y);

  final int x;
  final int y;
}
