// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/material.dart';

import '../../game_platform/painting/graph_board_painter.dart';
import 'othello_board_geometry.dart';

class OthelloPage extends StatelessWidget {
  const OthelloPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                'Othello (TGF pressure test)',
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 260,
                child: CustomPaint(
                  painter: GraphBoardPainter(
                    geometry: othelloBoardGeometry,
                    lineColor: Theme.of(context).colorScheme.outline,
                    nodeColor: Theme.of(
                      context,
                    ).colorScheme.primary.withAlpha(96),
                    nodeRadius: 3,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Rust crate: tgf-othello'),
            ],
          ),
        ),
      ),
    );
  }
}
