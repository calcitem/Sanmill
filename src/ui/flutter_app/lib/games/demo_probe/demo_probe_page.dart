// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/material.dart';

import '../../game_platform/painting/graph_board_painter.dart';
import 'demo_probe_board_geometry.dart';

/// Minimal second game: tic-tac-toe. Used only to validate multi-game shell
/// and [BoardGeometry] without Mill rules.
class DemoProbePage extends StatefulWidget {
  const DemoProbePage({super.key});

  @override
  State<DemoProbePage> createState() => _DemoProbePageState();
}

class _DemoProbePageState extends State<DemoProbePage> {
  static const int _empty = 0;
  static const int _x = 1;
  static const int _o = 2;

  final List<int> _cells = List<int>.filled(9, _empty);
  int _turn = _x;

  void _onTap(int index) {
    if (_cells[index] != _empty) {
      return;
    }
    setState(() {
      _cells[index] = _turn;
      _turn = _turn == _x ? _o : _x;
    });
  }

  void _newGame() {
    setState(() {
      for (int i = 0; i < 9; i++) {
        _cells[i] = _empty;
      }
      _turn = _x;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                'Platform probe (tic-tac-toe)',
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 120,
                child: CustomPaint(
                  painter: GraphBoardPainter(
                    geometry: demoProbeBoardGeometry,
                    lineColor: Theme.of(context).colorScheme.outline,
                    nodeColor: Theme.of(
                      context,
                    ).colorScheme.primary.withAlpha(128),
                    nodeRadius: 4,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              GridView.count(
                shrinkWrap: true,
                crossAxisCount: 3,
                children: List<Widget>.generate(9, (int i) {
                  return InkWell(
                    onTap: () => _onTap(i),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          _cells[i] == _x
                              ? 'X'
                              : _cells[i] == _o
                              ? 'O'
                              : '',
                          style: const TextStyle(fontSize: 40),
                        ),
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 16),
              FilledButton(onPressed: _newGame, child: const Text('New game')),
            ],
          ),
        ),
      ),
    );
  }
}
