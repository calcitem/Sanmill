// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// custom_drawer_header.dart

part of '../../custom_drawer/custom_drawer.dart';

/// Custom Drawer Header
///
/// Displays the animated header title in the drawer.
class CustomDrawerHeader extends StatelessWidget {
  const CustomDrawerHeader({
    super.key,
    required this.headerTitle,
  });

  final String headerTitle;

  @override
  Widget build(BuildContext context) {
    final List<Color> drawerHeaderAnimationColors = <Color>[
      DB().colorSettings.drawerTextColor,
      Colors.black,
      Colors.blue,
      Colors.yellow,
      Colors.red,
      DB().colorSettings.darkBackgroundColor,
      DB().colorSettings.boardBackgroundColor,
      DB().colorSettings.drawerHighlightItemColor,
    ];

    final AnimatedTextKit animatedHeaderText = AnimatedTextKit(
      key: const Key('custom_drawer_header_animated_text_kit'),
      animatedTexts: <ColorizeAnimatedText>[
        ColorizeAnimatedText(
          headerTitle,
          textStyle: Theme.of(context).textTheme.headlineMedium!.copyWith(
                fontWeight: FontWeight.w600,
              ),
          colors: drawerHeaderAnimationColors,
          speed: const Duration(seconds: 3),
          textDirection: Directionality.of(context),
        ),
      ],
      pause: const Duration(seconds: 3),
      repeatForever: true,
      stopPauseOnTap: true,
    );

    final EdgeInsets drawerHeaderPadding = EdgeInsets.only(
      bottom: 16.0,
      top: 16.0 + (Constants.isLargeScreen(context) ? 30.0 : 8.0),
      left: 20.0,
      right: 16.0,
    );

    return Padding(
      key: const Key('custom_drawer_header_padding'),
      padding: drawerHeaderPadding,
      child: ExcludeSemantics(
        key: const Key('custom_drawer_header_exclude_semantics'),
        child: animatedHeaderText,
      ),
    );
  }
}
