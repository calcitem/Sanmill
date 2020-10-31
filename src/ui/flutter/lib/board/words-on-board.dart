import 'package:flutter/material.dart';
import '../common/color-consts.dart';

class WordsOnBoard extends StatelessWidget {
  //
  static const DigitsFontSize = 18.0;

  @override
  Widget build(BuildContext context) {
    final bChildren = <Widget>[], rChildren = <Widget>[];

    for (var i = 0; i < 7; i++) {
      if (i < 8) {
        bChildren.add(Expanded(child: SizedBox()));
        rChildren.add(Expanded(child: SizedBox()));
      }
    }

    return DefaultTextStyle(
      child: Column(
        children: <Widget>[
          Row(children: bChildren),
          Expanded(child: SizedBox()),
          Expanded(child: SizedBox()),
          Row(children: rChildren),
        ],
      ),
      style: TextStyle(color: ColorConsts.BoardTips),
    );
  }
}
