import 'package:flutter/material.dart';
import '../../services/database/database.dart';
import '../../services/mill/mill.dart';
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
  final List<PieceColor> _pieceList = List<PieceColor>.filled(7 * 7, PieceColor.none);
  int _curIndex = 0;
  int _maxIndex = 7;

  @override
  void initState() {
    super.initState();
    _pieceList[0] = PieceColor.white;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DB().colorSettings.darkBackgroundColor,
      body: Stack(
        children: [
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(
                left: AppTheme.boardPadding,
                right: AppTheme.boardPadding,
                top: 120,
              ),
              child: GuideBoard(
                focusIndex: _focusIndex,
                blurIndex: _blurIndex,
                pieceList: _pieceList,
              ),
            ),
          ),
          CustomPaint(
            painter: GuideMaskPainter(background: Colors.black38, maskOffset: Offset(100, 300)),
          ),
          SafeArea(
            child: Container(
              height: kToolbarHeight,
              color: Colors.white,
              child: Row(
                children: [
                  IconButton(
                    onPressed: _curIndex <= 0 ? null : preStep,
                    icon: const Icon(Icons.arrow_back),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                    child: const Text('Skip'),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: _curIndex >= _maxIndex ? null : nextStep,
                    icon: const Icon(Icons.arrow_forward_rounded),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void preStep() {
    _curIndex--;
    setState(() {});
  }

  void nextStep() {
    _curIndex++;
    setState(() {});
  }

  void setPiece(int step) {
    _pieceList.clear();
    switch (step) {
      case 0:
        {
          _pieceList[0] = PieceColor.white;
          break;
        }
    }
    setState(() {});
  }
}
