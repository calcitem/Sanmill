import 'package:flutter/material.dart';

import 'pieces_layout.dart';

class PiecesLayer extends StatefulWidget {
  const PiecesLayer(this.layoutParams, {super.key});

  final PiecesLayout layoutParams;

  @override
  State createState() => _PiecesLayerState();
}

class _PiecesLayerState extends State<PiecesLayer> {
  //
  @override
  Widget build(BuildContext context) {
    return widget.layoutParams.buildPiecesLayout(context);
  }
}
