// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// board_recognition_debug_view.dart

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../../generated/intl/l10n.dart';
import '../../shared/database/database.dart';
import '../../shared/services/logger.dart';
import '../services/board_image_recognition.dart';
import '../services/mill.dart';
import 'piece_overlay_painter.dart';

/// Debug stage types, more granular processing steps
enum DebugStage {
  originalImage, // Original image
  resizedImage, // Resized image
  enhancedImage, // Contrast-enhanced image
  boardMaskRaw, // Initial board mask (unprocessed)
  boardMaskProcessed, // Processed board mask (after dilation/erosion)
  boardDetection, // Board region detection result
  boardPointsDetection, // Board point detection
  colorAnalysis, // Color analysis result
  pieceDetection, // Piece detection process
  finalResult, // Final recognition result
}

/// Board recognition debug view to show original image with recognition overlay
class BoardRecognitionDebugView extends StatefulWidget {
  const BoardRecognitionDebugView({
    super.key,
    required this.imageBytes,
    required this.boardPoints,
    required this.resultMap,
    required this.processedImageWidth,
    required this.processedImageHeight,
    this.showTitle = false,
    this.debugInfo,
  });

  final Uint8List imageBytes;
  final List<BoardPoint> boardPoints;
  final Map<int, PieceColor> resultMap;
  final int processedImageWidth;
  final int processedImageHeight;
  final bool showTitle;
  final BoardRecognitionDebugInfo? debugInfo;

  /// Generate a temporary FEN string based on recognition results
  /// This is used only for display purposes in the FinalResult stage
  /// Made public static to be callable from BoardRecognitionDebugPage
  static String? generateTempFenString(Map<int, PieceColor> resultMap) {
    if (resultMap.isEmpty) {
      return null;
    }

    try {
      // Create a custom FEN string directly from the recognition result map
      // FEN format: "inner_ring/middle_ring/outer_ring side_to_move phase action ..."
      // where each ring starts from 12 o'clock position and goes clockwise

      // The mapping between recognition indices (0-23) and rings:
      // Inner ring (16-23): Indices in image recognition are 16, 17, 18, 19, 20, 21, 22, 23
      // Middle ring (8-15): Indices in image recognition are 8, 9, 10, 11, 12, 13, 14, 15
      // Outer ring (0-7):   Indices in image recognition are 0, 1, 2, 3, 4, 5, 6, 7

      // Build FEN string for each ring
      final StringBuffer fenBuffer = StringBuffer();

      // First segment: Inner ring (indices 16-23, starting from top, shift left by 1)
      String innerRing = "";
      // Start with index 17 (instead of 16) and loop around to get index 16 at the end
      for (int i = 0; i < 8; i++) {
        final int idx = 16 + ((i + 1) % 8); // Shift left by 1
        final PieceColor pieceColor = resultMap[idx] ?? PieceColor.none;
        innerRing += _pieceColorToFenChar(pieceColor);
      }

      // Second segment: Middle ring (indices 8-15, starting from top, shift left by 1)
      String middleRing = "";
      for (int i = 0; i < 8; i++) {
        final int idx = 8 + ((i + 1) % 8); // Shift left by 1
        final PieceColor pieceColor = resultMap[idx] ?? PieceColor.none;
        middleRing += _pieceColorToFenChar(pieceColor);
      }

      // Third segment: Outer ring (indices 0-7, starting from top, shift left by 1)
      String outerRing = "";
      for (int i = 0; i < 8; i++) {
        final int idx = (i + 1) % 8; // Shift left by 1
        final PieceColor pieceColor = resultMap[idx] ?? PieceColor.none;
        outerRing += _pieceColorToFenChar(pieceColor);
      }

      // Combine rings with separators
      fenBuffer.write('$innerRing/$middleRing/$outerRing');

      // Count pieces
      int whiteCount = 0;
      int blackCount = 0;

      for (final PieceColor color in resultMap.values) {
        if (color == PieceColor.white) {
          whiteCount++;
        }
        if (color == PieceColor.black) {
          blackCount++;
        }
      }

      // Determine phase and side to move based on piece counts
      final int piecesCount = DB().ruleSettings.piecesCount;
      final String phase =
          (whiteCount < piecesCount || blackCount < piecesCount) ? "p" : "m";

      // If white has more pieces, it's black's turn; otherwise white's turn
      final String sideToMove = (whiteCount > blackCount) ? "b" : "w";

      // Add action - use "p" for placing or "s" for select
      final String action = (phase == "p") ? "p" : "s";

      // Append remaining FEN fields
      fenBuffer.write(' $sideToMove $phase $action');

      // Add piece counts
      fenBuffer.write(
          ' $whiteCount ${piecesCount - whiteCount} $blackCount ${piecesCount - blackCount}');

      // Add remaining standard values for a valid FEN
      fenBuffer.write(' 0 0 0 0 0 0 0 0 0 0 0');

      return fenBuffer.toString();
    } catch (e) {
      logger.e("Error generating temporary FEN: $e");
      return null;
    }
  }

  /// Helper method to convert piece color to FEN character
  static String _pieceColorToFenChar(PieceColor color) {
    return color.string;
  }

  @override
  State<BoardRecognitionDebugView> createState() =>
      _BoardRecognitionDebugViewState();
}

class _BoardRecognitionDebugViewState extends State<BoardRecognitionDebugView> {
  DebugStage _currentStage = DebugStage.finalResult;

  // Cache converted image data to avoid redundant conversions
  Uint8List? _cachedOriginalImage;
  Uint8List? _cachedResizedImage;
  Uint8List? _cachedEnhancedImage;

  // Processed mask (after dilation/erosion)
  List<List<bool>>? _processedMask;

  @override
  void initState() {
    super.initState();
    _prepareImages();
  }

  @override
  void didUpdateWidget(BoardRecognitionDebugView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.debugInfo != widget.debugInfo) {
      _prepareImages();
    }
  }

  // Prepare images for processing each stage
  void _prepareImages() {
    // Prepare original image
    if (widget.debugInfo?.originalImage != null) {
      _cachedOriginalImage =
          _convertImageToBytes(widget.debugInfo!.originalImage!);
    }

    // Prepare resized image (can be obtained from processed image, this is just an example)
    if (widget.debugInfo?.processedImage != null) {
      // Use copyResize to create resized image
      final img.Image? resizedImage = widget.debugInfo?.originalImage != null
          ? img.copyResize(
              widget.debugInfo!.originalImage!,
              width: widget.processedImageWidth,
              height: widget.processedImageHeight,
            )
          : null;

      if (resizedImage != null) {
        _cachedResizedImage = _convertImageToBytes(resizedImage);
      }
    }

    // Prepare contrast-enhanced image
    if (widget.debugInfo?.processedImage != null) {
      _cachedEnhancedImage =
          _convertImageToBytes(widget.debugInfo!.processedImage!);
    }

    // Process mask
    if (widget.debugInfo?.boardMask != null) {
      // Create a copy as "processed mask"
      // In actual application, this should be the mask after dilation/erosion processing
      _processedMask = List<List<bool>>.generate(
        widget.debugInfo!.boardMask!.length,
        (int i) => List<bool>.from(widget.debugInfo!.boardMask![i]),
      );

      // Simulate processed mask (in fact, this processing should be done by BoardImageRecognitionService)
      if (_processedMask != null) {
        // This is just for demonstration, in fact, it should be provided by BoardImageRecognitionService
      }
    }
  }

  // Convert Image to Uint8List
  Uint8List _convertImageToBytes(img.Image image) {
    return Uint8List.fromList(img.encodeJpg(image));
  }

  @override
  Widget build(BuildContext context) {
    // Main visualization component
    final Widget visualizationWidget = AspectRatio(
      aspectRatio: widget.processedImageWidth / widget.processedImageHeight,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8.0),
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            // Base layer: Display different content based on selected debug stage
            _buildBaseLayer(),

            // Top layer: Visual overlay, display different overlay content based on different stages
            _buildOverlayLayer(),
          ],
        ),
      ),
    );

    // Wrapped in a column with stage selection
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        // If request title, add
        if (widget.showTitle)
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Text(
              S.of(context).boardRecognitionResult,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
          ),

        // Debug stage selector
        if (widget.debugInfo != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: _buildStageSelector(),
          ),

        // Visualization
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: visualizationWidget,
        ),

        // Stage information text
        if (widget.debugInfo != null)
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: _buildStageInfo(),
          ),
      ],
    );
  }

  /// Build stage selector
  Widget _buildStageSelector() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            _stageButton('1. Original Image', DebugStage.originalImage),
            _stageButton('2. Resized Image', DebugStage.resizedImage),
            _stageButton('3. Enhanced Contrast', DebugStage.enhancedImage),
            _stageButton('4. Initial Mask', DebugStage.boardMaskRaw),
            _stageButton('5. Processed Mask', DebugStage.boardMaskProcessed),
            _stageButton('6. Board Detection', DebugStage.boardDetection),
            _stageButton('7. Point Detection', DebugStage.boardPointsDetection),
            _stageButton('8. Color Analysis', DebugStage.colorAnalysis),
            _stageButton('9. Piece Detection', DebugStage.pieceDetection),
            _stageButton('10. Final Result', DebugStage.finalResult),
          ],
        ),
      ),
    );
  }

  /// Build stage button
  Widget _stageButton(String label, DebugStage stage) {
    final bool isSelected = _currentStage == stage;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2.0),
      child: ElevatedButton(
        onPressed: () {
          setState(() {
            _currentStage = stage;
          });
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: isSelected
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          foregroundColor: isSelected
              ? Theme.of(context).colorScheme.onPrimary
              : Theme.of(context).colorScheme.onSurfaceVariant,
          padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 6.0),
          minimumSize: const Size(10, 30),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text(label, style: const TextStyle(fontSize: 10)),
      ),
    );
  }

  /// Build overlay (display different overlay content based on different stages)
  Widget _buildOverlayLayer() {
    if (widget.debugInfo == null) {
      return const SizedBox.shrink();
    }

    // Do not display overlay if image and board are not fully loaded
    if (widget.imageBytes.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    final bool boardDetected = widget.boardPoints.isNotEmpty ||
        (widget.debugInfo!.boardRect != null &&
            !(widget.debugInfo!.boardRect!.width <= 0 ||
                widget.debugInfo!.boardRect!.height <= 0));

    // Select appropriate overlay based on current debug stage
    switch (_currentStage) {
      case DebugStage.boardDetection:
        if (!boardDetected) {
          return Center(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(
                    Icons.error_outline,
                    color: Colors.white,
                    size: 48,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    S.of(context).noValidBoardDetected,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Please try adjusting the camera angle or lighting conditions',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.white,
                        ),
                  ),
                ],
              ),
            ),
          );
        } else if (widget.debugInfo!.boardRect != null &&
            !(widget.debugInfo!.boardRect!.width <= 0 ||
                widget.debugInfo!.boardRect!.height <= 0)) {
          // Display detected board area (using rectangle)
          return BoardRectOverlay(
            boardRect: widget.debugInfo!.boardRect!,
            imageSize: Size(
              widget.processedImageWidth.toDouble(),
              widget.processedImageHeight.toDouble(),
            ),
          );
        } else {
          // Display detected board points (using point grid)
          return CustomPaint(
            size: Size.infinite,
            painter: PieceOverlayPainter(
              boardPoints: widget.boardPoints,
              resultMap: widget.resultMap,
              imageSize: Size(
                widget.processedImageWidth.toDouble(),
                widget.processedImageHeight.toDouble(),
              ),
              boardRect: widget.debugInfo?.boardRect,
            ),
          );
        }

      case DebugStage.boardPointsDetection:
        // If no board is detected, point detection will also fail
        if (widget.boardPoints.isEmpty) {
          return Center(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red, width: 3),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(Icons.error_outline, color: Colors.red, size: 48),
                  const SizedBox(height: 8),
                  Text(
                    S.of(context).noBoardPointDetected,
                    style: const TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                      fontSize: 22,
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        return CustomPaint(
          size: Size.infinite,
          painter: BoardPointsDebugPainter(
            boardPoints: widget.boardPoints,
            imageSize: Size(
              widget.processedImageWidth.toDouble(),
              widget.processedImageHeight.toDouble(),
            ),
          ),
        );

      case DebugStage.colorAnalysis:
        if (widget.debugInfo?.colorProfile == null) {
          return Center(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                S.of(context).colorAnalysisFailed,
                style: const TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),
          );
        }
        return CustomPaint(
          size: Size.infinite,
          painter: ColorAnalysisPainter(
            boardPoints: widget.boardPoints,
            colorProfile: widget.debugInfo?.colorProfile,
            imageSize: Size(
              widget.processedImageWidth.toDouble(),
              widget.processedImageHeight.toDouble(),
            ),
          ),
        );

      case DebugStage.pieceDetection:
        if (widget.boardPoints.isEmpty) {
          return Center(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                S.of(context).noBoardPointDetectedCannotIdentifyPiece,
                style: const TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),
          );
        }
        return CustomPaint(
          size: Size.infinite,
          painter: PieceDetectionPainter(
            boardPoints: widget.boardPoints,
            resultMap: widget.resultMap,
            imageSize: Size(
              widget.processedImageWidth.toDouble(),
              widget.processedImageHeight.toDouble(),
            ),
            showDetails: true,
          ),
        );

      case DebugStage.finalResult:
        if (widget.boardPoints.isEmpty) {
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'Final Recognition Failed',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                  ),
                ),
                const SizedBox(height: 4),
                Text(S.of(context).entireRecognitionProcessFailedToComplete),
                Text(
                    S.of(context).suggestionTryTakingAClearerPictureOfTheBoard),
              ],
            ),
          );
        }

        int whiteCount = 0, blackCount = 0;
        for (final PieceColor color in widget.resultMap.values) {
          if (color == PieceColor.white) {
            whiteCount++;
          }
          if (color == PieceColor.black) {
            blackCount++;
          }
        }

        // Generate a temporary FEN string for display using the public static method
        final String? fenString =
            BoardRecognitionDebugView.generateTempFenString(widget.resultMap);

        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                'Final Recognition Result: ',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text('White Pieces: $whiteCount'),
              Text('Black Pieces: $blackCount'),
              const Text(
                  'Red Circle Indicates Black Pieces, Green Circle Indicates White Pieces'),
              const SizedBox(height: 10),
              // Add FEN string display
              if (fenString != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text(
                      'FEN:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black12,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.grey),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            fenString,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Click S.of(context).applyToBoard to set up this position',
                            style: TextStyle(
                              fontStyle: FontStyle.italic,
                              fontSize: 11,
                              color: Colors.blue,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
            ],
          ),
        );

      case DebugStage.originalImage:
      case DebugStage.resizedImage:
      case DebugStage.enhancedImage:
      case DebugStage.boardMaskRaw:
      case DebugStage.boardMaskProcessed:
        return const SizedBox.shrink(); // Other stages do not display overlay
    }
  }

  /// Build base layer (display different content based on different stages)
  Widget _buildBaseLayer() {
    switch (_currentStage) {
      case DebugStage.originalImage:
        // Use cached original image, if available
        if (_cachedOriginalImage != null) {
          return Image.memory(_cachedOriginalImage!, fit: BoxFit.contain);
        }
        return _buildImageNotAvailable('Original Image');

      case DebugStage.resizedImage:
        // Resized image
        if (_cachedResizedImage != null) {
          return Image.memory(_cachedResizedImage!, fit: BoxFit.contain);
        }
        return _buildImageNotAvailable('Resized Image');

      case DebugStage.enhancedImage:
        // Use cached contrast-enhanced image
        if (_cachedEnhancedImage != null) {
          return Image.memory(_cachedEnhancedImage!, fit: BoxFit.contain);
        }
        return _buildImageNotAvailable('Enhanced Contrast Image');

      case DebugStage.boardMaskRaw:
        // Display initial board mask
        if (widget.debugInfo?.boardMask != null) {
          return CustomPaint(
            painter: MaskPainter(
              mask: widget.debugInfo!.boardMask!,
              imageSize: Size(
                widget.processedImageWidth.toDouble(),
                widget.processedImageHeight.toDouble(),
              ),
              maskColor: Colors.blue.withValues(alpha: 0.7),
              label: 'Initial Mask',
            ),
          );
        }
        return _buildImageNotAvailable('Initial Board Mask');

      case DebugStage.boardMaskProcessed:
        // Display processed board mask (after dilation/erosion)
        if (_processedMask != null) {
          return CustomPaint(
            painter: MaskPainter(
              mask: _processedMask!,
              imageSize: Size(
                widget.processedImageWidth.toDouble(),
                widget.processedImageHeight.toDouble(),
              ),
              maskColor: Colors.green.withValues(alpha: 0.7),
              label: 'Processed Mask',
            ),
          );
        }
        return _buildImageNotAvailable('Processed Mask');

      case DebugStage.boardDetection:
        // Use original image as background in board detection step for easier detection result visibility
        return Image.memory(widget.imageBytes, fit: BoxFit.cover);

      case DebugStage.boardPointsDetection:
      case DebugStage.colorAnalysis:
      case DebugStage.pieceDetection:
      case DebugStage.finalResult:
        return Image.memory(widget.imageBytes, fit: BoxFit.cover);
    }
  }

  /// Build image not available display
  Widget _buildImageNotAvailable(String label) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.image_not_supported, size: 48),
          Text('$label Not Available'),
        ],
      ),
    );
  }

  /// Build stage information text
  Widget _buildStageInfo() {
    switch (_currentStage) {
      case DebugStage.originalImage:
        final img.Image? original = widget.debugInfo?.originalImage;
        if (original == null) {
          return const Text('Original Image Information Not Available');
        }
        return Text(
          'Original Image: ${original.width}x${original.height} Pixels',
          style: const TextStyle(fontWeight: FontWeight.bold),
        );

      case DebugStage.resizedImage:
        return Text(
          'Resized: ${widget.processedImageWidth}x${widget.processedImageHeight} Pixels',
          style: const TextStyle(fontWeight: FontWeight.bold),
        );

      case DebugStage.enhancedImage:
        final ImageCharacteristics? chars = widget.debugInfo?.characteristics;
        if (chars == null) {
          return const Text('Enhanced Image Information Not Available');
        }
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                'Enhanced Contrast: Contrast Factor=1.8',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                'Brightness=${chars.averageBrightness.toStringAsFixed(1)}, '
                '${chars.isDarkBackground ? "Dark Background" : "Light Background"}, '
                'Contrast=${chars.isHighContrast ? "High" : "Low"}, '
                'Contrast Ratio=${chars.contrastRatio.toStringAsFixed(2)}',
              ),
            ],
          ),
        );

      case DebugStage.boardMaskRaw:
        final List<List<bool>>? mask = widget.debugInfo?.boardMask;
        if (mask == null) {
          return const Text('Board Mask Information Not Available');
        }

        // Calculate the number of set points in the mask
        int setPoints = 0;
        for (final List<bool> row in mask) {
          for (final bool value in row) {
            if (value) {
              setPoints++;
            }
          }
        }
        return Text(
          'Initial Board Mask: ${mask.length} Rows, Mask Point Count=$setPoints',
          style: const TextStyle(fontWeight: FontWeight.bold),
        );

      case DebugStage.boardMaskProcessed:
        return const Text(
          'Mask Processing: Dilation (Expand Area) -> Erosion (Remove Noise)',
          style: TextStyle(fontWeight: FontWeight.bold),
        );

      case DebugStage.boardDetection:
        final math.Rectangle<int>? rect = widget.debugInfo?.boardRect;
        if (rect == null) {
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  S.of(context).boardDetectionFailed,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                  ),
                ),
                const SizedBox(height: 4),
                const Text('Possible Reasons:'),
                const Text('1. Insufficient Board Area Contrast'),
                const Text('2. Board is Obstructed or Out of Image Range'),
                const Text(
                    '3. Poor Lighting Conditions Causing Board Boundary Blur'),
                const Text(
                    'Suggestion: Try Taking a Picture in a Well-lit Environment to Ensure Complete and Clear Visibility of the Board'),
              ],
            ),
          );
        }
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                'Board Region Detection Result: ',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text('Top-left: (${rect.left}, ${rect.top})'),
              Text('Size: Width=${rect.width}, Height=${rect.height}'),
              Text(
                  'Aspect Ratio: ${(rect.width / rect.height).toStringAsFixed(2)}'),
              const Text('Yellow Rectangle Indicates Detected Board Area'),
            ],
          ),
        );

      case DebugStage.boardPointsDetection:
        final int pointCount = widget.boardPoints.length;
        if (pointCount == 0) {
          return const SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'No board point detected!',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                  ),
                ),
                SizedBox(height: 4),
                Text('Possible Reasons:'),
                Text('1. Board Area Detection Failed'),
                Text(
                    '2. Board Pattern Does Not Match Standard Nine-piece Chess Layout'),
                Text(
                    'Suggestion: Ensure Using Standard Nine-piece Chess Board'),
              ],
            ),
          );
        }
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                'Board Point Detection Result: ',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text('Detected $pointCount Points (Should Be 24)'),
              const Text(
                  'Blue Circle Indicates Detected Points, Number Indicates Point Index'),
              if (pointCount < 24)
                const Text(
                    'Warning: Point Count Less Than 24, Detection May Be Inaccurate',
                    style: TextStyle(
                        color: Colors.red, fontWeight: FontWeight.bold)),
            ],
          ),
        );

      case DebugStage.colorAnalysis:
        final ColorProfile? profile = widget.debugInfo?.colorProfile;
        if (profile == null) {
          return const SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Color Analysis Failed!',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                  ),
                ),
                SizedBox(height: 4),
                Text('Possible Reasons:'),
                Text('1. Board Area or Point Detection Failed'),
                Text(
                    '2. Insufficient Image Contrast, Difficult to Distinguish Colors'),
                Text(
                    'Suggestion: Take a Picture in a Uniformly Lit Environment'),
              ],
            ),
          );
        }
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                'Color Analysis Result: ',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                  'White Mean: ${profile.whiteMean.toStringAsFixed(1)}, Standard Deviation: ${profile.whiteStd.toStringAsFixed(1)}'),
              Text(
                  'Black Mean: ${profile.blackMean.toStringAsFixed(1)}, Standard Deviation: ${profile.blackStd.toStringAsFixed(1)}'),
              Text(
                  'Empty Mean: ${profile.emptyMean.toStringAsFixed(1)}, Standard Deviation: ${profile.emptyStd.toStringAsFixed(1)}'),
              const Text(
                  'Orange Indicates White Sample, Blue Indicates Black Sample, Green Indicates Empty Sample'),
            ],
          ),
        );

      case DebugStage.pieceDetection:
        if (widget.boardPoints.isEmpty) {
          return const SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Piece Detection Failed!',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                  ),
                ),
                SizedBox(height: 4),
                Text('Possible Reasons:'),
                Text('1. Board Point Detection Failed'),
                Text('2. Unable to Determine Sampling Point Location'),
                Text(
                    'Suggestion: Ensure Clear Visibility of the Board and Pieces'),
              ],
            ),
          );
        }
        int whiteCount = 0, blackCount = 0;
        for (final PieceColor color in widget.resultMap.values) {
          if (color == PieceColor.white) {
            whiteCount++;
          }
          if (color == PieceColor.black) {
            blackCount++;
          }
        }
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                'Piece Detection Process: ',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const Text(
                  'Analyze Color Characteristics of Each Point to Determine If There Is a Piece'),
              Text(
                  'White Threshold: ${widget.debugInfo?.characteristics?.whiteBrightnessThreshold ?? 0}'),
              Text(
                  'Black Threshold: ${widget.debugInfo?.characteristics?.blackBrightnessThreshold ?? 0}'),
              Text(
                  'Currently Identified: White Pieces=$whiteCount, Black Pieces=$blackCount'),
              const Text(
                  'Yellow Outline Sampling Area, Red Indicates Identified as Black, Green Indicates Identified as White'),
            ],
          ),
        );

      case DebugStage.finalResult:
        if (widget.boardPoints.isEmpty) {
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'Final Recognition Failed',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                  ),
                ),
                const SizedBox(height: 4),
                Text(S.of(context).entireRecognitionProcessFailedToComplete),
                Text(
                    S.of(context).suggestionTryTakingAClearerPictureOfTheBoard),
              ],
            ),
          );
        }

        int whiteCount = 0, blackCount = 0;
        for (final PieceColor color in widget.resultMap.values) {
          if (color == PieceColor.white) {
            whiteCount++;
          }
          if (color == PieceColor.black) {
            blackCount++;
          }
        }

        // Generate a temporary FEN string for display using the public static method
        final String? fenString =
            BoardRecognitionDebugView.generateTempFenString(widget.resultMap);

        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                'Final Recognition Result: ',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text('White Pieces: $whiteCount'),
              Text('Black Pieces: $blackCount'),
              const Text(
                  'Red Circle Indicates Black Pieces, Green Circle Indicates White Pieces'),
              const SizedBox(height: 10),
              // Add FEN string display
              if (fenString != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text(
                      'FEN:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black12,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.grey),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            fenString,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Click S.of(context).applyToBoard to set up this position',
                            style: TextStyle(
                              fontStyle: FontStyle.italic,
                              fontSize: 11,
                              color: Colors.blue,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
            ],
          ),
        );
    }
  }
}

/// Custom canvas for drawing mask
class MaskPainter extends CustomPainter {
  MaskPainter({
    required this.mask,
    required this.imageSize,
    this.maskColor = Colors.white,
    this.label,
  });

  final List<List<bool>> mask;
  final Size imageSize;
  final Color maskColor;
  final String? label;

  @override
  void paint(Canvas canvas, Size size) {
    // Draw black background
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = Colors.black,
    );

    // Calculate scaling ratio
    final double scaleX = size.width / imageSize.width;
    final double scaleY = size.height / imageSize.height;

    // Draw mask (specified color part)
    final Paint maskPaint = Paint()..color = maskColor.withValues(alpha: 0.7);

    // To optimize performance, we draw small rectangles instead of single pixels
    for (int y = 0; y < mask.length; y += 2) {
      for (int x = 0; x < mask[y].length; x += 2) {
        if (y < mask.length && x < mask[y].length && mask[y][x]) {
          canvas.drawRect(
            Rect.fromLTWH(
              x * scaleX,
              y * scaleY,
              2 * scaleX,
              2 * scaleY,
            ),
            maskPaint,
          );
        }
      }
    }

    // If there is a label, draw label text
    if (label != null) {
      final TextPainter textPainter = TextPainter(
        text: TextSpan(
          text: label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
            backgroundColor: Colors.black54,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        const Offset(10, 10),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}

/// Custom canvas for drawing board points
class BoardPointsDebugPainter extends CustomPainter {
  BoardPointsDebugPainter({
    required this.boardPoints,
    required this.imageSize,
  });

  final List<BoardPoint> boardPoints;
  final Size imageSize;

  @override
  void paint(Canvas canvas, Size size) {
    // Calculate scaling ratio
    final double scaleX = size.width / imageSize.width;
    final double scaleY = size.height / imageSize.height;

    // Draw each point
    for (int i = 0; i < boardPoints.length; i++) {
      final BoardPoint point = boardPoints[i];

      // Draw point circle
      final Paint pointPaint = Paint()
        ..color = Colors.blue
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;

      canvas.drawCircle(
        Offset(point.x * scaleX, point.y * scaleY),
        point.radius * scaleX * 0.8,
        pointPaint,
      );

      // Draw point index
      final TextPainter textPainter = TextPainter(
        text: TextSpan(
          text: '$i',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.bold,
            backgroundColor: Colors.black54,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(
          point.x * scaleX - textPainter.width / 2,
          point.y * scaleY - textPainter.height / 2,
        ),
      );

      // Draw different color small points based on point location in different rings
      final Paint innerPointPaint = Paint()
        ..color = i < 8 ? Colors.red : (i < 16 ? Colors.yellow : Colors.green)
        ..style = PaintingStyle.fill;

      canvas.drawCircle(
        Offset(point.x * scaleX, point.y * scaleY),
        3.0,
        innerPointPaint,
      );
    }

    // Draw legend
    final TextPainter legendPainter = TextPainter(
      text: const TextSpan(
        text: 'Red=Outer Ring, Yellow=Middle Ring, Green=Inner Ring',
        style: TextStyle(
          color: Colors.white,
          fontSize: 12,
          backgroundColor: Colors.black54,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    legendPainter.layout();
    legendPainter.paint(
      canvas,
      Offset(10, size.height - legendPainter.height - 10),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}

/// Custom canvas for displaying color analysis
class ColorAnalysisPainter extends CustomPainter {
  ColorAnalysisPainter({
    required this.boardPoints,
    required this.imageSize,
    this.colorProfile,
  });

  final List<BoardPoint> boardPoints;
  final Size imageSize;
  final ColorProfile? colorProfile;

  @override
  void paint(Canvas canvas, Size size) {
    if (colorProfile == null) {
      return;
    }

    // Calculate scaling ratio
    final double scaleX = size.width / imageSize.width;
    final double scaleY = size.height / imageSize.height;

    // Draw color analysis result of each point
    for (int i = 0; i < boardPoints.length; i++) {
      final BoardPoint point = boardPoints[i];

      // Determine color category based on point average brightness
      final double brightness = (i % 3 == 0)
          ? colorProfile!
              .whiteMean // Example: Take every 3rd point as white sample
          : (i % 3 == 1)
              ? colorProfile!
                  .blackMean // Example: Take every 3rd point as black sample
              : colorProfile!
                  .emptyMean; // Example: Other points as empty sample

      // Determine point color based on brightness
      final Color pointColor = (i % 3 == 0)
          ? Colors.orange // White sample
          : (i % 3 == 1)
              ? Colors.blue // Black sample
              : Colors.green; // Empty sample

      // Draw point circle
      final Paint pointPaint = Paint()
        ..color = pointColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;

      canvas.drawCircle(
        Offset(point.x * scaleX, point.y * scaleY),
        point.radius * scaleX * 0.7,
        pointPaint,
      );

      // Draw brightness value
      final TextPainter textPainter = TextPainter(
        text: TextSpan(
          text: brightness.toStringAsFixed(0),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            backgroundColor: Colors.black54,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(
          point.x * scaleX - textPainter.width / 2,
          point.y * scaleY - textPainter.height / 2,
        ),
      );
    }

    // Draw statistics information
    final TextPainter statsPainter = TextPainter(
      text: TextSpan(
        children: <TextSpan>[
          const TextSpan(
            text: 'Color Statistics: ',
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          TextSpan(
            text:
                'White=${colorProfile!.whiteMean.toStringAsFixed(1)}±${colorProfile!.whiteStd.toStringAsFixed(1)} ',
            style: const TextStyle(
              color: Colors.orange,
              fontSize: 12,
            ),
          ),
          TextSpan(
            text:
                'Black=${colorProfile!.blackMean.toStringAsFixed(1)}±${colorProfile!.blackStd.toStringAsFixed(1)} ',
            style: const TextStyle(
              color: Colors.blue,
              fontSize: 12,
            ),
          ),
          TextSpan(
            text:
                'Empty=${colorProfile!.emptyMean.toStringAsFixed(1)}±${colorProfile!.emptyStd.toStringAsFixed(1)}',
            style: const TextStyle(
              color: Colors.green,
              fontSize: 12,
            ),
          ),
        ],
        style: const TextStyle(
          backgroundColor: Colors.black54,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    statsPainter.layout();
    statsPainter.paint(
      canvas,
      const Offset(10, 10),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}

/// Custom canvas for displaying piece detection process
class PieceDetectionPainter extends CustomPainter {
  PieceDetectionPainter({
    required this.boardPoints,
    required this.resultMap,
    required this.imageSize,
    this.showDetails = false,
  });

  final List<BoardPoint> boardPoints;
  final Map<int, PieceColor> resultMap;
  final Size imageSize;
  final bool showDetails;

  @override
  void paint(Canvas canvas, Size size) {
    // Calculate scaling ratio
    final double scaleX = size.width / imageSize.width;
    final double scaleY = size.height / imageSize.height;

    // Draw recognition result of each point
    for (int i = 0; i < boardPoints.length; i++) {
      final BoardPoint point = boardPoints[i];
      final PieceColor? pieceColor = resultMap[i];

      // Draw sampling area (yellow dashed circle)
      final Paint samplingAreaPaint = Paint()
        ..color = Colors.yellow.withValues(alpha: 0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;

      canvas.drawCircle(
        Offset(point.x * scaleX, point.y * scaleY),
        point.radius *
            scaleX *
            0.75, // Sampling area slightly smaller than actual radius
        samplingAreaPaint,
      );

      // If there is a piece, draw piece recognition result
      if (pieceColor != null && pieceColor != PieceColor.none) {
        final Paint piecePaint = Paint()
          ..color = pieceColor == PieceColor.white ? Colors.green : Colors.red
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0;

        canvas.drawCircle(
          Offset(point.x * scaleX, point.y * scaleY),
          point.radius * scaleX,
          piecePaint,
        );

        // If display detailed information, draw recognition type
        if (showDetails) {
          final TextPainter textPainter = TextPainter(
            text: TextSpan(
              text: pieceColor == PieceColor.white ? 'W' : 'B',
              style: TextStyle(
                color:
                    pieceColor == PieceColor.white ? Colors.green : Colors.red,
                fontSize: 14,
                fontWeight: FontWeight.bold,
                backgroundColor: Colors.black54,
              ),
            ),
            textDirection: TextDirection.ltr,
          );
          textPainter.layout();
          textPainter.paint(
            canvas,
            Offset(
              point.x * scaleX - textPainter.width / 2,
              point.y * scaleY - textPainter.height / 2,
            ),
          );
        }
      } else {
        // Empty point, draw X mark
        if (showDetails) {
          final Paint emptyPaint = Paint()
            ..color = Colors.grey
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5;

          final double crossSize = point.radius * scaleX * 0.4;

          canvas.drawLine(
            Offset(point.x * scaleX - crossSize, point.y * scaleY - crossSize),
            Offset(point.x * scaleX + crossSize, point.y * scaleY + crossSize),
            emptyPaint,
          );

          canvas.drawLine(
            Offset(point.x * scaleX + crossSize, point.y * scaleY - crossSize),
            Offset(point.x * scaleX - crossSize, point.y * scaleY + crossSize),
            emptyPaint,
          );
        }
      }

      // Draw point index
      final TextPainter indexPainter = TextPainter(
        text: TextSpan(
          text: '$i',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            backgroundColor: Colors.black54,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      indexPainter.layout();
      indexPainter.paint(
        canvas,
        Offset(
          point.x * scaleX - 12,
          point.y * scaleY - 12,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}

/// Custom canvas for displaying board area overlay
class BoardRectOverlay extends StatelessWidget {
  const BoardRectOverlay({
    super.key,
    required this.boardRect,
    required this.imageSize,
  });

  final math.Rectangle<int> boardRect;
  final Size imageSize;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.infinite,
      painter: BoardRectPainter(
        boardRect: boardRect,
        imageSize: imageSize,
      ),
    );
  }
}

/// Custom canvas for drawing board area rectangle
class BoardRectPainter extends CustomPainter {
  BoardRectPainter({
    required this.boardRect,
    required this.imageSize,
  });

  final math.Rectangle<int> boardRect;
  final Size imageSize;

  @override
  void paint(Canvas canvas, Size size) {
    // Calculate scaling ratio
    final double scaleX = size.width / imageSize.width;
    final double scaleY = size.height / imageSize.height;

    final Rect scaledRect = Rect.fromLTWH(
      boardRect.left * scaleX,
      boardRect.top * scaleY,
      boardRect.width * scaleX,
      boardRect.height * scaleY,
    );

    // Draw yellow dashed rectangle
    final Paint rectPaint = Paint()
      ..color = Colors.yellow
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    // Draw dashed line
    final Path path = Path();
    const double dashWidth = 10.0;
    const double dashSpace = 5.0;
    double distance = 0.0;

    // Draw top side
    path.moveTo(scaledRect.left, scaledRect.top);
    bool draw = true;
    while (distance < scaledRect.width) {
      double currentWidth = distance + (draw ? dashWidth : dashSpace);
      if (currentWidth > scaledRect.width) {
        currentWidth = scaledRect.width;
      }

      if (draw) {
        path.lineTo(scaledRect.left + currentWidth, scaledRect.top);
      } else {
        path.moveTo(scaledRect.left + currentWidth, scaledRect.top);
      }

      distance = currentWidth;
      draw = !draw;
    }

    // Draw right side
    distance = 0.0;
    draw = true;
    while (distance < scaledRect.height) {
      double currentHeight = distance + (draw ? dashWidth : dashSpace);
      if (currentHeight > scaledRect.height) {
        currentHeight = scaledRect.height;
      }

      if (draw) {
        path.lineTo(scaledRect.right, scaledRect.top + currentHeight);
      } else {
        path.moveTo(scaledRect.right, scaledRect.top + currentHeight);
      }

      distance = currentHeight;
      draw = !draw;
    }

    // Draw bottom side
    distance = 0.0;
    draw = true;
    while (distance < scaledRect.width) {
      double currentWidth = distance + (draw ? dashWidth : dashSpace);
      if (currentWidth > scaledRect.width) {
        currentWidth = scaledRect.width;
      }

      if (draw) {
        path.lineTo(scaledRect.right - currentWidth, scaledRect.bottom);
      } else {
        path.moveTo(scaledRect.right - currentWidth, scaledRect.bottom);
      }

      distance = currentWidth;
      draw = !draw;
    }

    // Draw left side
    distance = 0.0;
    draw = true;
    while (distance < scaledRect.height) {
      double currentHeight = distance + (draw ? dashWidth : dashSpace);
      if (currentHeight > scaledRect.height) {
        currentHeight = scaledRect.height;
      }

      if (draw) {
        path.lineTo(scaledRect.left, scaledRect.bottom - currentHeight);
      } else {
        path.moveTo(scaledRect.left, scaledRect.bottom - currentHeight);
      }

      distance = currentHeight;
      draw = !draw;
    }

    canvas.drawPath(path, rectPaint);

    // Draw four corners for enhanced display
    const double cornerSize = 15.0;
    final Paint cornerPaint = Paint()
      ..color = Colors.yellow
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0;

    // Top-left corner
    canvas.drawLine(
      Offset(scaledRect.left, scaledRect.top + cornerSize),
      Offset(scaledRect.left, scaledRect.top),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(scaledRect.left, scaledRect.top),
      Offset(scaledRect.left + cornerSize, scaledRect.top),
      cornerPaint,
    );

    // Top-right corner
    canvas.drawLine(
      Offset(scaledRect.right - cornerSize, scaledRect.top),
      Offset(scaledRect.right, scaledRect.top),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(scaledRect.right, scaledRect.top),
      Offset(scaledRect.right, scaledRect.top + cornerSize),
      cornerPaint,
    );

    // Bottom-right corner
    canvas.drawLine(
      Offset(scaledRect.right, scaledRect.bottom - cornerSize),
      Offset(scaledRect.right, scaledRect.bottom),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(scaledRect.right, scaledRect.bottom),
      Offset(scaledRect.right - cornerSize, scaledRect.bottom),
      cornerPaint,
    );

    // Bottom-left corner
    canvas.drawLine(
      Offset(scaledRect.left + cornerSize, scaledRect.bottom),
      Offset(scaledRect.left, scaledRect.bottom),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(scaledRect.left, scaledRect.bottom),
      Offset(scaledRect.left, scaledRect.bottom - cornerSize),
      cornerPaint,
    );

    // Draw text label
    const TextSpan textSpan = TextSpan(
      text: 'Detected Board Area',
      style: TextStyle(
        color: Colors.yellow,
        fontSize: 16,
        fontWeight: FontWeight.bold,
        backgroundColor: Colors.black54,
      ),
    );

    final TextPainter textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    );

    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(
        scaledRect.left + 5,
        scaledRect.top - textPainter.height - 5,
      ),
    );

    // Draw rectangle size information
    final TextSpan sizeSpan = TextSpan(
      text: '${boardRect.width} x ${boardRect.height}',
      style: const TextStyle(
        color: Colors.white,
        fontSize: 14,
        fontWeight: FontWeight.bold,
        backgroundColor: Colors.black54,
      ),
    );

    final TextPainter sizePainter = TextPainter(
      text: sizeSpan,
      textDirection: TextDirection.ltr,
    );

    sizePainter.layout();
    sizePainter.paint(
      canvas,
      Offset(
        scaledRect.right - sizePainter.width - 5,
        scaledRect.bottom + 5,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}
