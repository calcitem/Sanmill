// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// how_to_play_screen.dart

import 'package:flutter/material.dart';

import '../generated/intl/l10n.dart';

class HowToPlayScreen extends StatelessWidget {
  const HowToPlayScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return BlockSemantics(
      child: Scaffold(
        key: const Key('how_to_play_screen_scaffold'),
        resizeToAvoidBottomInset: false,
        backgroundColor: theme.colorScheme.surface,
        appBar: AppBar(
          key: const Key('how_to_play_screen_appbar'),
          title: Text(
            S.of(context).howToPlay,
            key: const Key('how_to_play_screen_appbar_title'),
          ),
        ),
        body: SingleChildScrollView(
          key: const Key('how_to_play_screen_scrollview'),
          padding: const EdgeInsets.all(16),
          child: Text(
            S.of(context).helpContent,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurface,
              height: 1.35,
            ),
            key: const Key('how_to_play_screen_body_text'),
          ),
        ),
      ),
    );
  }
}
