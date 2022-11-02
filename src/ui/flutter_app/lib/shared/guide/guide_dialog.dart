import 'package:flutter/material.dart';
import '../../services/mill/mill.dart';
import 'guide_board.dart';

class GuideDialog extends StatefulWidget {
  const GuideDialog({super.key});

  @override
  State<GuideDialog> createState() => _GuideDialogState();
}

class _GuideDialogState extends State<GuideDialog> {
  int? _focusIndex;
  int? _blurIndex;
  final List<PieceColor> _pieceList = List<PieceColor>.filled(7 * 7, PieceColor.none);

  @override
  void initState() {
    super.initState();
    _pieceList[0] = PieceColor.white;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: GuideBoard(
          focusIndex: _focusIndex,
          blurIndex: _blurIndex,
          pieceList: _pieceList,
        ),
      ),
    );
  }
}
