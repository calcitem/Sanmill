// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// how_to_play_screen.dart

import 'package:flutter/material.dart';

import '../custom_drawer/custom_drawer.dart';
import '../generated/intl/l10n.dart';
import '../shared/database/database.dart';
import '../shared/themes/app_theme.dart';

class HowToPlayScreen extends StatelessWidget {
  const HowToPlayScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlockSemantics(
      child: Scaffold(
        key: const Key('how_to_play_screen_scaffold'),
        resizeToAvoidBottomInset: false,
        appBar: AppBar(
          key: const Key('how_to_play_screen_appbar'),
          elevation: 0.0,
          backgroundColor:
              DB().colorSettings.darkBackgroundColor.withValues(alpha: 1.0),
          // Ensure the background color is opaque
          leading: CustomDrawerIcon.of(context)?.drawerIcon,
          title: Text(
            S.of(context).howToPlay,
            style: AppTheme.helpTextStyle,
            key: const Key('how_to_play_screen_appbar_title'),
          ),
          iconTheme: const IconThemeData(
            color: AppTheme.helpTextColor,
          ),
        ),
        backgroundColor:
            DB().colorSettings.darkBackgroundColor.withValues(alpha: 1.0),
        // Ensure the background color is opaque
        body: SingleChildScrollView(
          key: const Key('how_to_play_screen_scrollview'),
          padding: const EdgeInsets.all(16),
          child: Text(
            S.of(context).helpContent,
            style: AppTheme.helpTextStyle,
            key: const Key('how_to_play_screen_body_text'),
          ),
        ),
      ),
    );
  }
}
