// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:ui';

import 'package:flutter/material.dart';

const double kLichessBottomBarHeight = 56;
const double _kCupertinoBarBlurSigma = 30;
const double _kCupertinoBarOpacity = 0.8;

/// Lichess-style fixed-height action bar for game and puzzle screens.
class LichessBottomBar extends StatelessWidget {
  const LichessBottomBar({
    super.key,
    required this.children,
    this.mainAxisAlignment = MainAxisAlignment.spaceAround,
    this.expandChildren = true,
    this.cupertinoTransparent = false,
  });

  const LichessBottomBar.empty({super.key, this.cupertinoTransparent = false})
    : children = const <Widget>[],
      expandChildren = true,
      mainAxisAlignment = MainAxisAlignment.spaceAround;

  final List<Widget> children;
  final MainAxisAlignment mainAxisAlignment;
  final bool expandChildren;
  final bool cupertinoTransparent;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color? barColor =
        theme.platform == TargetPlatform.iOS && cupertinoTransparent
        ? (theme.bottomAppBarTheme.color ?? theme.colorScheme.surface)
              .withValues(alpha: _kCupertinoBarOpacity)
        : null;

    Widget bar = BottomAppBar(
      color: barColor,
      height: kLichessBottomBarHeight,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisAlignment: mainAxisAlignment,
        children: expandChildren
            ? children.map((Widget child) => Expanded(child: child)).toList()
            : children,
      ),
    );

    if (theme.platform == TargetPlatform.iOS && cupertinoTransparent) {
      bar = ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: _kCupertinoBarBlurSigma,
            sigmaY: _kCupertinoBarBlurSigma,
          ),
          child: bar,
        ),
      );
    }

    return MediaQuery.withClampedTextScaling(maxScaleFactor: 1.4, child: bar);
  }
}

/// Button used inside [LichessBottomBar].
class LichessBottomBarButton extends StatelessWidget {
  const LichessBottomBarButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.badgeLabel,
    this.highlighted = false,
    this.showLabel = false,
    this.showTooltip = true,
    this.blink = false,
    this.tooltip,
  });

  final IconData icon;
  final String label;
  final String? badgeLabel;
  final VoidCallback? onTap;
  final bool highlighted;
  final bool showLabel;
  final bool showTooltip;
  final bool blink;
  final String? tooltip;

  bool get enabled => onTap != null;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final Color primary = colorScheme.primary;
    final double? labelFontSize = Theme.of(
      context,
    ).textTheme.bodySmall?.fontSize;

    final Widget child = Opacity(
      opacity: enabled ? 1 : 0.4,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Badge(
            backgroundColor: colorScheme.secondary,
            textStyle: TextStyle(
              color: colorScheme.onSecondary,
              fontWeight: FontWeight.bold,
            ),
            isLabelVisible: badgeLabel != null,
            label: badgeLabel != null ? Text(badgeLabel!) : null,
            child: Icon(icon, color: highlighted ? primary : null),
          ),
          if (showLabel)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: labelFontSize,
                  color: highlighted ? primary : null,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );

    return Semantics(
      container: true,
      enabled: enabled,
      button: true,
      label: label,
      excludeSemantics: true,
      child: Tooltip(
        excludeFromSemantics: true,
        message: tooltip ?? label,
        triggerMode: showTooltip
            ? TooltipTriggerMode.longPress
            : TooltipTriggerMode.manual,
        child: InkWell(
          borderRadius: BorderRadius.zero,
          onTap: onTap,
          child: blink
              ? _AnimatedInvertBackground(
                  color: primary.withValues(alpha: 0.2),
                  child: child,
                )
              : child,
        ),
      ),
    );
  }
}

class _AnimatedInvertBackground extends StatefulWidget {
  const _AnimatedInvertBackground({required this.child, required this.color});

  final Widget child;
  final Color color;

  @override
  State<_AnimatedInvertBackground> createState() =>
      _AnimatedInvertBackgroundState();
}

class _AnimatedInvertBackgroundState extends State<_AnimatedInvertBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Color?> _colorAnimation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );
    _colorAnimation = ColorTween(
      begin: Colors.transparent,
      end: widget.color,
    ).animate(_controller);
    _controller.addStatusListener((AnimationStatus status) {
      if (status == AnimationStatus.completed) {
        _controller.reverse();
      } else if (status == AnimationStatus.dismissed) {
        _controller.forward();
      }
    });
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _colorAnimation,
      builder: (BuildContext context, Widget? child) {
        return ColoredBox(color: _colorAnimation.value!, child: child);
      },
      child: widget.child,
    );
  }
}
