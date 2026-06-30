// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// board_recognition_debug_page.dart
//
// Dev-mode preview dialog for the board image recognition feature.
//
// The recognition pipeline ([BoardImageRecognitionService]) produces a
// `Map<int, PieceColor>` describing the detected board.  In development
// builds we surface that result, the per-stage debug imagery
// ([BoardRecognitionDebugView]) and the generated FEN before the user
// decides whether to load it into the Setup Position editor.
//
// The legacy standalone tuning page (crop / manual point adjustment) was
// intentionally not ported: it mutated the deleted Dart `Position`
// directly and was never wired to a route.  Applying a recognised board
// now goes through the native setup session via [BoardRecognitionImport].

// ignore_for_file: avoid_classes_with_only_static_members

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../generated/intl/l10n.dart';
import '../../shared/widgets/snackbars/scaffold_messenger.dart';
import '../services/board_image_recognition.dart';
import '../services/mill.dart';
import '../widgets/board_recognition_debug_view.dart';

/// Static factory for the recognition-result preview dialog.
///
/// Kept as a thin builder so the orchestration (image picking, applying
/// the result) lives in [BoardRecognitionImport] and the visualization
/// lives in [BoardRecognitionDebugView]; this class only assembles them.
abstract final class BoardRecognitionDebugPage {
  /// Builds the recognition-result preview dialog content.
  ///
  /// [onResult] is invoked with `true` when the user accepts the result
  /// (apply to the board) and `false` when they cancel.  The caller owns
  /// dismissing the surrounding dialog route inside [onResult].
  static Widget createRecognitionResultDialog({
    required Uint8List imageBytes,
    required Map<int, PieceColor> result,
    required List<BoardPoint> boardPoints,
    required int processedWidth,
    required int processedHeight,
    required ValueChanged<bool> onResult,
    required BuildContext context,
    BoardRecognitionDebugInfo? debugInfo,
  }) {
    int whiteCount = 0;
    int blackCount = 0;
    for (final PieceColor color in result.values) {
      if (color == PieceColor.white) {
        whiteCount++;
      } else if (color == PieceColor.black) {
        blackCount++;
      }
    }

    final String? fen = BoardRecognitionDebugView.generateTempFenString(result);

    return AlertDialog(
      title: Text(S.of(context).identificationResults),
      contentPadding: const EdgeInsets.fromLTRB(8, 20, 8, 24),
      content: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 300, maxWidth: 800),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
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
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
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
                    Expanded(
                      child: Column(
                        children: <Widget>[
                          const Icon(Icons.circle, color: Colors.red, size: 24),
                          Text("${S.of(context).blackPiece}: $blackCount"),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (fen != null) ...<Widget>[
                const SizedBox(height: 16),
                _FenPreviewCard(fen: fen),
              ],
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => onResult(false),
          child: Text(S.of(context).cancel),
        ),
        if (fen != null)
          TextButton.icon(
            onPressed: () => _copyFen(context, fen),
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

  static Future<void> _copyFen(BuildContext context, String fen) async {
    final String copiedMsg = S.of(context).fenCopiedToClipboard;
    await Clipboard.setData(ClipboardData(text: fen));
    rootScaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(content: Text(copiedMsg), duration: const Duration(seconds: 2)),
    );
  }
}

/// Read-only card showing the generated FEN with a copy affordance.
class _FenPreviewCard extends StatelessWidget {
  const _FenPreviewCard({required this.fen});

  final String fen;

  @override
  Widget build(BuildContext context) {
    return Container(
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
              ElevatedButton.icon(
                onPressed: () =>
                    BoardRecognitionDebugPage._copyFen(context, fen),
                icon: const Icon(Icons.copy),
                label: const Text('Copy'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  minimumSize: const Size(0, 36),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SelectableText(
            fen,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ],
      ),
    );
  }
}
