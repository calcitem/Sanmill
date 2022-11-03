import 'package:flutter/material.dart';
import '../../generated/assets/assets.gen.dart';
import '../../models/general_settings.dart';
import '../../services/database/database.dart';
import '../../services/mill/mill.dart';
import '../painters/painters.dart';
import '../theme/app_theme.dart';
import 'guide_board.dart';
import 'guide_mask_painter.dart';

class GuideDialog extends StatefulWidget {
  const GuideDialog({super.key});

  @override
  State<GuideDialog> createState() => _GuideDialogState();
}

class _GuideDialogState extends State<GuideDialog> {
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
    _pieceList[0] = PieceColor.white;
  }

  @override
  Widget build(BuildContext context) {
    final double pieceWidth = _size.width * DB().displaySettings.pieceWidth / 7;
    return WillPopScope(
      onWillPop: () async {
        preStep();
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
                child: GuideBoard(
                  focusIndex: _focusIndex,
                  blurIndex: _blurIndex,
                  pieceList: _pieceList,
                ),
              ),
            ),
            CustomPaint(
              painter: GuideMaskPainter(
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
                          onPressed: _curIndex <= 0 ? null : preStep,
                          icon: const Icon(Icons.arrow_back),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () {
                            Navigator.of(context).pop();
                            DB().generalSettings =
                                DB().generalSettings.copyWith(showGuide: true);
                          },
                          child: Text(isFinally ? 'Got it' : 'Skip'),
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
                      child: getGuide(),
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

  void preStep() {
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

  Widget getGuide() {
    Widget? child;
    switch (_curIndex) {
      case 0:
        child = const _Step1(key: ValueKey<String>('Step1'));
        break;
      case 1:
        child = const _Step2(key: ValueKey<String>('Step2'));
        break;
      case 2:
        child = _Step3(
            key: const ValueKey<String>('Step3'),
            begin: getPieceOffset(5, 3),
            end: getPieceOffset(4, 3),
            onEnd: onEnd);
        break;
      case 3:
        child = const _Step4(key: ValueKey<String>('Step4'));
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
      case 2:
        {
          _maskOffset = getMaskOffset(5, 3);
          _pieceList[getPieceIndex(4, 2)] = PieceColor.white;
          _pieceList[getPieceIndex(4, 4)] = PieceColor.white;
          _pieceList[getPieceIndex(2, 4)] = PieceColor.black;
          _pieceList[getPieceIndex(3, 4)] = PieceColor.black;
          _pieceList[getPieceIndex(5, 3)] = PieceColor.white;
          break;
        }
      case 3:
        {
          _maskOffset = getMaskOffset(3, 3);
          _pieceList[getPieceIndex(4, 2)] = PieceColor.white;
          _pieceList[getPieceIndex(4, 3)] = PieceColor.white;
          _pieceList[getPieceIndex(4, 4)] = PieceColor.white;
          _pieceList[getPieceIndex(3, 1)] = PieceColor.white;
          _pieceList[getPieceIndex(3, 4)] = PieceColor.black;
          _pieceList[getPieceIndex(5, 1)] = PieceColor.black;
          _pieceList[getPieceIndex(5, 3)] = PieceColor.black;
          _pieceList[getPieceIndex(5, 5)] = PieceColor.black;
          _focusIndex = getPieceIndex(3, 4);
          break;
        }
      case 4:
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
      case 5:
        {
          _maskOffset = getMaskOffset(4, 2);
          _pieceList[getPieceIndex(3, 2)] = PieceColor.white;
          _pieceList[getPieceIndex(4, 2)] = PieceColor.white;
          _pieceList[getPieceIndex(4, 4)] = PieceColor.white;
          _pieceList[getPieceIndex(5, 1)] = PieceColor.black;
          _pieceList[getPieceIndex(5, 3)] = PieceColor.black;
          _pieceList[getPieceIndex(5, 5)] = PieceColor.black;
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
          right: 32,
          bottom: 32,
          child: Image.asset(
            Assets.images.icGuidePet.keyName,
            width: 96,
          ),
        ),
        Positioned(
          left: 32,
          bottom: 128,
          child: Text(
            '111111',
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
          Image.asset(
            Assets.images.icGuidePet.keyName,
            width: 96,
          ),
          Text(
            '222222',
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

class _Step3 extends StatefulWidget {
  const _Step3({
    super.key,
    required this.begin,
    required this.end,
    required this.onEnd,
  });

  final Offset begin;
  final Offset end;
  final VoidCallback onEnd;

  @override
  State<_Step3> createState() => _Step3State();
}

class _Step3State extends State<_Step3> with SingleTickerProviderStateMixin {
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
            child: Image.asset(
              Assets.images.icGuidePet.path,
              width: 24,
            ),
          ),
        ),
        Positioned(
          right: 32,
          bottom: 32,
          child: Image.asset(
            Assets.images.icGuidePet.keyName,
            width: 96,
          ),
        ),
        Positioned(
          left: 32,
          top: 32,
          child: Text(
            '333333',
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

class _Step4 extends StatelessWidget {
  const _Step4({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        Positioned(
          right: 32,
          bottom: 32,
          child: Image.asset(
            Assets.images.icGuidePet.keyName,
            width: 96,
          ),
        ),
        Positioned(
          left: 32,
          top: 32,
          child: Text(
            '444444',
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
    return Stack(
      children: <Widget>[
        Positioned(
          left: 32,
          top: 32,
          child: Image.asset(
            Assets.images.icGuidePet.keyName,
            width: 96,
          ),
        ),
        Positioned(
          left: 32,
          bottom: 32,
          child: Text(
            '555555',
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
            child: Image.asset(
              Assets.images.icGuidePet.path,
              width: 24,
            ),
          ),
        ),
        Positioned(
          right: 32,
          bottom: 32,
          child: Image.asset(
            Assets.images.icGuidePet.keyName,
            width: 96,
          ),
        ),
        Positioned(
          left: 32,
          top: 32,
          child: Text(
            '666666',
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
          Image.asset(
            Assets.images.icGuidePet.keyName,
            width: 96,
          ),
          Text(
            '777777',
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
