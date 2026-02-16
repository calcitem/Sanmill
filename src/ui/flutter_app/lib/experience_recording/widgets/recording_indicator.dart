// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// recording_indicator.dart

import 'package:flutter/material.dart';

import '../../generated/intl/l10n.dart';
import '../services/recording_service.dart';

/// A compact floating indicator shown when experience recording is active.
///
/// Displays a pulsing red dot and the text "REC" with an event counter.
/// Tapping the indicator shows a bottom sheet with quick actions
/// (stop recording, view count).
class RecordingIndicator extends StatelessWidget {
  const RecordingIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: RecordingService().isRecordingNotifier,
      builder: (BuildContext context, bool isRecording, Widget? _) {
        if (!isRecording) {
          return const SizedBox.shrink();
        }
        return _RecordingBadge();
      },
    );
  }
}

class _RecordingBadge extends StatefulWidget {
  @override
  State<_RecordingBadge> createState() => _RecordingBadgeState();
}

class _RecordingBadgeState extends State<_RecordingBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _opacity = Tween<double>(
      begin: 0.3,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _showOptions(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 8,
                  ),
                  child: ValueListenableBuilder<int>(
                    valueListenable: RecordingService().eventCountNotifier,
                    builder: (BuildContext context, int count, Widget? _) {
                      return Text(
                        '${S.of(context).recording} · '
                        '$count ${S.of(context).sessionEventCount}',
                        style: Theme.of(context).textTheme.titleMedium,
                      );
                    },
                  ),
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(
                    Icons.stop_circle_outlined,
                    color: Colors.red,
                  ),
                  title: Text(S.of(context).stopRecording),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await RecordingService().stopRecording();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showOptions(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // Pulsing red dot.
            AnimatedBuilder(
              animation: _opacity,
              builder: (BuildContext context, Widget? child) {
                return Opacity(opacity: _opacity.value, child: child);
              },
              child: Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
              ),
            ),
            const SizedBox(width: 6),
            const Text(
              'REC',
              style: TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(width: 4),
            // Live event counter.
            ValueListenableBuilder<int>(
              valueListenable: RecordingService().eventCountNotifier,
              builder: (BuildContext context, int count, Widget? _) {
                return Text(
                  '($count)',
                  style: const TextStyle(color: Colors.white70, fontSize: 10),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
