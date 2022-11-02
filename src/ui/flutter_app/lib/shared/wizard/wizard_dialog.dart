// This file is part of Sanmill.
// Copyright (C) 2019-2022 The Sanmill developers (see AUTHORS file)
//
// Sanmill is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Sanmill is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../../generated/intl/l10n.dart';
import '../../models/general_settings.dart';
import '../../services/database/database.dart';
import '../../services/mill/mill.dart';
import '../painters/painters.dart';
import '../theme/app_theme.dart';
import 'wizard_board.dart';
import 'wizard_mask_painter.dart';

class WizardDialog extends StatefulWidget {
  const WizardDialog({super.key});

  @override
  State<WizardDialog> createState() => _WizardDialogState();
}

class _WizardDialogState extends State<WizardDialog> {
  int? _focusIndex;
  int? _blurIndex;
  List<PieceColor> _pieceList = List<PieceColor>.filled(7 * 7, PieceColor.none);

  int _curIndex = 0;
  final int _maxIndex = 6;

  bool get isFinally => _curIndex == _maxIndex;

  Offset? _maskOffset;

  Size get _size => Size(
        MediaQuery.of(context).size.width - AppTheme.boardPadding * 2,
        MediaQuery.of(context).size.width - AppTheme.boardPadding * 2,
      );

  @override
  void initState() {
    super.initState();
    _pieceList[getPieceIndex(3, 1)] = PieceColor.black;
    _pieceList[getPieceIndex(3, 5)] = PieceColor.white;
  }

  @override
  Widget build(BuildContext context) {
    final double pieceWidth = _size.width * DB().displaySettings.pieceWidth / 7;
    return WillPopScope(
      onWillPop: () async {
        prevStep();
        return false;
      },
      child: Scaffold(
        backgroundColor: DB().colorSettings.darkBackgroundColor,
        body: Stack(
          children: <Widget>[
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(
                  left: AppTheme.boardPadding,
                  right: AppTheme.boardPadding,
                  top: kToolbarHeight + AppTheme.boardPadding,
                ),
                child: WizardBoard(
                  focusIndex: _focusIndex,
                  blurIndex: _blurIndex,
                  pieceList: _pieceList,
                ),
              ),
            ),
            CustomPaint(
              painter: WizardMaskPainter(
                maskOffset: _maskOffset,
                maskRadius: pieceWidth * 1.5,
              ),
            ),
            SafeArea(
              child: Column(
                children: <Widget>[
                  Container(
                    height: kToolbarHeight,
                    color: Colors.white,
                    child: Row(
                      children: <Widget>[
                        IconButton(
                          onPressed: _curIndex <= 0 ? null : prevStep,
                          icon: const Icon(Icons.arrow_back),
                        ),
                        const Spacer(),
                        IconButton(
                          onPressed: () {
                            Navigator.of(context).pop();
                            DB().generalSettings =
                                DB().generalSettings.copyWith(showWizard: true);
                          },
                          icon: isFinally
                              ? const Icon(Icons.done_outline)
                              : const Icon(FluentIcons.arrow_exit_20_regular),
                        ),
                        const Spacer(),
                        IconButton(
                          onPressed: _curIndex >= _maxIndex ? null : nextStep,
                          icon: const Icon(Icons.arrow_forward_rounded),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 400),
                      child: getWizard(),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
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

  Widget getWizard() {
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
    return pointFromIndex(index, _size) +
        Offset(
          AppTheme.boardPadding,
          AppTheme.boardPadding +
              kToolbarHeight +
              MediaQuery.of(context).padding.top,
        );
  }

  Offset getPieceOffset(int row, int col) {
    final int index = getPieceIndex(row, col);
    return pointFromIndex(index, _size) +
        const Offset(AppTheme.boardPadding, AppTheme.boardPadding);
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
          child: Text(
            "${S.of(context).appName}\n${S.of(context).howToPlay}",
            style: const TextStyle(
              fontSize: 32,
              color: Colors.white,
            ),
            textScaleFactor: DB().displaySettings.fontScale,
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
            style: const TextStyle(
              fontSize: 16,
              color: Colors.white,
            ),
            textScaleFactor: DB().displaySettings.fontScale,
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
          child: Text(
            S.of(context).isPieceCountInHandShown,
            style: const TextStyle(
              fontSize: 16,
              color: Colors.white,
            ),
            textScaleFactor: DB().displaySettings.fontScale,
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
              onPressed: () {},
            ),
          ),
        ),
        Positioned(
          left: 32,
          top: 32,
          child: Text(
            "${S.of(context).movingPhase}\n${S.of(context).toSelectPiece}\n${S.of(context).toMovePiece}",
            style: const TextStyle(
              fontSize: 16,
              color: Colors.white,
            ),
            textScaleFactor: DB().displaySettings.fontScale,
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
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 16,
              color: Colors.white,
            ),
            textScaleFactor: DB().displaySettings.fontScale,
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
            maxLines: 2,
            style: const TextStyle(
              fontSize: 16,
              color: Colors.white,
            ),
            textScaleFactor: DB().displaySettings.fontScale,
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
            '您可以在配置中修改规则。', // TODO
            style: const TextStyle(
              fontSize: 16,
              color: Colors.white,
            ),
            textScaleFactor: DB().displaySettings.fontScale,
          ),
        ],
      ),
    );
  }
}
