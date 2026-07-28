// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/material.dart';

/// The outcome of work performed while the recognition progress page is shown.
class BoardRecognitionProgressResult<T> {
  const BoardRecognitionProgressResult.success(this.value)
    : error = null,
      stackTrace = null;

  const BoardRecognitionProgressResult.failure(this.error, this.stackTrace)
    : value = null;

  final T? value;
  final Object? error;
  final StackTrace? stackTrace;

  bool get isSuccess => error == null;
}

/// Shows an opaque progress page and starts [task] after its first frame.
Future<BoardRecognitionProgressResult<T>?> showBoardRecognitionProgress<T>({
  required BuildContext context,
  required String message,
  required Future<T> Function() task,
}) => Navigator.of(context, rootNavigator: true)
    .push<BoardRecognitionProgressResult<T>>(
      PageRouteBuilder<BoardRecognitionProgressResult<T>>(
        opaque: true,
        barrierColor: null,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder:
            (BuildContext _, Animation<double> _, Animation<double> _) =>
                BoardRecognitionProgressPage<T>(message: message, task: task),
      ),
    );

/// Keeps expensive recognition work behind a responsive, opaque surface.
class BoardRecognitionProgressPage<T> extends StatefulWidget {
  const BoardRecognitionProgressPage({
    super.key,
    required this.message,
    required this.task,
  });

  final String message;
  final Future<T> Function() task;

  @override
  State<BoardRecognitionProgressPage<T>> createState() =>
      _BoardRecognitionProgressPageState<T>();
}

class _BoardRecognitionProgressPageState<T>
    extends State<BoardRecognitionProgressPage<T>> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      _runTask();
    });
  }

  Future<void> _runTask() async {
    late BoardRecognitionProgressResult<T> result;
    try {
      result = BoardRecognitionProgressResult<T>.success(await widget.task());
    } catch (error, stackTrace) {
      result = BoardRecognitionProgressResult<T>.failure(error, stackTrace);
    }
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    child: Scaffold(
      key: const Key('board_recognition_progress_page'),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Semantics(
              excludeSemantics: true,
              liveRegion: true,
              label: widget.message,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const CircularProgressIndicator(),
                  const SizedBox(height: 24),
                  Text(
                    widget.message,
                    key: const Key('board_recognition_progress_message'),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
