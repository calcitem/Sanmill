// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

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
  int? _focusIndex;
  int? _blurIndex;
  List<PieceColor> _pieceList = List<PieceColor>.filled(7 * 7, PieceColor.none);

  int _curIndex = 0;
  final int _maxIndex = 6;

  bool get isFinally => _curIndex == _maxIndex;

  bool get isStart => _curIndex == 0;

  Offset? _maskOffset;

  Size get _size => _isLandscape
      ? Size(landscapeBoardWidth, landscapeBoardWidth)
      : Size(
          deviceWidth(context) - AppTheme.boardPadding * 2,
          deviceWidth(context) - AppTheme.boardPadding * 2,
        );

  Orientation? _orientation;

  double get landscapeBoardWidth => deviceWidth(context) * 0.6;

  double get pieceWidth => _size.width * DB().displaySettings.pieceWidth / 7;

  bool get _isLandscape => _orientation == Orientation.landscape;

  @override
  void initState() {
    super.initState();
    _pieceList[getPieceIndex(3, 1)] = PieceColor.black;
    _pieceList[getPieceIndex(3, 5)] = PieceColor.white;
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
        builder: (BuildContext context, Orientation orientation) {
          if (_orientation != orientation) {
            _orientation = orientation;
            setPiece();
          }
          return Scaffold(
            key: const Key('scaffold'),
            backgroundColor: DB().colorSettings.darkBackgroundColor,
            body: _isLandscape
                ? SafeArea(
                    key: const Key('landscape_safe_area'),
                    child: Stack(
                      key: const Key('stack_landscape'),
                      children: <Widget>[
                        Align(
                          child: SizedBox(
                            width: landscapeBoardWidth,
                            height: landscapeBoardWidth,
                            child: TutorialBoard(
                              key: const Key('tutorial_board_landscape'),
                              focusIndex: _focusIndex,
                              blurIndex: _blurIndex,
                              pieceList: _pieceList,
                            ),
                          ),
                        ),
                        CustomPaint(
                          key: const Key('custom_paint_landscape'),
                          painter: TutorialMaskPainter(
                            maskOffset: _maskOffset,
                            maskRadius: pieceWidth * 1.5,
                          ),
                        ),
                        Column(
                          key: const Key('column_landscape'),
                          children: <Widget>[
                            Container(
                              height: kToolbarHeight,
                              color: Colors.white,
                              child: Row(
                                children: <Widget>[
                                  Semantics(
                                    label: S.of(context).previous,
                                    child: IconButton(
                                      key: const Key(
                                          'landscape_previous_button'),
                                      onPressed:
                                          _curIndex <= 0 ? null : prevStep,
                                      icon: Icon(
                                        Icons.arrow_back,
                                        color: isStart
                                            ? Colors.grey
                                            : Colors.black,
                                      ),
                                    ),
                                  ),
                                  const Spacer(),
                                  IconButton(
                                    key: const Key('landscape_skip_button'),
                                    tooltip: isFinally
                                        ? S.of(context).gotIt
                                        : S.of(context).skip,
                                    onPressed: () {
                                      _finishTutorial(context);
                                    },
                                    icon: isFinally
                                        ? const Icon(
                                            Icons.done_outline,
                                            color: Colors.black,
                                          )
                                        : const Icon(
                                            FluentIcons.arrow_exit_20_regular,
                                            color: Colors.black,
                                          ),
                                  ),
                                  const Spacer(),
                                  Semantics(
                                    label: S.of(context).next,
                                    child: IconButton(
                                      key: const Key('landscape_next_button'),
                                      onPressed: _curIndex >= _maxIndex
                                          ? null
                                          : nextStep,
                                      icon: Icon(
                                        Icons.arrow_forward_rounded,
                                        color: isFinally
                                            ? Colors.grey
                                            : Colors.black,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              child: GestureDetector(
                                key: const Key('gesture_detector_landscape'),
                                onTap: () {
                                  if (_curIndex >= _maxIndex) {
                                    _finishTutorial(context);
                                  } else {
                                    nextStep();
                                  }
                                },
                                behavior: HitTestBehavior.opaque,
                                child: AnimatedSwitcher(
                                  key: const Key('animated_switcher_landscape'),
                                  duration: const Duration(milliseconds: 400),
                                  child: getTutorial(),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  )
                : Stack(
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
                          child: TutorialBoard(
                            key: const Key('tutorial_board_portrait'),
                            focusIndex: _focusIndex,
                            blurIndex: _blurIndex,
                            pieceList: _pieceList,
                          ),
                        ),
                      ),
                      CustomPaint(
                        key: const Key('custom_paint_portrait'),
                        painter: TutorialMaskPainter(
                          maskOffset: _maskOffset,
                          maskRadius: pieceWidth * 1.5,
                        ),
                      ),
                      SafeArea(
                        child: Column(
                          key: const Key('column_portrait'),
                          children: <Widget>[
                            Container(
                              height: kToolbarHeight,
                              color: Colors.white,
                              child: Row(
                                children: <Widget>[
                                  Semantics(
                                    label: S.of(context).previous,
                                    child: IconButton(
                                      key:
                                          const Key('portrait_previous_button'),
                                      onPressed:
                                          _curIndex <= 0 ? null : prevStep,
                                      icon: Icon(
                                        Icons.arrow_back,
                                        color: isStart
                                            ? Colors.grey
                                            : Colors.black,
                                      ),
                                    ),
                                  ),
                                  const Spacer(),
                                  IconButton(
                                    key: const Key('portrait_finish_button'),
                                    tooltip: isFinally
                                        ? S.of(context).gotIt
                                        : S.of(context).skip,
                                    onPressed: () {
                                      _finishTutorial(context);
                                    },
                                    icon: isFinally
                                        ? const Icon(
                                            Icons.done_outline,
                                            color: Colors.black,
                                          )
                                        : const Icon(
                                            FluentIcons.arrow_exit_20_regular,
                                            color: Colors.black,
                                          ),
                                  ),
                                  const Spacer(),
                                  Semantics(
                                    label: S.of(context).next,
                                    child: IconButton(
                                      key: const Key('portrait_next_button'),
                                      onPressed: _curIndex >= _maxIndex
                                          ? null
                                          : nextStep,
                                      icon: Icon(
                                        Icons.arrow_forward_rounded,
                                        color: isFinally
                                            ? Colors.grey
                                            : Colors.black,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              child: GestureDetector(
                                key: const Key('gesture_detector_portrait'),
                                onTap: () {
                                  if (_curIndex >= _maxIndex) {
                                    _finishTutorial(context);
                                  } else {
                                    nextStep();
                                  }
                                },
                                behavior: HitTestBehavior.opaque,
                                child: AnimatedSwitcher(
                                  key: const Key('animated_switcher_portrait'),
                                  duration: const Duration(milliseconds: 400),
                                  child: getTutorial(),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
          );
        },
      ),
    );
  }

  void _finishTutorial(BuildContext context) {
    Navigator.of(context).pop();
    DB().generalSettings = DB().generalSettings.copyWith(showTutorial: false);
  }

  void prevStep() {
    if (_curIndex > 0) {
      _curIndex--;
      setPiece();
      setState(() {});
    }
  }

  void nextStep() {
    if (_curIndex < _maxIndex) {
      _curIndex++;
      setPiece();
      setState(() {});
    }
  }

  Widget getTutorial() {
    Widget? child;
    switch (_curIndex) {
      case 0:
        child = const _Step1(key: ValueKey<String>('Step1'));
        break;
      case 1:
        child = const _Step2(key: ValueKey<String>('Step2'));
        break;
      case 2:
        child = const _Step3(key: ValueKey<String>('Step3'));
        break;
      case 3:
        child = _Step4(
            key: const ValueKey<String>('Step4'),
            begin: getPieceOffset(5, 3),
            end: getPieceOffset(4, 3),
            onEnd: onEnd);
        break;
      case 4:
        child = const _Step5(key: ValueKey<String>('Step5'));
        break;
      case 5:
        child = _Step6(
            key: const ValueKey<String>('Step6'),
            begin: getPieceOffset(3, 2),
            end: getPieceOffset(4, 3),
            onEnd: onEnd);
        break;
      case 6:
        child = const _Step7(key: ValueKey<String>('Step7'));
        break;
    }
    return child ?? const SizedBox.shrink();
  }

  void setPiece() {
    pieceReset();
    switch (_curIndex) {
      case 1: // Placing phase
        {
          _maskOffset = getMaskOffset(3, 5);
          _pieceList[getPieceIndex(3, 5)] = PieceColor.white;
          break;
        }
      case 2: // Counter
        {
          _maskOffset = getMaskOffset(3, 3);
          break;
        }
      case 3: // Moving phase
        {
          _maskOffset = getMaskOffset(5, 3);
          _pieceList[getPieceIndex(4, 2)] = PieceColor.white;
          _pieceList[getPieceIndex(4, 4)] = PieceColor.white;
          _pieceList[getPieceIndex(2, 4)] = PieceColor.black;
          _pieceList[getPieceIndex(2, 3)] = PieceColor.black;
          _pieceList[getPieceIndex(3, 4)] = PieceColor.black;
          _pieceList[getPieceIndex(5, 3)] = PieceColor.white;
          break;
        }
      case 4: // Mill
        {
          _maskOffset = getMaskOffset(5, 3);
          _pieceList[getPieceIndex(4, 2)] = PieceColor.white;
          _pieceList[getPieceIndex(4, 3)] = PieceColor.white;
          _pieceList[getPieceIndex(4, 4)] = PieceColor.white;
          _pieceList[getPieceIndex(5, 1)] = PieceColor.black;
          _pieceList[getPieceIndex(5, 3)] = PieceColor.black;
          _pieceList[getPieceIndex(5, 5)] = PieceColor.black;
          _focusIndex = getPieceIndex(5, 3);
          break;
        }
      case 5: // Flying
        {
          _maskOffset = getMaskOffset(4, 2);
          _pieceList[getPieceIndex(3, 2)] = PieceColor.white;
          _pieceList[getPieceIndex(4, 2)] = PieceColor.white;
          _pieceList[getPieceIndex(4, 4)] = PieceColor.white;
          _pieceList[getPieceIndex(5, 1)] = PieceColor.black;
          _pieceList[getPieceIndex(5, 3)] = PieceColor.black;
          _pieceList[getPieceIndex(5, 5)] = PieceColor.black;
          _pieceList[getPieceIndex(6, 3)] = PieceColor.black;
          break;
        }
    }
  }

  void onEnd() {
    switch (_curIndex) {
      case 2:
        {
          _pieceList[getPieceIndex(5, 3)] = PieceColor.none;
          _pieceList[getPieceIndex(4, 3)] = PieceColor.white;
          break;
        }
      case 3:
        {
          _pieceList[getPieceIndex(5, 3)] = PieceColor.none;
          _pieceList[getPieceIndex(4, 3)] = PieceColor.white;
          break;
        }
      case 5:
        {
          _pieceList[getPieceIndex(3, 2)] = PieceColor.none;
          _pieceList[getPieceIndex(4, 3)] = PieceColor.white;
          break;
        }
    }
    setState(() {});
  }

  void pieceReset() {
    _pieceList = List<PieceColor>.filled(7 * 7, PieceColor.none);
    _maskOffset = null;
    _focusIndex = null;
    _blurIndex = null;
  }

  int getPieceIndex(int row, int col) {
    return row * 7 + col;
  }

  Offset getMaskOffset(int row, int col) {
    final int index = getPieceIndex(row, col);
    return _isLandscape
        ? pointFromIndex(index, _size) +
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
        : pointFromIndex(index, _size) +
            Offset(
              AppTheme.boardPadding,
              AppTheme.boardPadding +
                  kToolbarHeight +
                  MediaQuery.of(context).padding.top,
            );
  }

  Offset getPieceOffset(int row, int col) {
    final int index = getPieceIndex(row, col);
    return _isLandscape
        ? pointFromIndex(index, _size) +
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
        : pointFromIndex(index, _size) +
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
        )
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
        )
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
        vsync: this, duration: const Duration(milliseconds: 1000));
    _animation = Tween<Offset>(begin: widget.begin, end: widget.end)
        .animate(_controller);
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
                child:
                    Transform.translate(offset: _animation.value, child: child),
              );
            },
            child: IconButton(
              icon: const Icon(
                FluentIcons.arrow_circle_up_24_regular,
                color: Colors.red,
              ),
              tooltip: "Move piece up",
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
        )
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
        )
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
        vsync: this, duration: const Duration(milliseconds: 1000));
    _animation = Tween<Offset>(begin: widget.begin, end: widget.end)
        .animate(_controller);
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
                child:
                    Transform.translate(offset: _animation.value, child: child),
              );
            },
            child: IconButton(
              icon: const Icon(
                FluentIcons.arrow_circle_down_right_24_regular,
                color: Colors.red,
              ),
              tooltip: "Move piece diagonally down",
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
        )
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
