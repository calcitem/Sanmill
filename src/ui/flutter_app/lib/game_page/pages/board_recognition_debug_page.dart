// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// board_recognition_debug_page.dart

import 'dart:async';
import 'dart:math' as math;

import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import '../../generated/intl/l10n.dart';
import '../../shared/database/database.dart';
import '../../shared/services/logger.dart';
import '../../shared/widgets/snackbars/scaffold_messenger.dart';
import '../services/board_image_recognition.dart';
import '../services/mill.dart';
import '../widgets/board_recognition_debug_view.dart';

class BoardRecognitionDebugPage extends StatefulWidget {
  const BoardRecognitionDebugPage({super.key});

  /// Create a dialog content widget for showing recognition results
  /// This returns the dialog content instead of showing dialog directly
  static Widget createRecognitionResultDialog({
    required Uint8List imageBytes,
    required Map<int, PieceColor> result,
    required List<BoardPoint> boardPoints,
    required int processedWidth,
    required int processedHeight,
    required Function(bool) onResult,
    BoardRecognitionDebugInfo? debugInfo,
    required BuildContext context,
  }) {
    // Count pieces by color
    int whiteCount = 0;
    int blackCount = 0;
    for (final PieceColor color in result.values) {
      if (color == PieceColor.white) {
        whiteCount++;
      } else if (color == PieceColor.black) {
        blackCount++;
      }
    }

    // Generate FEN string for display and copying
    final String? fen = BoardRecognitionDebugView.generateTempFenString(result);

    // Return the dialog content widget
    return AlertDialog(
      title: Text(S.of(context).identificationResults),
      contentPadding: const EdgeInsets.fromLTRB(8, 20, 8, 24),
      content: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 300, maxWidth: 800),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              // Display recognition result visualization
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: BoardRecognitionDebugView(
                  imageBytes: imageBytes,
                  boardPoints: boardPoints,
                  resultMap: result,
                  processedImageWidth: processedWidth,
                  processedImageHeight: processedHeight,
                  debugInfo: debugInfo,
                  showTitle: true,
                ),
              ),
              const SizedBox(height: 16),
              // Display statistics
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    // White pieces count
                    Expanded(
                      child: Column(
                        children: <Widget>[
                          const Icon(
                            Icons.circle_outlined,
                            color: Colors.green,
                            size: 24,
                          ),
                          Text("${S.of(context).whitePiece}: $whiteCount"),
                        ],
                      ),
                    ),
                    // Black pieces count
                    Expanded(
                      child: Column(
                        children: <Widget>[
                          const Icon(
                            Icons.circle,
                            color: Colors.red,
                            size: 24,
                          ),
                          Text("${S.of(context).blackPiece}: $blackCount"),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Add FEN display and copy button
              if (fen != null) ...<Widget>[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          const Text(
                            'Generated FEN:',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const Spacer(),
                          // Copy button for FEN string
                          ElevatedButton.icon(
                            onPressed: () async {
                              // Capture localized string before async gap
                              final String copiedMsg =
                                  S.of(context).fenCopiedToClipboard;
                              await Clipboard.setData(ClipboardData(text: fen));
                              rootScaffoldMessengerKey.currentState
                                  ?.showSnackBar(
                                SnackBar(
                                  content: Text(copiedMsg),
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                            },
                            icon: const Icon(Icons.copy),
                            label: const Text('Copy'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              minimumSize: const Size(0, 36),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SelectableText(
                        fen,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          S.of(context).viewTips,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const Text(
                            'Use the buttons above to select different processing stages, and swipe left or right to view all stages.'),
                        const Text(
                            'If the recognition is not accurate, try taking a picture of the board in better lighting conditions.'),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => onResult(false),
          child: Text(S.of(context).cancel),
        ),
        // Copy FEN button in action bar (additional option)
        if (fen != null)
          TextButton.icon(
            onPressed: () async {
              final String copiedMsg = S.of(context).fenCopiedToClipboard;
              await Clipboard.setData(ClipboardData(text: fen));
              rootScaffoldMessengerKey.currentState?.showSnackBar(
                SnackBar(
                  content: Text(copiedMsg),
                  duration: const Duration(seconds: 2),
                ),
              );
            },
            icon: const Icon(Icons.copy),
            label: Text(S.of(context).copyFen),
          ),
        ElevatedButton(
          onPressed: () => onResult(true),
          child: Text(S.of(context).applyThisResultToBoard),
        ),
      ],
    );
  }

  /// Apply the recognition result to the game board using FEN
  /// This function generates a FEN string from the result and uses setFen to update the position.
  static Future<void> applyRecognitionResultToBoard(
      Map<int, PieceColor> result, BuildContext context) async {
    logger.i("---------------- BOARD RECOGNITION DEBUG ----------------");
    logger.i("Starting recognition result application process");

    // Log the input data for debugging
    logger.i("Recognition result map contains ${result.length} pieces:");
    int whitePieces = 0;
    int blackPieces = 0;
    for (final MapEntry<int, PieceColor> entry in result.entries) {
      if (entry.value == PieceColor.white) {
        whitePieces++;
      }
      if (entry.value == PieceColor.black) {
        blackPieces++;
      }
    }
    logger.i("White pieces: $whitePieces, Black pieces: $blackPieces");

    // Capture localized strings early to avoid using `context` after async gaps
    final String msgFenApplied =
        S.of(context).boardPositionAppliedFenCopiedToClipboard;
    // Use a simple error string instead of S.of(context).error
    const String errorPrefix = "Error";

    // Display input data in snackbar
    rootScaffoldMessengerKey.currentState?.clearSnackBars();
    rootScaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text(
            "Applying board with $whitePieces white and $blackPieces black pieces"),
        duration: const Duration(seconds: 2),
      ),
    );

    // 1. Generate FEN from the recognition result using the public static method
    logger.i("Generating FEN string from recognition result...");
    final String? fen = BoardRecognitionDebugView.generateTempFenString(result);

    if (fen == null) {
      logger.e("Failed to generate FEN string from recognition result.");
      rootScaffoldMessengerKey.currentState?.showSnackBar(
        const SnackBar(
            content: Text("$errorPrefix: Could not generate board state.")),
      );
      return;
    }
    logger.i("Generated FEN: '$fen'");

    // Automatically copy FEN to clipboard
    await Clipboard.setData(ClipboardData(text: fen));
    logger.i("FEN copied to clipboard automatically: $fen");

    // Display FEN in snackbar for debugging
    rootScaffoldMessengerKey.currentState?.clearSnackBars();
    rootScaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text("FEN copied to clipboard automatically"),
            Text("FEN: $fen",
                style: const TextStyle(fontFamily: 'monospace', fontSize: 10)),
            const Text(
                "Try pasting this FEN in the game manually if the automatic application doesn't work"),
          ],
        ),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'OK',
          onPressed: () {
            rootScaffoldMessengerKey.currentState?.hideCurrentSnackBar();
          },
        ),
      ),
    );
    await Future<void>.delayed(
        const Duration(seconds: 1)); // Give time to see the snackbar

    // 2. Validate the generated FEN
    logger.i("Validating FEN...");
    final Position tempPos = Position();
    if (!tempPos.validateFen(fen)) {
      logger.e("Invalid FEN generated: '$fen'");
      rootScaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(
            content: Text(
                "$errorPrefix: Invalid board state generated (FEN: $fen).")),
      );
      return;
    }
    logger.i("FEN validation passed");

    // 3. Ensure we are in setup position mode *before* applying the FEN
    logger.i("Current gameMode: ${GameController().gameInstance.gameMode}");
    if (GameController().gameInstance.gameMode != GameMode.setupPosition) {
      logger.i("Switching to setup position mode before applying FEN");
      GameController().gameInstance.gameMode = GameMode.setupPosition;
    }

    // 4. Apply the FEN to the main Position object
    logger.i("Applying FEN to main Position object...");

    // Backup current position state before reset (for debugging)
    final String? oldFen = GameController().position.fen;
    logger.i("Current position FEN before reset: '$oldFen'");

    // Reset position first
    GameController().position.reset();
    logger.i("Position reset completed");

    // Set the FEN
    final bool success = GameController().position.setFen(fen);
    logger.i("setFen result: $success");

    if (!success) {
      logger.e("Failed to apply FEN to position object: '$fen'");
      rootScaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                  "$errorPrefix: Failed to apply board state automatically."),
              const Text(
                  "Please try setting up the position manually using the copied FEN."),
              Text("FEN: $fen",
                  style:
                      const TextStyle(fontFamily: 'monospace', fontSize: 10)),
            ],
          ),
          duration: const Duration(seconds: 10),
        ),
      );
      return;
    }

    // Verify the position state after setting FEN
    final String? newFen = GameController().position.fen;
    logger.i("Position FEN after setFen: '$newFen'");

    // Log the counts to verify
    logger.i(
        "White pieces on board: ${GameController().position.pieceOnBoardCount[PieceColor.white]}");
    logger.i(
        "Black pieces on board: ${GameController().position.pieceOnBoardCount[PieceColor.black]}");
    logger.i("Side to move: ${GameController().position.sideToMove}");
    logger.i("Phase: ${GameController().position.phase}");

    // 5. Update the Game Recorder with the new setup FEN
    logger.i("Updating GameRecorder with setup FEN.");
    GameController().gameRecorder =
        GameRecorder(lastPositionWithRemove: fen, setupPosition: fen);

    // 6. Update UI elements
    logger.i("Updating UI elements...");

    // Force redraw all pieces
    GameController().position.action =
        Act.select; // Ensure correct action state

    // Debug: Check the board state by counting pieces
    final Position position = GameController().position;
    logger.i("Board state check:");
    logger.i(
        "- Total white pieces on board: ${position.countPieceOnBoard(PieceColor.white)}");
    logger.i(
        "- Total black pieces on board: ${position.countPieceOnBoard(PieceColor.black)}");

    // Get another copy of FEN to verify the position state didn't change
    final String? currentFen = position.fen;
    logger.i("Current position FEN after updates: '$currentFen'");

    // Ensure we have the correct game mode
    logger.i(
        "Game mode after FEN application: ${GameController().gameInstance.gameMode}");

    // Update UI notifiers with strong refresh attempts
    GameController().setupPositionNotifier.updateIcons();
    logger.i("setupPositionNotifier.updateIcons() called");

    GameController().boardSemanticsNotifier.updateSemantics();
    logger.i("boardSemanticsNotifier.updateSemantics() called");

    GameController().headerIconsNotifier.showIcons();
    logger.i("headerIconsNotifier.showIcons() called");

    // Try a different approach - rebuild the position from scratch with a new FEN application
    logger.i(
        "Trying alternative approach with new GameRecorder and forced rebuild");
    Future<void>.delayed(const Duration(milliseconds: 200), () {
      logger.i("Running delayed rebuild of position...");

      // 1. First create a fresh game recorder with our FEN
      GameController().gameRecorder =
          GameRecorder(lastPositionWithRemove: fen, setupPosition: fen);

      // 2. Force the position to completely refresh from the FEN
      GameController().position.reset();
      GameController().position.setFen(fen);

      // 3. Update UI again after rebuilding
      GameController().setupPositionNotifier.updateIcons();
      GameController().boardSemanticsNotifier.updateSemantics();
      GameController().headerIconsNotifier.showIcons();

      logger.i("Rebuild completed");
    });

    logger.i("Recognition result application completed");
    logger.i("--------------------------------------------------------");

    // 7. Show confirmation SnackBar with FEN for debugging
    rootScaffoldMessengerKey.currentState?.clearSnackBars();
    rootScaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(msgFenApplied),
            SelectableText("FEN: $fen",
                style: const TextStyle(fontFamily: 'monospace', fontSize: 10)),
            const SizedBox(height: 8),
            Text("Pieces detected: White=$whitePieces, Black=$blackPieces"),
            Text(
                "Pieces in Position: White=${position.countPieceOnBoard(PieceColor.white)}, Black=${position.countPieceOnBoard(PieceColor.black)}"),
            const SizedBox(height: 4),
            const Text("Debug: Pieces by Location",
                style: TextStyle(fontWeight: FontWeight.bold)),
            SelectableText(
              _formatRecognitionResults(result),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 9),
            ),
          ],
        ),
        duration: const Duration(seconds: 15),
      ),
    );
  }

  /// Format recognition results into a readable string for debugging
  static String _formatRecognitionResults(Map<int, PieceColor> result) {
    final StringBuffer buffer = StringBuffer();

    // Collect white pieces
    buffer.writeln("White pieces at squares:");
    final List<int> whiteSquares = <int>[];
    for (final MapEntry<int, PieceColor> entry in result.entries) {
      if (entry.value == PieceColor.white) {
        whiteSquares.add(entry.key);
      }
    }
    buffer.writeln(whiteSquares.join(', '));

    // Collect black pieces
    buffer.writeln("Black pieces at squares:");
    final List<int> blackSquares = <int>[];
    for (final MapEntry<int, PieceColor> entry in result.entries) {
      if (entry.value == PieceColor.black) {
        blackSquares.add(entry.key);
      }
    }
    buffer.writeln(blackSquares.join(', '));

    return buffer.toString();
  }

  /// Show recognition result in a dialog
  /// This can be called from anywhere to display recognition results
  static Future<bool> showRecognitionResultDialog(
    BuildContext context, {
    required Uint8List imageBytes,
    required Map<int, PieceColor> result,
    required List<BoardPoint> boardPoints,
    required int processedWidth,
    required int processedHeight,
    BoardRecognitionDebugInfo? debugInfo,
  }) async {
    // Using a Completer to handle dialog result asynchronously
    final Completer<bool> completer = Completer<bool>();

    // Show the dialog with a post-frame callback to avoid build-time issues
    WidgetsBinding.instance.addPostFrameCallback((_) {
      showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return createRecognitionResultDialog(
            imageBytes: imageBytes,
            result: result,
            boardPoints: boardPoints,
            processedWidth: processedWidth,
            processedHeight: processedHeight,
            debugInfo: debugInfo ?? BoardImageRecognitionService.lastDebugInfo,
            context: context,
            onResult: (bool value) {
              Navigator.of(context).pop();

              // If the user clicked "Apply to board" (value is true)
              if (value) {
                // Apply the recognition result to the game board
                applyRecognitionResultToBoard(result, context);
              }

              completer.complete(value);
            },
          );
        },
      );
    });

    // Return the future from completer
    return completer.future.then((bool value) => value);
  }

  @override
  State<BoardRecognitionDebugPage> createState() =>
      _BoardRecognitionDebugPageState();
}

class _BoardRecognitionDebugPageState extends State<BoardRecognitionDebugPage> {
  Uint8List? _lastImageBytes;
  List<BoardPoint> _lastBoardPoints = <BoardPoint>[];
  Map<int, PieceColor> _lastResult = <int, PieceColor>{};
  bool _isProcessing = false;
  String _statusMessage = 'Please select a game board image to identify';

  // --- New state variables for cropping ---
  final CropController _cropController = CropController();
  bool _isAdjustingArea = false; // Flag to control showing the cropper UI
  // Store the original image dimensions for scaling calculations
  int _originalImageWidth = 0;
  int _originalImageHeight = 0;

  // --- End of new state variables ---

  Rect? _lastCropRect;

  // --- Recognition parameters that can be adjusted ---
  // Default values match the original constants in BoardImageRecognitionService
  double _contrastEnhancementFactor = 1.8; // Contrast enhancement factor
  double _pieceThreshold = 0.25; // Piece detection threshold
  double _boardColorDistanceThreshold = 28.0; // Board color distance threshold
  double _pieceColorMatchThreshold = 30.0; // Piece color match threshold
  int _whiteBrightnessThreshold = 170; // White brightness threshold base
  int _blackBrightnessThreshold = 135; // Black brightness threshold base
  double _blackSaturationThreshold = 0.25; // Black saturation threshold
  int _blackColorVarianceThreshold = 40; // Black color variance threshold

  // Flag to show/hide parameter adjustment panel
  bool _showParameterPanel = false;

  // --- End of recognition parameters ---

  @override
  void initState() {
    super.initState();
    _statusMessage = 'Please select a game board image to identify';
  }

  @override
  Widget build(BuildContext context) {
    // --- Cropper UI ---
    if (_isAdjustingArea && _lastImageBytes != null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Adjust Board Area'),
          actions: <Widget>[
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => setState(() => _isAdjustingArea = false),
            ),
            IconButton(
              icon: const Icon(Icons.check),
              onPressed: _confirmCrop,
            ),
          ],
        ),
        body: Crop(
          image: _lastImageBytes!,
          controller: _cropController,
          aspectRatio: 1.0,
          // Provide initialRectBuilder compatible with new crop_your_image API
          initialRectBuilder: InitialRectBuilder.withBuilder(
            (ViewportBasedRect viewportRect, ImageBasedRect imageRect) {
              // Build Rect from imageRect (original image coordinate)
              final Rect imgRect = Rect.fromLTWH(
                imageRect.left,
                imageRect.top,
                imageRect.width,
                imageRect.height,
              );
              final Rect vpRect = Rect.fromLTWH(
                viewportRect.left,
                viewportRect.top,
                viewportRect.width,
                viewportRect.height,
              );

              // Let helper decide preferred initial rect
              final Rect? prefer = _buildInitialCropRect(imgRect);
              return prefer ?? vpRect;
            },
          ),
          baseColor: Colors.blue.shade900,
          maskColor: Colors.white.withAlpha(100),
          cornerDotBuilder: (double size, EdgeAlignment edgeAlignment) =>
              const DotControl(color: Colors.blue),
          interactive: true,
          // Updated onCropped callback for CropResult API
          onCropped: (CropResult result) {
            switch (result) {
              case CropSuccess(:final Uint8List croppedImage):
                logger.i("Image cropped (data size: ${croppedImage.length})");
                // Process the cropped image here
                break;
              case CropFailure(:final Object cause):
                logger.e("Crop failed: $cause");
                break;
            }
          },
          // Fixed onMoved callback signature - takes only ViewportBasedRect parameter
          onMoved: (ViewportBasedRect viewportRect, ImageBasedRect imageRect) {
            _lastCropRect = Rect.fromLTWH(
              viewportRect.left,
              viewportRect.top,
              viewportRect.width,
              viewportRect.height,
            );
            logger.i("Crop rect moved: $_lastCropRect");
          },
          onStatusChanged: (CropStatus status) =>
              logger.i("Cropper status: $status"),
        ),
      );
    }

    // --- Original Debug Page UI ---
    return Scaffold(
      appBar: AppBar(
        title: const Text('Game board recognition debugging'),
        actions: <Widget>[
          // Toggle parameter adjustment panel
          if (_lastImageBytes != null && !_isProcessing)
            IconButton(
              icon: Icon(_showParameterPanel ? Icons.settings : Icons.tune),
              tooltip:
                  _showParameterPanel ? 'Hide Parameters' : 'Show Parameters',
              onPressed: () {
                setState(() {
                  _showParameterPanel = !_showParameterPanel;
                });
              },
            ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                _statusMessage,
                style: const TextStyle(fontSize: 16),
                textAlign: TextAlign.center,
              ),
            ),

            if (_isProcessing)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(child: CircularProgressIndicator()),
              ),

            // --- Parameter Adjustment Panel ---
            if (_showParameterPanel &&
                _lastImageBytes != null &&
                !_isProcessing)
              _buildParameterAdjustmentPanel(),

            if (_lastImageBytes != null && !_isProcessing)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: BoardRecognitionDebugView(
                  imageBytes: _lastImageBytes!,
                  boardPoints: _lastBoardPoints,
                  resultMap: _lastResult,
                  processedImageWidth:
                      BoardImageRecognitionService.processedImageWidth,
                  processedImageHeight:
                      BoardImageRecognitionService.processedImageHeight,
                  debugInfo: BoardImageRecognitionService.lastDebugInfo,
                ),
              ),

            const SizedBox(height: 16),

            if (_lastResult.isNotEmpty && !_isProcessing)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: _buildResultSummary(),
              ),

            // --- Add Adjust Area Button ---
            if (_lastImageBytes != null && !_isAdjustingArea && !_isProcessing)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          final img.Image? decoded =
                              img.decodeImage(_lastImageBytes!);
                          if (decoded != null) {
                            _originalImageWidth = decoded.width;
                            _originalImageHeight = decoded.height;
                            setState(() {
                              _isAdjustingArea = true;
                              _statusMessage =
                                  'Adjust the box to cover the game board area.';
                            });
                          } else {
                            rootScaffoldMessengerKey.currentState?.showSnackBar(
                              const SnackBar(
                                  content:
                                      Text("Failed to read image dimensions.")),
                            );
                          }
                        },
                        icon: const Icon(Icons.crop),
                        label: Text(S.of(context).adjustBoardArea),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orangeAccent),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Add advanced crop button
                    ElevatedButton.icon(
                      onPressed:
                          _lastImageBytes != null && _lastBoardPoints.isNotEmpty
                              ? _showRecognitionResultDialog
                              : null,
                      icon: const Icon(Icons.crop_free),
                      label: const Text('Advanced Crop'),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue),
                    ),
                  ],
                ),
              ),
            // --- End of Adjust Area Button ---

            const SizedBox(height: 16),

            // Action Buttons (Select/Capture) - Only show if not adjusting
            if (!_isAdjustingArea)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: <Widget>[
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed:
                            _isProcessing ? null : _pickAndRecognizeImage,
                        icon: const Icon(Icons.photo_library),
                        label: Text(S.of(context).selectFromAlbum),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed:
                            _isProcessing ? null : _captureAndRecognizeImage,
                        icon: const Icon(Icons.camera_alt),
                        label: Text(S.of(context).photoShoot),
                      ),
                    ),
                  ],
                ),
              ),

            // Apply Button - Only show if not adjusting and have results
            if (_lastResult.isNotEmpty && !_isAdjustingArea && !_isProcessing)
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: ElevatedButton.icon(
                  onPressed: () async {
                    // Apply recognition result to board and wait for completion
                    await BoardRecognitionDebugPage
                        .applyRecognitionResultToBoard(_lastResult, context);

                    // Get the FEN string after applying to board
                    final String? fen = GameController().position.fen;

                    // Remove previous SnackBar and show the FEN
                    if (mounted && fen != null) {
                      // Using custom snackbar clear method to avoid multiple snackbars
                      rootScaffoldMessengerKey.currentState?.clearSnackBars();
                      rootScaffoldMessengerKey.currentState?.showSnackBar(
                        SnackBar(
                          content:
                              Text('Recognition result applied with FEN: $fen'),
                          duration: const Duration(seconds: 5),
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.done),
                  label: Text(S.of(context).applyThisResultToBoard),
                ),
              ),

            const SizedBox(height: 16),

            // Recognition Analysis Tips - Only show if not adjusting
            if (!_isAdjustingArea)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8.0),
                child: Card(
                  margin: EdgeInsets.all(8),
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'Recognition Issue Analysis',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                            'Possible reasons for inaccurate game board recognition:'),
                        Text(
                            '• Lighting conditions: Too bright or too dark environment will affect color detection'),
                        Text(
                            '• Angle problem: Non-frontal shooting will cause game board deformation'),
                        Text(
                            '• Game board contrast: The game board and background colors are similar and will affect area detection'),
                        Text(
                            '• Chess piece overlap: Chess pieces that are too close may be misidentified'),
                        Text(
                            '• Image quality: Blurred or low-resolution images are difficult to recognize correctly'),
                        SizedBox(height: 8),
                        Text('Debug information for each processing stage:'),
                        Text(
                            '• Use the buttons above to select different processing stages, and swipe left or right to view all stages.'),
                        // ... (removed detailed stage descriptions for brevity, can be added back if needed)
                      ],
                    ),
                  ),
                ),
              ),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  /// Build a parameter adjustment panel with sliders for all thresholds
  Widget _buildParameterAdjustmentPanel() {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                const Text(
                  'Recognition Parameters',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                ElevatedButton(
                  onPressed: _reprocessWithCurrentParameters,
                  child: const Text('Apply & Reprocess'),
                ),
              ],
            ),
            const Divider(),

            // Contrast Enhancement Factor
            _buildParameterSlider(
              label: 'Contrast Enhancement',
              value: _contrastEnhancementFactor,
              min: 1.0,
              max: 3.0,
              divisions: 20,
              onChanged: (double value) {
                setState(() {
                  _contrastEnhancementFactor = value;
                });
              },
            ),

            // Piece Detection Threshold
            _buildParameterSlider(
              label: 'Piece Detection Threshold',
              value: _pieceThreshold,
              min: 0.1,
              max: 0.5,
              divisions: 20,
              onChanged: (double value) {
                setState(() {
                  _pieceThreshold = value;
                });
              },
            ),

            // Board Color Distance Threshold
            _buildParameterSlider(
              label: 'Board Color Distance',
              value: _boardColorDistanceThreshold,
              min: 10.0,
              max: 50.0,
              divisions: 40,
              onChanged: (double value) {
                setState(() {
                  _boardColorDistanceThreshold = value;
                });
              },
            ),

            // Piece Color Match Threshold
            _buildParameterSlider(
              label: 'Piece Color Match Threshold',
              value: _pieceColorMatchThreshold,
              min: 10.0,
              max: 50.0,
              divisions: 40,
              onChanged: (double value) {
                setState(() {
                  _pieceColorMatchThreshold = value;
                });
              },
            ),

            // White Brightness Threshold
            _buildParameterSlider(
              label: 'White Brightness Threshold',
              value: _whiteBrightnessThreshold.toDouble(),
              min: 120.0,
              max: 220.0,
              divisions: 100,
              onChanged: (double value) {
                setState(() {
                  _whiteBrightnessThreshold = value.round();
                });
              },
            ),

            // Black Brightness Threshold
            _buildParameterSlider(
              label: 'Black Brightness Threshold',
              value: _blackBrightnessThreshold.toDouble(),
              min: 80.0,
              max: 180.0,
              divisions: 100,
              onChanged: (double value) {
                setState(() {
                  _blackBrightnessThreshold = value.round();
                });
              },
            ),

            // Black Saturation Threshold
            _buildParameterSlider(
              label: 'Black Saturation Threshold',
              value: _blackSaturationThreshold,
              min: 0.05,
              max: 0.5,
              divisions: 15,
              onChanged: (double value) {
                setState(() {
                  _blackSaturationThreshold = value;
                });
              },
            ),

            // Black Color Variance Threshold
            _buildParameterSlider(
              label: 'Black Color Variance',
              value: _blackColorVarianceThreshold.toDouble(),
              min: 10.0,
              max: 80.0,
              divisions: 35,
              onChanged: (double value) {
                setState(() {
                  _blackColorVarianceThreshold = value.round();
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Build a parameter slider with label and value
  Widget _buildParameterSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required Function(double) onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(top: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
              Text(value.toStringAsFixed(2)),
            ],
          ),
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
        const Divider(height: 8),
      ],
    );
  }

  /// Reprocess the image with the current parameter values
  void _reprocessWithCurrentParameters() {
    if (_lastImageBytes == null || _isProcessing) {
      return;
    }

    final math.Rectangle<int>? boardRect =
        BoardImageRecognitionService.lastDebugInfo.boardRect;

    if (boardRect != null) {
      _reprocessWithRect(
        boardRect,
        contrastEnhancementFactor: _contrastEnhancementFactor,
        pieceThreshold: _pieceThreshold,
        boardColorDistanceThreshold: _boardColorDistanceThreshold,
        pieceColorMatchThreshold: _pieceColorMatchThreshold,
        whiteBrightnessThreshold: _whiteBrightnessThreshold,
        blackBrightnessThreshold: _blackBrightnessThreshold,
        blackSaturationThreshold: _blackSaturationThreshold,
        blackColorVarianceThreshold: _blackColorVarianceThreshold,
      );
    } else {
      rootScaffoldMessengerKey.currentState?.showSnackBar(
        const SnackBar(
          content:
              Text("No board area detected yet. Please adjust area first."),
        ),
      );
    }
  }

  // --- Helper to build initial crop rect based on detected rect ---
  Rect? _buildInitialCropRect(Rect imageRect) {
    final math.Rectangle<int>? detectedRect =
        BoardImageRecognitionService.lastDebugInfo.boardRect;
    final int processedW = BoardImageRecognitionService.processedImageWidth;
    final int processedH = BoardImageRecognitionService.processedImageHeight;
    final int originalW = _originalImageWidth;
    final int originalH = _originalImageHeight;

    if (detectedRect == null ||
        processedW <= 0 ||
        processedH <= 0 ||
        originalW <= 0 ||
        originalH <= 0) {
      final double side = math.min(imageRect.width, imageRect.height) * 0.8;
      return Rect.fromCenter(
        center: imageRect.center,
        width: side,
        height: side,
      );
    }

    final double scaleX = originalW / processedW.toDouble();
    final double scaleY = originalH / processedH.toDouble();
    final double initialCropLeft = detectedRect.left * scaleX;
    final double initialCropTop = detectedRect.top * scaleY;
    final double initialCropWidth = detectedRect.width * scaleX;
    final double initialCropHeight = detectedRect.height * scaleY;
    final Rect initialRect = Rect.fromLTWH(
      initialCropLeft,
      initialCropTop,
      initialCropWidth,
      initialCropHeight,
    ).intersect(imageRect);
    logger.i("Initial crop rect (scaled from detected): $initialRect");
    final double side = math.min(initialRect.width, initialRect.height);
    return Rect.fromLTWH(initialRect.left, initialRect.top, side, side);
  }

  // --- Handler for confirming the crop ---
  Future<void> _confirmCrop() async {
    setState(() {
      _isAdjustingArea = false;
      _isProcessing = true;
      _statusMessage = 'Reprocessing with adjusted area...';
    });
    await Future<void>.delayed(const Duration(milliseconds: 50));

    try {
      // 1. Get the crop rectangle
      final Rect cropRect = _lastCropRect ?? const Rect.fromLTWH(0, 0, 10, 10);

      logger.i(
          "Crop confirmed. Crop Rect (relative to original image): $cropRect");

      // 2. Scale the crop rectangle down
      final int processedW = BoardImageRecognitionService.processedImageWidth;
      final int processedH = BoardImageRecognitionService.processedImageHeight;
      final int originalW = _originalImageWidth;
      final int originalH = _originalImageHeight;

      if (processedW <= 0 ||
          processedH <= 0 ||
          originalW <= 0 ||
          originalH <= 0) {
        throw Exception("Invalid image dimensions for scaling crop rectangle.");
      }

      final double invScaleX = processedW / originalW.toDouble();
      final double invScaleY = processedH / originalH.toDouble();
      final double scaledManualLeft = cropRect.left * invScaleX;
      final double scaledManualTop = cropRect.top * invScaleY;
      final double scaledManualWidth = cropRect.width * invScaleX;
      final double scaledManualHeight = cropRect.height * invScaleY;
      final math.Rectangle<int> scaledManualRect = math.Rectangle<int>(
        scaledManualLeft.round().clamp(0, processedW),
        scaledManualTop.round().clamp(0, processedH),
        scaledManualWidth
            .round()
            .clamp(1, processedW - scaledManualLeft.round()),
        scaledManualHeight
            .round()
            .clamp(1, processedH - scaledManualTop.round()),
      );
      logger.i("Scaled Manual Rect (for processing): $scaledManualRect");

      // 3. Call the reprocessing function with current parameters
      await _reprocessWithRect(
        scaledManualRect,
        contrastEnhancementFactor: _contrastEnhancementFactor,
        pieceThreshold: _pieceThreshold,
        boardColorDistanceThreshold: _boardColorDistanceThreshold,
        pieceColorMatchThreshold: _pieceColorMatchThreshold,
        whiteBrightnessThreshold: _whiteBrightnessThreshold,
        blackBrightnessThreshold: _blackBrightnessThreshold,
        blackSaturationThreshold: _blackSaturationThreshold,
        blackColorVarianceThreshold: _blackColorVarianceThreshold,
      );
    } catch (e, stacktrace) {
      logger.e("Error during reprocessing with adjusted area: $e\n$stacktrace");
      setState(() {
        _isProcessing = false;
        _statusMessage = 'Error reprocessing: $e';
      });
    }
  }

  // --- New function to reprocess the image with a specific rectangle and parameters ---
  Future<void> _reprocessWithRect(
    math.Rectangle<int> userRect, {
    double contrastEnhancementFactor = 1.8,
    double pieceThreshold = 0.25,
    double boardColorDistanceThreshold = 28.0,
    double pieceColorMatchThreshold = 30.0,
    int whiteBrightnessThreshold = 170,
    int blackBrightnessThreshold = 135,
    double blackSaturationThreshold = 0.25,
    int blackColorVarianceThreshold = 40,
  }) async {
    if (_lastImageBytes == null) {
      logger.w("Cannot reprocess, _lastImageBytes is null.");
      setState(() {
        _isProcessing = false;
        _statusMessage = 'Error: No image data available.';
      });
      return;
    }

    setState(() {
      _isProcessing = true;
      _statusMessage = 'Reprocessing with custom parameters...';
    });

    final img.Image? decodedImage = img.decodeImage(_lastImageBytes!);
    if (decodedImage == null) {
      logger.e("Failed to decode image for reprocessing");
      setState(() {
        _isProcessing = false;
        _statusMessage = 'Error decoding image.';
      });
      return;
    }
    _originalImageWidth = decodedImage.width;
    _originalImageHeight = decodedImage.height;

    // Log the custom parameters being used
    logger.i("Reprocessing with custom parameters:");
    logger.i("  contrast: $contrastEnhancementFactor");
    logger.i("  pieceThreshold: $pieceThreshold");
    logger.i("  boardColorDistance: $boardColorDistanceThreshold");
    logger.i("  pieceColorMatch: $pieceColorMatchThreshold");
    logger.i("  whiteBrightness: $whiteBrightnessThreshold");
    logger.i("  blackBrightness: $blackBrightnessThreshold");
    logger.i("  blackSaturation: $blackSaturationThreshold");
    logger.i("  blackColorVariance: $blackColorVarianceThreshold");

    // --- Call PUBLIC methods/access PUBLIC variables on BoardImageRecognitionService ---
    img.Image processImage =
        BoardImageRecognitionService.resizeForProcessing(decodedImage);
    final img.Image unprocessedImage = img.Image.from(processImage);

    // Use custom contrast enhancement factor
    processImage = BoardImageRecognitionService.enhanceImageForProcessing(
      processImage,
      contrastEnhancementFactor: contrastEnhancementFactor,
    );

    final ImageCharacteristics characteristics =
        BoardImageRecognitionService.analyzeImageCharacteristics(
      processImage,
      whiteBrightnessThresholdBase: whiteBrightnessThreshold,
      blackBrightnessThresholdBase: blackBrightnessThreshold,
      pieceThreshold: pieceThreshold,
    );

    // Assume lastDebugInfo is public static or has a public setter
    BoardRecognitionDebugInfo newDebugInfo =
        BoardImageRecognitionService.lastDebugInfo.copyWith(
      originalImage: img.Image.from(decodedImage),
      processedImage: img.Image.from(processImage),
      boardRect: userRect,
      characteristics: characteristics,
      boardPoints: <BoardPoint>[],
    );
    BoardImageRecognitionService.lastDebugInfo = newDebugInfo;

    final List<BoardPoint> boardPoints =
        BoardImageRecognitionService.createRefinedBoardPoints(
            processImage, userRect);
    // Assume lastDetectedPoints is public static or has a public setter
    BoardImageRecognitionService.lastDetectedPoints = boardPoints;
    newDebugInfo = newDebugInfo.copyWith(boardPoints: boardPoints);

    final Rgb boardColor = BoardImageRecognitionService.estimateBoardColor(
        unprocessedImage, userRect);
    newDebugInfo = newDebugInfo.copyWith(boardColor: boardColor);

    final ColorProfile colorProfile =
        BoardImageRecognitionService.buildColorProfile(
            unprocessedImage, boardPoints);
    newDebugInfo = newDebugInfo.copyWith(colorProfile: colorProfile);

    // Detect pieces with new parameters
    final Map<int, PieceColor> newResult = <int, PieceColor>{};
    final Color configuredWhiteColor = DB().colorSettings.whitePieceColor;
    final Color configuredBlackColor = DB().colorSettings.blackPieceColor;
    final Rgb configuredWhiteRgb =
        BoardImageRecognitionService.rgbFromColor(configuredWhiteColor);
    final Rgb configuredBlackRgb =
        BoardImageRecognitionService.rgbFromColor(configuredBlackColor);

    for (int i = 0; i < 24 && i < boardPoints.length; i++) {
      final BoardPoint point = boardPoints[i];
      final PieceColor detectedColor =
          BoardImageRecognitionService.detectPieceAtPoint(
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
        blackColorVarianceThreshold: blackColorVarianceThreshold,
      );
      newResult[i] = detectedColor;
    }

    final Map<int, PieceColor> enhancedResult =
        BoardImageRecognitionService.applyConsistencyRules(newResult);

    int whiteCount = 0, blackCount = 0;
    for (final PieceColor color in enhancedResult.values) {
      if (color == PieceColor.white) {
        whiteCount++;
      }
      if (color == PieceColor.black) {
        blackCount++;
      }
    }
    logger.i(
        "REPROCESSING COUNT white=$whiteCount, black=$blackCount (with custom parameters)");

    setState(() {
      _lastBoardPoints = boardPoints;
      _lastResult = enhancedResult;
      BoardImageRecognitionService.lastDebugInfo =
          newDebugInfo; // Update static again after all steps
      _isProcessing = false;
      _statusMessage = 'Reprocessing complete using custom parameters.';
    });
  }

  // Modify _processImage slightly to store original dimensions
  Future<void> _processImage(Uint8List bytes) async {
    setState(() {
      _isProcessing = true; // Added processing state
      _statusMessage = S.of(context).identifyingBoard;
    });

    // Store original image bytes
    _lastImageBytes = bytes;

    // --- Decode once to get original dimensions ---
    final img.Image? decoded = img.decodeImage(bytes);
    if (decoded != null) {
      _originalImageWidth = decoded.width;
      _originalImageHeight = decoded.height;
      logger.i(
          "Original image dimensions: ${_originalImageWidth}x$_originalImageHeight");
    } else {
      logger.w("Could not decode image to get original dimensions.");
      _originalImageWidth = 0; // Reset if decode fails
      _originalImageHeight = 0;
    }
    // --- End dimension storing ---

    try {
      final Map<int, PieceColor> result =
          await BoardImageRecognitionService.recognizeBoardFromImage(bytes);

      setState(() {
        // _lastImageBytes is already set
        _lastBoardPoints = BoardImageRecognitionService.lastDetectedPoints;
        _lastResult = result;
        _isProcessing = false; // Turn off processing indicator
        _statusMessage =
            'Recognition complete. Use the toolbar to review stages or adjust area.';
      });
    } catch (e, stacktrace) {
      // Added stacktrace
      logger.e("Identification failed: $e\n$stacktrace"); // Log stacktrace
      setState(() {
        _isProcessing = false; // Turn off processing indicator on error
        _statusMessage = 'Identification failed: $e';
      });
    }
  }

  // Widget _buildResultSummary()... (Keep as is)
  Widget _buildResultSummary() {
    // ... (implementation remains the same)
    int whiteCount = 0;
    int blackCount = 0;
    for (final PieceColor color in _lastResult.values) {
      if (color == PieceColor.white) {
        whiteCount++;
      } else if (color == PieceColor.black) {
        blackCount++;
      }
    }

    return Card(
      margin: const EdgeInsets.all(16.0),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'Recognition Result Statistics',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text('Number of White pieces: $whiteCount',
                style: const TextStyle(fontSize: 16)),
            Text('Number of Black pieces: $blackCount',
                style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 12),
            const Text(
              'Tip: Red circles represent black pieces, green circles represent white pieces',
              style: TextStyle(fontStyle: FontStyle.italic),
            ),

            // Add debug button for testing alternative setup methods
            const SizedBox(height: 20),
            const Text(
              'Debug Options',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: () => _testDirectSetup(_lastResult),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber,
              ),
              child: const Text('Test Direct Setup (Manual Board)'),
            ),
            const SizedBox(height: 8),
            const Text(
              'This button bypasses the FEN generation and directly sets up the board',
              style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
            ),
          ],
        ),
      ),
    );
  }

  // Future<void> _testDirectSetup... (Keep as is)
  Future<void> _testDirectSetup(Map<int, PieceColor> result) async {
    // ... (implementation remains the same)
    logger.i("---------------- TESTING DIRECT SETUP ----------------");
    logger.i("Setting up board directly, bypassing FEN generation");

    // First ensure we're in setup position mode
    GameController().gameInstance.gameMode = GameMode.setupPosition;

    // Reset the position
    GameController().position.reset();
    logger.i("Position reset completed");

    // Count pieces by color
    int whiteCount = 0;
    int blackCount = 0;
    for (final MapEntry<int, PieceColor> entry in result.entries) {
      if (entry.value == PieceColor.white) {
        whiteCount++;
      }
      if (entry.value == PieceColor.black) {
        blackCount++;
      }
    }

    // Log what we're about to do
    logger.i(
        "Placing $whiteCount white pieces and $blackCount black pieces directly");
    rootScaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text(
            "Manually placing $whiteCount white pieces and $blackCount black pieces"),
        duration: const Duration(seconds: 2),
      ),
    );

    // Set up the state first - prepare for placing white pieces
    GameController().position.phase = Phase.placing;
    GameController().position.sideToSetup = PieceColor.white;
    GameController().position.sideToMove = PieceColor.white;
    GameController().position.action = Act.place;

    // Define a method to place pieces
    Future<void> placePieces(PieceColor color) async {
      GameController().position.sideToSetup = color;
      GameController().position.sideToMove = color;
      GameController().position.action = Act.place;

      // Place all pieces of this color
      for (final MapEntry<int, PieceColor> entry in result.entries) {
        if (entry.value == color) {
          logger.i("Placing $color piece at square ${entry.key}");
          GameController().position.putPieceForSetupPosition(entry.key);
          // Small delay for processing
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      }
    }

    // Place white pieces
    await placePieces(PieceColor.white);
    logger.i("White pieces placed");

    // Place black pieces
    await placePieces(PieceColor.black);
    logger.i("Black pieces placed");

    // Update counts
    final int piecesCount = DB().ruleSettings.piecesCount;
    GameController().position.pieceOnBoardCount[PieceColor.white] = whiteCount;
    GameController().position.pieceOnBoardCount[PieceColor.black] = blackCount;
    GameController().position.pieceInHandCount[PieceColor.white] =
        piecesCount - whiteCount;
    GameController().position.pieceInHandCount[PieceColor.black] =
        piecesCount - blackCount;

    // Determine game phase
    if (whiteCount < piecesCount || blackCount < piecesCount) {
      GameController().position.phase = Phase.placing;
    } else {
      GameController().position.phase = Phase.moving;
    }

    // Determine whose turn it is
    if (whiteCount > blackCount) {
      GameController().position.sideToMove = PieceColor.black;
    } else {
      GameController().position.sideToMove = PieceColor.white;
    }

    // Update FEN and recorder
    final String? fen = GameController().position.fen;
    if (fen != null) {
      logger.i("Generated FEN after direct setup: $fen");
      GameController().gameRecorder =
          GameRecorder(lastPositionWithRemove: fen, setupPosition: fen);
    } else {
      logger.e("Failed to generate FEN after direct setup");
    }

    // Update UI
    GameController().setupPositionNotifier.updateIcons();
    GameController().boardSemanticsNotifier.updateSemantics();
    GameController().headerIconsNotifier.showIcons();

    logger.i("Direct setup completed");

    // Show success message
    rootScaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text("Direct board setup completed"),
            if (fen != null)
              SelectableText("FEN: $fen",
                  style:
                      const TextStyle(fontFamily: 'monospace', fontSize: 10)),
            Text("Pieces on board: White=$whiteCount, Black=$blackCount"),
          ],
        ),
        duration: const Duration(seconds: 10),
      ),
    );
  }

  // Future<void> _pickAndRecognizeImage... (Keep as is)
  Future<void> _pickAndRecognizeImage() async {
    if (_isProcessing) {
      return;
    }

    setState(() {
      _isProcessing = true;
      _statusMessage = S.of(context).selectingImageFromAlbum;
    });

    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(source: ImageSource.gallery);
      if (image == null) {
        setState(() {
          _isProcessing = false;
          _statusMessage = S.of(context).noImageSelected;
        });
        return;
      }

      await _processImage(await image.readAsBytes());
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _statusMessage = 'Image selection failed: $e';
      });
    }
  }

  // Future<void> _captureAndRecognizeImage... (Keep as is)
  Future<void> _captureAndRecognizeImage() async {
    if (_isProcessing) {
      return;
    }

    setState(() {
      _isProcessing = true;
      _statusMessage = S.of(context).takingPicture;
    });

    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(source: ImageSource.camera);
      if (image == null) {
        setState(() {
          _isProcessing = false;
          _statusMessage = 'No pictures taken';
        });
        return;
      }

      await _processImage(await image.readAsBytes());
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _statusMessage = 'Image capture failed: $e';
      });
    }
  }

  // Add _showRecognitionResultDialog method between other methods
  /// Shows a dialog for recognition result with cropping capability.
  ///
  /// TODO: This method is currently not used but kept for future implementation
  /// of enhanced recognition result visualization with cropping capability.
  /// It can replace the current static dialog approach with interactive cropping.
  Future<void> _showRecognitionResultDialog() async {
    if (_lastImageBytes == null || _lastBoardPoints.isEmpty) {
      return;
    }

    // Create a copy of the image bytes for safety
    final Uint8List originalBytes = Uint8List.fromList(_lastImageBytes!);

    // Create a temporary image to display in the dialog
    final img.Image? decoded = img.decodeImage(originalBytes);
    if (decoded == null) {
      logger.e("Could not decode image for crop dialog.");
      return;
    }

    // Determine the board area from the detected points
    final int minX =
        _lastBoardPoints.map((BoardPoint p) => p.x).reduce(math.min);
    final int minY =
        _lastBoardPoints.map((BoardPoint p) => p.y).reduce(math.min);
    final int maxX =
        _lastBoardPoints.map((BoardPoint p) => p.x).reduce(math.max);
    final int maxY =
        _lastBoardPoints.map((BoardPoint p) => p.y).reduce(math.max);

    // Add padding to ensure we capture the entire board
    final int paddingX = ((maxX - minX) * 0.05).round();
    final int paddingY = ((maxY - minY) * 0.05).round();

    final int cropLeft = (minX - paddingX).clamp(0, decoded.width - 1);
    final int cropTop = (minY - paddingY).clamp(0, decoded.height - 1);
    final int cropRight = (maxX + paddingX).clamp(cropLeft + 1, decoded.width);
    final int cropBottom = (maxY + paddingY).clamp(cropTop + 1, decoded.height);

    final int cropWidth = cropRight - cropLeft;
    final int cropHeight = cropBottom - cropTop;

    // Update crop controller with aspect ratio based on detected points
    // For square boards, we use 1.0 as the aspect ratio
    _cropController.aspectRatio = 1.0;

    // Use initialRectBuilder to set the initial crop rectangle
    final InitialRectBuilder initialRect = InitialRectBuilder.withArea(
      ImageBasedRect.fromLTWH(
        cropLeft.toDouble(),
        cropTop.toDouble(),
        cropWidth.toDouble(),
        cropHeight.toDouble(),
      ),
    );

    // Show dialog with cropping UI
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(S.of(context).adjustBoardArea),
          content: Container(
            width: double.maxFinite,
            height: 400,
            decoration: BoxDecoration(
              color: Colors.black,
              border: Border.all(color: Colors.white30),
            ),
            child: Crop(
              image: originalBytes,
              controller: _cropController,
              // Use initialRectBuilder instead of initialCropRect
              initialRectBuilder: initialRect,
              maskColor: Colors.black.withValues(alpha: 0.6),
              onCropped: (CropResult result) {
                // This callback won't be used as we're using the crop button
                // to trigger cropping manually
              },
              onStatusChanged: (CropStatus status) {
                if (status == CropStatus.ready) {
                  logger.d("Crop widget is ready");
                }
              },
              // Fixed onMoved callback signature - takes ViewportBasedRect parameter
              onMoved:
                  (ViewportBasedRect viewportRect, ImageBasedRect imageRect) {
                logger.d("Crop rect moved: $viewportRect");
              },
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text('Confirm'),
              onPressed: () {
                // Call the crop() method and then get the result from the onCropped callback
                _cropController.crop();
                Navigator.of(context).pop();
                // Process the cropped image separately, outside this dialog
              },
            ),
          ],
        );
      },
    );
  }
} // End of _BoardRecognitionDebugPageState
