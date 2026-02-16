// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// replay_controls.dart

import 'package:flutter/material.dart';

import '../../generated/intl/l10n.dart';
import '../services/replay_service.dart';

/// Overlay control bar displayed during session replay.
///
/// Shows play/pause, stop, speed selector, and a progress indicator
/// so the user can monitor and control the replay.
class ReplayControls extends StatelessWidget {
  const ReplayControls({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ReplayState>(
      valueListenable: ReplayService().stateNotifier,
      builder: (BuildContext context, ReplayState state, Widget? _) {
        if (state == ReplayState.idle) {
          return const SizedBox.shrink();
        }
        return _ReplayBar(state: state);
      },
    );
  }
}

class _ReplayBar extends StatelessWidget {
  const _ReplayBar({required this.state});

  final ReplayState state;

  @override
  Widget build(BuildContext context) {
    final ReplayService service = ReplayService();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // Replay label.
          const Icon(Icons.replay, color: Colors.amber, size: 16),
          const SizedBox(width: 4),
          Text(
            S.of(context).replay,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 8),

          // Play/Pause toggle.
          _buildPlayPauseButton(service),
          const SizedBox(width: 4),

          // Stop button.
          _buildIconButton(
            icon: Icons.stop,
            color: Colors.red,
            onTap: service.stop,
          ),
          const SizedBox(width: 8),

          // Speed selector.
          _buildSpeedSelector(service),
          const SizedBox(width: 8),

          // Progress indicator.
          _buildProgress(service),
        ],
      ),
    );
  }

  Widget _buildPlayPauseButton(ReplayService service) {
    if (state == ReplayState.finished) {
      return _buildIconButton(
        icon: Icons.check_circle_outline,
        color: Colors.green,
        onTap: service.stop,
      );
    }
    final bool playing = state == ReplayState.playing;
    return _buildIconButton(
      icon: playing ? Icons.pause : Icons.play_arrow,
      color: Colors.white,
      onTap: playing ? service.pause : service.resume,
    );
  }

  Widget _buildIconButton({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(icon, color: color, size: 20),
      ),
    );
  }

  Widget _buildSpeedSelector(ReplayService service) {
    return ValueListenableBuilder<ReplaySpeed>(
      valueListenable: service.speedNotifier,
      builder: (BuildContext context, ReplaySpeed speed, Widget? _) {
        return GestureDetector(
          onTap: () {
            // Cycle through speeds.
            final List<ReplaySpeed> speeds = ReplaySpeed.values;
            final int nextIdx =
                (speeds.indexOf(speed) + 1) % speeds.length;
            service.setSpeed(speeds[nextIdx]);
          },
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white38),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              speed.label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildProgress(ReplayService service) {
    return ValueListenableBuilder<int>(
      valueListenable: service.progressNotifier,
      builder: (BuildContext context, int current, Widget? _) {
        return ValueListenableBuilder<int>(
          valueListenable: service.totalEventsNotifier,
          builder: (BuildContext context, int total, Widget? __) {
            final int display = (current + 1).clamp(0, total);
            return Text(
              '$display/$total',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 11,
              ),
            );
          },
        );
      },
    );
  }
}
