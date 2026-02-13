// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// tutorial_dialog.dart

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../../game_page/services/mill.dart';
import '../../game_page/services/painters/painters.dart';
import '../../general_settings/models/general_settings.dart';
import '../../generated/intl/l10n.dart';
import '../../shared/database/database.dart';
import '../../shared/themes/app_theme.dart';
import '../painters/tutorial_mask_painter.dart';
import 'tutorial_board.dart';

class TutorialDialog extends StatefulWidget {
  const TutorialDialog({super.key});

  @override
  State<TutorialDialog> createState() => _TutorialDialogState();
}

class _TutorialDialogState extends State<TutorialDialog> {
  static const int _maxIndex = 6;
  static const int _placingPhaseStep = 1;
  static const int _counterStep = 2;
  static const int _movingPhaseStep = 3;
  static const int _millStep = 4;
  static const int _flyingStep = 5;

  int _curIndex = 0;
  int? _focusIndex;
  int? _blurIndex;
  Offset? _maskOffset;
  Orientation? _orientation;
  List<PieceColor> _pieceList = List<PieceColor>.filled(7 * 7, PieceColor.none);

  bool get isFinally => _curIndex == _maxIndex;
  bool get isStart => _curIndex == 0;
  bool get _isLandscape => _orientation == Orientation.landscape;

  Size get _boardSize => _isLandscape
      ? Size(landscapeBoardWidth, landscapeBoardWidth)
      : Size(
          deviceWidth(context) - AppTheme.boardPadding * 2,
          deviceWidth(context) - AppTheme.boardPadding * 2,
        );

  double get landscapeBoardWidth => deviceWidth(context) * 0.6;

  double get pieceWidth =>
      _boardSize.width * DB().displaySettings.pieceWidth / 7;

  @override
  void initState() {
    super.initState();
    _pieceList[_boardIndex(3, 1)] = PieceColor.black;
    _pieceList[_boardIndex(3, 5)] = PieceColor.white;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      key: const Key('pop_scope'),
      canPop: false,
      onPopInvokedWithResult: (bool didPop, dynamic result) async {
        if (didPop) {
          return;
        }
        prevStep();
        return;
      },
      child: OrientationBuilder(
        key: const Key('orientation_builder'),
        builder: _buildForOrientation,
      ),
    );
  }

  Widget _buildForOrientation(BuildContext context, Orientation orientation) {
    if (_orientation != orientation) {
      _orientation = orientation;
      _applyStepBoardState();
    }
    return Scaffold(
      key: const Key('scaffold'),
      backgroundColor: DB().colorSettings.darkBackgroundColor,
      body: _isLandscape ? _buildLandscapeLayout() : _buildPortraitLayout(),
    );
  }

  Widget _buildLandscapeLayout() {
    return SafeArea(
      key: const Key('landscape_safe_area'),
      child: Stack(
        key: const Key('stack_landscape'),
        children: <Widget>[
          Align(
            child: SizedBox(
              width: landscapeBoardWidth,
              height: landscapeBoardWidth,
              child: _buildBoard(const Key('tutorial_board_landscape')),
            ),
          ),
          _buildMask(const Key('custom_paint_landscape')),
          Column(
            key: const Key('column_landscape'),
            children: <Widget>[
              _buildNavigationBar(
                previousButtonKey: const Key('landscape_previous_button'),
                finishButtonKey: const Key('landscape_skip_button'),
                nextButtonKey: const Key('landscape_next_button'),
              ),
              Expanded(
                child: _buildInteractiveStepArea(
                  gestureDetectorKey: const Key('gesture_detector_landscape'),
                  switcherKey: const Key('animated_switcher_landscape'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPortraitLayout() {
    return Stack(
      key: const Key('stack_portrait'),
      children: <Widget>[
        SafeArea(
          key: const Key('portrait_safe_area'),
          child: Padding(
            padding: EdgeInsets.only(
              left: AppTheme.boardPadding,
              right: AppTheme.boardPadding,
              top: kToolbarHeight + AppTheme.boardPadding,
            ),
            child: _buildBoard(const Key('tutorial_board_portrait')),
          ),
        ),
        _buildMask(const Key('custom_paint_portrait')),
        SafeArea(
          child: Column(
            key: const Key('column_portrait'),
            children: <Widget>[
              _buildNavigationBar(
                previousButtonKey: const Key('portrait_previous_button'),
                finishButtonKey: const Key('portrait_finish_button'),
                nextButtonKey: const Key('portrait_next_button'),
              ),
              Expanded(
                child: _buildInteractiveStepArea(
                  gestureDetectorKey: const Key('gesture_detector_portrait'),
                  switcherKey: const Key('animated_switcher_portrait'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBoard(Key key) {
    return TutorialBoard(
      key: key,
      focusIndex: _focusIndex,
      blurIndex: _blurIndex,
      pieceList: _pieceList,
    );
  }

  Widget _buildMask(Key key) {
    return CustomPaint(
      key: key,
      painter: TutorialMaskPainter(
        maskOffset: _maskOffset,
        maskRadius: pieceWidth * 1.5,
      ),
    );
  }

  Widget _buildNavigationBar({
    required Key previousButtonKey,
    required Key finishButtonKey,
    required Key nextButtonKey,
  }) {
    return Container(
      height: kToolbarHeight,
      color: Colors.white,
      child: Row(
        children: <Widget>[
          Semantics(
            label: S.of(context).previous,
            child: IconButton(
              key: previousButtonKey,
              onPressed: isStart ? null : prevStep,
              icon: Icon(
                Icons.arrow_back,
                color: isStart ? Colors.grey : Colors.black,
              ),
            ),
          ),
          const Spacer(),
          IconButton(
            key: finishButtonKey,
            tooltip: isFinally ? S.of(context).gotIt : S.of(context).skip,
            onPressed: () => _finishTutorial(context),
            icon: isFinally
                ? const Icon(Icons.done_outline, color: Colors.black)
                : const Icon(
                    FluentIcons.arrow_exit_20_regular,
                    color: Colors.black,
                  ),
          ),
          const Spacer(),
          Semantics(
            label: S.of(context).next,
            child: IconButton(
              key: nextButtonKey,
              onPressed: isFinally ? null : nextStep,
              icon: Icon(
                Icons.arrow_forward_rounded,
                color: isFinally ? Colors.grey : Colors.black,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInteractiveStepArea({
    required Key gestureDetectorKey,
    required Key switcherKey,
  }) {
    return GestureDetector(
      key: gestureDetectorKey,
      onTap: () {
        if (isFinally) {
          _finishTutorial(context);
        } else {
          nextStep();
        }
      },
      behavior: HitTestBehavior.opaque,
      child: AnimatedSwitcher(
        key: switcherKey,
        duration: const Duration(milliseconds: 400),
        child: _buildCurrentStep(),
      ),
    );
  }

  void _finishTutorial(BuildContext context) {
    Navigator.of(context).pop();
    DB().generalSettings = DB().generalSettings.copyWith(showTutorial: false);
  }

  void prevStep() => _changeStep(-1);

  void nextStep() => _changeStep(1);

  void _changeStep(int delta) {
    final int newIndex = _curIndex + delta;
    if (newIndex < 0 || newIndex > _maxIndex) {
      return;
    }
    setState(() {
      _curIndex = newIndex;
      _applyStepBoardState();
    });
  }

  Widget _buildCurrentStep() {
    switch (_curIndex) {
      case 0:
        return const _Step1(key: ValueKey<String>('Step1'));
      case _placingPhaseStep:
        return const _Step2(key: ValueKey<String>('Step2'));
      case _counterStep:
        return const _Step3(key: ValueKey<String>('Step3'));
      case _movingPhaseStep:
        return _Step4(
          key: const ValueKey<String>('Step4'),
          begin: _pieceAnimationOffset(5, 3),
          end: _pieceAnimationOffset(4, 3),
          onEnd: _handleAnimatedMoveEnd,
        );
      case _millStep:
        return const _Step5(key: ValueKey<String>('Step5'));
      case _flyingStep:
        return _Step6(
          key: const ValueKey<String>('Step6'),
          begin: _pieceAnimationOffset(3, 2),
          end: _pieceAnimationOffset(4, 3),
          onEnd: _handleAnimatedMoveEnd,
        );
      case _maxIndex:
        return const _Step7(key: ValueKey<String>('Step7'));
      default:
        return const SizedBox.shrink();
    }
  }

  /// Updates board decorations and pieces for the current tutorial step.
  void _applyStepBoardState() {
    _resetBoardState();
    switch (_curIndex) {
      case _placingPhaseStep:
        _configurePlacingPhase();
        break;
      case _counterStep:
        _setMaskAt(3, 3);
        break;
      case _movingPhaseStep:
        _configureMovingPhase();
        break;
      case _millStep:
        _configureMillStep();
        break;
      case _flyingStep:
        _configureFlyingStep();
        break;
    }
  }

  void _configurePlacingPhase() {
    _setMaskAt(3, 5);
    _placePiece(3, 5, PieceColor.white);
  }

  void _configureMovingPhase() {
    _setMaskAt(5, 3);
    _placePiece(4, 2, PieceColor.white);
    _placePiece(4, 4, PieceColor.white);
    _placePiece(2, 4, PieceColor.black);
    _placePiece(2, 3, PieceColor.black);
    _placePiece(3, 4, PieceColor.black);
    _placePiece(5, 3, PieceColor.white);
  }

  void _configureMillStep() {
    _setMaskAt(5, 3);
    _placePiece(4, 2, PieceColor.white);
    _placePiece(4, 3, PieceColor.white);
    _placePiece(4, 4, PieceColor.white);
    _placePiece(5, 1, PieceColor.black);
    _placePiece(5, 3, PieceColor.black);
    _placePiece(5, 5, PieceColor.black);
    _focusIndex = _boardIndex(5, 3);
  }

  void _configureFlyingStep() {
    _setMaskAt(4, 2);
    _placePiece(3, 2, PieceColor.white);
    _placePiece(4, 2, PieceColor.white);
    _placePiece(4, 4, PieceColor.white);
    _placePiece(5, 1, PieceColor.black);
    _placePiece(5, 3, PieceColor.black);
    _placePiece(5, 5, PieceColor.black);
    _placePiece(6, 3, PieceColor.black);
  }

  void _setMaskAt(int row, int col) {
    _maskOffset = _maskOffsetFor(row, col);
  }

  /// Applies piece movements after an animation completes.
  void _handleAnimatedMoveEnd() {
    switch (_curIndex) {
      case _counterStep:
      case _movingPhaseStep:
        _clearPiece(5, 3);
        _placePiece(4, 3, PieceColor.white);
        break;
      case _flyingStep:
        _clearPiece(3, 2);
        _placePiece(4, 3, PieceColor.white);
        break;
      default:
        return;
    }
    setState(() {});
  }

  void _resetBoardState() {
    _pieceList = List<PieceColor>.filled(7 * 7, PieceColor.none);
    _maskOffset = null;
    _focusIndex = null;
    _blurIndex = null;
  }

  int _boardIndex(int row, int col) => row * 7 + col;

  void _placePiece(int row, int col, PieceColor color) {
    _pieceList[_boardIndex(row, col)] = color;
  }

  void _clearPiece(int row, int col) {
    _pieceList[_boardIndex(row, col)] = PieceColor.none;
  }

  Offset _maskOffsetFor(int row, int col) {
    final int index = _boardIndex(row, col);
    return _isLandscape
        ? pointFromIndex(index, _boardSize) +
              Offset(
                (MediaQuery.of(context).size.width -
                        MediaQuery.of(context).padding.horizontal -
                        landscapeBoardWidth) /
                    2,
                (MediaQuery.of(context).size.height -
                        landscapeBoardWidth -
                        MediaQuery.of(context).padding.vertical) /
                    2,
              )
        : pointFromIndex(index, _boardSize) +
              Offset(
                AppTheme.boardPadding,
                AppTheme.boardPadding +
                    kToolbarHeight +
                    MediaQuery.of(context).padding.top,
              );
  }

  Offset _pieceAnimationOffset(int row, int col) {
    final int index = _boardIndex(row, col);
    return _isLandscape
        ? pointFromIndex(index, _boardSize) +
              Offset(
                (MediaQuery.of(context).size.width -
                        MediaQuery.of(context).padding.horizontal -
                        landscapeBoardWidth) /
                    2,
                (MediaQuery.of(context).size.height -
                            landscapeBoardWidth -
                            MediaQuery.of(context).padding.vertical) /
                        2 -
                    kToolbarHeight -
                    MediaQuery.of(context).padding.top,
              )
        : pointFromIndex(index, _boardSize) +
              Offset(AppTheme.boardPadding, AppTheme.boardPadding);
  }
}

class _Step1 extends StatelessWidget {
  const _Step1({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        Positioned(
          left: 32,
          bottom: 128,
          width: 320,
          child: Text(
            "${S.of(context).appName}\n${S.of(context).howToPlay}",
            maxLines: 4,
            style: TextStyle(
              color: Colors.white,
              fontSize: AppTheme.textScaler.scale(32.0),
            ),
          ),
        ),
      ],
    );
  }
}

class _Step2 extends StatelessWidget {
  const _Step2({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(left: 16, top: 16),
      width: double.maxFinite,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            "${S.of(context).placingPhase}\n${S.of(context).toPlacePiece}",
            style: TextStyle(
              fontSize: AppTheme.textScaler.scale(16),
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _Step3 extends StatelessWidget {
  const _Step3({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        Positioned(
          left: 32,
          top: 32,
          width: 320,
          child: Text(
            S.of(context).isPieceCountInHandShown,
            maxLines: 4,
            style: TextStyle(
              fontSize: AppTheme.textScaler.scale(16),
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }
}

class _Step4 extends StatefulWidget {
  const _Step4({
    super.key,
    required this.begin,
    required this.end,
    required this.onEnd,
  });

  final Offset begin;
  final Offset end;
  final VoidCallback onEnd;

  @override
  State<_Step4> createState() => _Step4State();
}

class _Step4State extends State<_Step4> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late Animation<Offset> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _animation = Tween<Offset>(
      begin: widget.begin,
      end: widget.end,
    ).animate(_controller);
    _controller.forward();
    _animation.addStatusListener(_statusListener);
  }

  @override
  void dispose() {
    _animation.removeStatusListener(_statusListener);
    _controller.dispose();
    super.dispose();
  }

  void _statusListener(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      widget.onEnd.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        Align(
          alignment: Alignment.topLeft,
          child: AnimatedBuilder(
            animation: _animation,
            builder: (BuildContext context, Widget? child) {
              return Visibility(
                visible: !_animation.isCompleted,
                child: Transform.translate(
                  offset: _animation.value,
                  child: child,
                ),
              );
            },
            child: IconButton(
              icon: const Icon(
                FluentIcons.arrow_circle_up_24_regular,
                color: Colors.red,
              ),
              tooltip: S.of(context).movePieceUp,
              onPressed: () {},
            ),
          ),
        ),
        Positioned(
          left: 32,
          top: 32,
          width: 320,
          child: Text(
            "${S.of(context).movingPhase}\n${S.of(context).toSelectPiece}\n${S.of(context).toMovePiece}",
            maxLines: 4,
            style: TextStyle(
              fontSize: AppTheme.textScaler.scale(16),
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }
}

class _Step5 extends StatelessWidget {
  const _Step5({super.key});

  @override
  Widget build(BuildContext context) {
    String text =
        "${S.of(context).needToCreateMillFirst}\n${S.of(context).tipCannotRemovePieceFromMill}";
    if (text[text.length - 1] != ".") {
      text = "$text!";
    }

    return Stack(
      children: <Widget>[
        Positioned(
          left: 32,
          top: 32,
          width: 320,
          child: Text(
            text,
            maxLines: 4,
            style: TextStyle(
              fontSize: AppTheme.textScaler.scale(16),
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }
}

class _Step6 extends StatefulWidget {
  const _Step6({
    super.key,
    required this.begin,
    required this.end,
    required this.onEnd,
  });

  final Offset begin;
  final Offset end;
  final VoidCallback onEnd;

  @override
  State<_Step6> createState() => _Step6State();
}

class _Step6State extends State<_Step6> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late Animation<Offset> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _animation = Tween<Offset>(
      begin: widget.begin,
      end: widget.end,
    ).animate(_controller);
    _controller.forward();
    _animation.addStatusListener(_statusListener);
  }

  @override
  void dispose() {
    _animation.removeStatusListener(_statusListener);
    _controller.dispose();
    super.dispose();
  }

  void _statusListener(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      widget.onEnd.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        Align(
          alignment: Alignment.topLeft,
          child: AnimatedBuilder(
            animation: _animation,
            builder: (BuildContext context, Widget? child) {
              return Visibility(
                visible: !_animation.isCompleted,
                child: Transform.translate(
                  offset: _animation.value,
                  child: child,
                ),
              );
            },
            child: IconButton(
              icon: const Icon(
                FluentIcons.arrow_circle_down_right_24_regular,
                color: Colors.red,
              ),
              tooltip: S.of(context).movePieceDiagonallyDown,
              onPressed: () {},
            ),
          ),
        ),
        Positioned(
          left: 32,
          top: 32,
          width: 320,
          child: Text(
            S.of(context).mayFly_Detail,
            maxLines: 4,
            style: TextStyle(
              fontSize: AppTheme.textScaler.scale(16),
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }
}

class _Step7 extends StatelessWidget {
  const _Step7({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(left: 16, top: 16),
      width: double.maxFinite,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            S.of(context).youCanModifyRules,
            style: TextStyle(
              fontSize: AppTheme.textScaler.scale(16),
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
