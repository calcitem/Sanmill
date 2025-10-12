// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// custom_drawer_header.dart

part of '../../custom_drawer/custom_drawer.dart';

/// Custom Drawer Header
///
/// Displays the animated header title in the drawer.
class CustomDrawerHeader extends StatelessWidget {
  const CustomDrawerHeader({super.key, required this.headerTitle});

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
          textStyle: Theme.of(
            context,
          ).textTheme.headlineMedium!.copyWith(fontWeight: FontWeight.w600),
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

    final TextStyle welcomeStyle =
        (Theme.of(context).textTheme.labelLarge ??
                Theme.of(context).textTheme.titleSmall ??
                const TextStyle())
            .copyWith(
      color: DB().colorSettings.drawerTextColor.withOpacity(0.72),
      letterSpacing: 1.1,
      fontWeight: FontWeight.w600,
    );

    final BorderRadius headerRadius = BorderRadius.circular(28.0);
    final LinearGradient headerGradient = LinearGradient(
      colors: <Color>[
        Color.alphaBlend(
          DB().colorSettings.drawerHighlightItemColor.withOpacity(0.55),
          DB().colorSettings.drawerColor.withOpacity(0.45),
        ),
        Color.alphaBlend(
          DB().colorSettings.drawerHighlightItemColor.withOpacity(0.18),
          DB().colorSettings.drawerColor.withOpacity(0.75),
        ),
      ],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );

    return Padding(
      key: const Key('custom_drawer_header_padding'),
      padding: drawerHeaderPadding,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: headerGradient,
          borderRadius: headerRadius,
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: DB().colorSettings.drawerHighlightItemColor
                  .withOpacity(0.22),
              blurRadius: 28,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: headerRadius,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Padding(
              key: const Key('custom_drawer_header_container_padding'),
              padding:
                  const EdgeInsets.symmetric(horizontal: 20.0, vertical: 20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Container(
                        decoration: BoxDecoration(
                          color: DB()
                              .colorSettings
                              .drawerHighlightItemColor
                              .withOpacity(0.24),
                          shape: BoxShape.circle,
                        ),
                        padding: const EdgeInsets.all(12.0),
                        child: Icon(
                          Icons.grid_view_rounded,
                          color: DB().colorSettings.drawerTextColor,
                        ),
                      ),
                      const SizedBox(width: 16.0),
                      Expanded(
                        child: Text(
                          S.of(context).welcome,
                          style: welcomeStyle,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18.0),
                  Semantics(
                    label: headerTitle,
                    child: ExcludeSemantics(
                      key: const Key('custom_drawer_header_exclude_semantics'),
                      child: animatedHeaderText,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
