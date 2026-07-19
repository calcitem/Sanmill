// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// gif_share.dart

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../experience_recording/services/diagnostic_reproduction_service.dart';
import '../../../shared/database/database.dart';
import '../../widgets/mini_board.dart';
import '../mill.dart';

/// GIF export is currently validated only on Android. Keep iOS disabled until
/// the historical capture/share issue is verified on device.
bool get supportsGifSharing => !kIsWeb && Platform.isAndroid;

/// Creates a compact board replay when the user asks to share it.
///
/// Earlier versions continuously captured the complete game screen after each
/// action. Besides consuming memory and render time during play, that path was
/// easy to break when the game-page widget tree changed. Rebuilding frames from
/// the recorder's board layouts keeps normal play free of GIF work and produces
/// the same crisp output on every device.
class GifShare {
  factory GifShare() => _instance ?? GifShare._internal();

  GifShare._internal() {
    _instance = this;
  }

  static GifShare? _instance;

  @visibleForTesting
  static const int imageSize = 540;

  @visibleForTesting
  static const int maximumFrameCount = 180;

  /// Netscape GIF loop count `0` means repeat indefinitely, which is the
  /// conventional behavior for a shared animated GIF.
  @visibleForTesting
  static const int loopCount = 0;

  static const int _frameDelayHundredths = 80;
  static const String _emptyBoardLayout = '********/********/********';

  Future<bool> shareGame({
    required List<ExtMove> moves,
    required bool hasDiagonalLines,
    String? initialFen,
  }) async {
    DiagnosticReplayGuard.requireAllowed('GIF capture and sharing');
    if (!supportsGifSharing) {
      return false;
    }

    final Uint8List? gif = await encodeGame(
      moves: moves,
      initialFen: initialFen,
      hasDiagonalLines: hasDiagonalLines,
    );
    if (gif == null) {
      return false;
    }
    return _writeGifToFile(gif);
  }

  @visibleForTesting
  Future<Uint8List?> encodeGame({
    required List<ExtMove> moves,
    required bool hasDiagonalLines,
    String? initialFen,
  }) async {
    final List<_GifBoardFrame> frames = _buildFrames(
      moves,
      initialFen: initialFen,
    );
    if (frames.isEmpty) {
      return null;
    }

    final List<int> frameIndices = sampledFrameIndices(frames.length);
    final img.GifEncoder encoder = img.GifEncoder(
      delay: _frameDelayHundredths,
      repeat: loopCount,
      numColors: 128,
      quantizerType: img.QuantizerType.octree,
      dither: img.DitherKernel.none,
    );

    for (final int index in frameIndices) {
      final img.Image frame = await _renderFrame(
        frames[index],
        hasDiagonalLines: hasDiagonalLines,
      );
      encoder.addFrame(frame);

      // Let progress indicators and platform events update between frames.
      await Future<void>.delayed(Duration.zero);
    }

    return encoder.finish();
  }

  @visibleForTesting
  static List<int> sampledFrameIndices(int frameCount) {
    assert(frameCount >= 0, 'Frame count cannot be negative.');
    if (frameCount <= maximumFrameCount) {
      return List<int>.generate(frameCount, (int index) => index);
    }

    return List<int>.generate(maximumFrameCount, (int index) {
      return (index * (frameCount - 1) / (maximumFrameCount - 1)).round();
    });
  }

  static List<_GifBoardFrame> _buildFrames(
    List<ExtMove> moves, {
    String? initialFen,
  }) {
    final String initialLayout = _boardLayoutFromFen(initialFen);
    final List<_GifBoardFrame> frames = <_GifBoardFrame>[
      _GifBoardFrame(boardLayout: initialLayout),
    ];
    for (final ExtMove move in moves) {
      final String? boardLayout = move.boardLayout;
      if (_isBoardLayout(boardLayout)) {
        frames.add(_GifBoardFrame(boardLayout: boardLayout!, move: move));
      }
    }
    return frames;
  }

  static String _boardLayoutFromFen(String? fen) {
    if (fen == null || fen.trim().isEmpty) {
      return _emptyBoardLayout;
    }
    final String board = fen.trim().split(RegExp(r'\s+')).first;
    return _isBoardLayout(board) ? board : _emptyBoardLayout;
  }

  static bool _isBoardLayout(String? boardLayout) {
    if (boardLayout == null || boardLayout.length != 26) {
      return false;
    }
    final List<String> rings = boardLayout.split('/');
    return rings.length == 3 && rings.every((String ring) => ring.length == 8);
  }

  static Future<img.Image> _renderFrame(
    _GifBoardFrame frame, {
    required bool hasDiagonalLines,
  }) async {
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, imageSize.toDouble(), imageSize.toDouble()),
      Paint()..color = DB().colorSettings.boardBackgroundColor,
    );
    MiniBoardPainter(
      boardLayout: frame.boardLayout,
      extMove: frame.move,
      hasDiagonalLines: hasDiagonalLines,
    ).paint(canvas, Size.square(imageSize.toDouble()));

    final ui.Picture picture = recorder.endRecording();
    final ui.Image rendered = await picture.toImage(imageSize, imageSize);
    picture.dispose();
    final ByteData? byteData = await rendered.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    rendered.dispose();
    assert(byteData != null, 'Rendered GIF frame must expose RGBA bytes.');
    if (byteData == null) {
      throw StateError('Could not read the rendered GIF frame.');
    }

    return img.Image.fromBytes(
      width: imageSize,
      height: imageSize,
      bytes: byteData.buffer,
      bytesOffset: byteData.offsetInBytes,
      order: img.ChannelOrder.rgba,
    );
  }

  static Future<bool> _writeGifToFile(List<int> gif) async {
    final String time = DateTime.now().millisecondsSinceEpoch.toString();
    final String gifFileName = 'Mill-$time.gif';
    final Directory docDir = await getApplicationDocumentsDirectory();
    final File gifFile = File('${docDir.path}/$gifFileName');
    await gifFile.writeAsBytes(gif);
    await SharePlus.instance.share(
      ShareParams(files: <XFile>[XFile(gifFile.path)]),
    );
    return true;
  }
}

class _GifBoardFrame {
  const _GifBoardFrame({required this.boardLayout, this.move});

  final String boardLayout;
  final ExtMove? move;
}
