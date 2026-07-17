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
    final List<String> paragraphs = S
        .of(context)
        .helpContent
        .trim()
        .split(RegExp(r'\n\s*\n'));

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
        body: ListView.separated(
          key: const Key('how_to_play_screen_scrollview'),
          padding: const EdgeInsets.all(16),
          itemCount: paragraphs.length,
          separatorBuilder: (_, _) => const SizedBox(height: 16),
          itemBuilder: (BuildContext context, int index) {
            final String paragraph = paragraphs[index].trim();
            final bool isHeading = _isHelpSectionHeading(paragraph);
            return Semantics(
              key: ValueKey<String>(
                isHeading
                    ? 'how_to_play_heading_$index'
                    : 'how_to_play_paragraph_$index',
              ),
              header: isHeading,
              child: Text(
                paragraph,
                style: isHeading
                    ? theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.onSurface,
                        fontWeight: FontWeight.w700,
                      )
                    : theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.onSurface,
                        height: 1.35,
                      ),
              ),
            );
          },
        ),
      ),
    );
  }
}

bool _isHelpSectionHeading(String paragraph) {
  if (paragraph.isEmpty || paragraph.contains('\n') || paragraph.length > 40) {
    return false;
  }
  return !RegExp(r'[.!?。！？:：;；]$').hasMatch(paragraph);
}
