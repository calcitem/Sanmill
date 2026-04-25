// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/material.dart';

import '../../game_platform/game_session.dart';
import '../../game_platform/painting/graph_board_painter.dart';
import 'demo_probe_board_geometry.dart';
import 'demo_probe_session.dart';

/// Minimal second game: tic-tac-toe. Used only to validate multi-game shell
/// and [BoardGeometry] without Mill rules.
class DemoProbePage extends StatefulWidget {
  const DemoProbePage({required this.session, super.key});

  final DemoProbeSession session;

  @override
  State<DemoProbePage> createState() => _DemoProbePageState();
}

class _DemoProbePageState extends State<DemoProbePage> {
  static const int _empty = 0;
  static const int _x = 1;
  static const int _o = 2;

  Future<void> _onTap(int index) async {
    await widget.session.apply(
      GameAction(type: 'place', to: BoardCoordinate(index)),
    );
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
              ValueListenableBuilder<GameStateSnapshot>(
                valueListenable: widget.session.state,
                builder:
                    (
                      BuildContext context,
                      GameStateSnapshot snapshot,
                      Widget? child,
                    ) {
                      final List<int> cells = List<int>.from(
                        snapshot.payload['cells']! as List<int>,
                      );
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          GridView.count(
                            shrinkWrap: true,
                            crossAxisCount: 3,
                            children: List<Widget>.generate(9, (int i) {
                              return InkWell(
                                onTap:
                                    cells[i] == _empty &&
                                        !snapshot.outcome.isTerminal
                                    ? () => _onTap(i)
                                    : null,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.outline,
                                    ),
                                  ),
                                  child: Center(
                                    child: Text(
                                      cells[i] == _x
                                          ? 'X'
                                          : cells[i] == _o
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
                          Text(_statusText(snapshot)),
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: widget.session.reset,
                            child: const Text('New game'),
                          ),
                        ],
                      );
                    },
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _statusText(GameStateSnapshot snapshot) {
    switch (snapshot.outcome.kind) {
      case GameOutcomeKind.ongoing:
        return snapshot.activeSeat == PlayerSeat.first
            ? 'X to move'
            : 'O to move';
      case GameOutcomeKind.draw:
        return 'Draw';
      case GameOutcomeKind.win:
        return snapshot.outcome.winner == PlayerSeat.first
            ? 'X wins'
            : 'O wins';
      case GameOutcomeKind.abandoned:
        return 'Abandoned';
    }
  }
}
