// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/material.dart';

import '../themes/app_styles.dart';

/// Lichess-style card section for short grouped lists.
class LichessListSection extends StatelessWidget {
  const LichessListSection({
    super.key,
    required this.children,
    this.header,
    this.headerKey,
    this.cardKey,
    this.margin = const EdgeInsets.fromLTRB(
      AppStyles.bodyPadding,
      0,
      AppStyles.bodyPadding,
      AppStyles.bodyPadding,
    ),
    this.hasLeading = true,
    this.leadingIndent,
    this.clipBehavior = Clip.hardEdge,
    this.backgroundColor,
  });

  final List<Widget> children;
  final Widget? header;
  final Key? headerKey;
  final Key? cardKey;
  final EdgeInsetsGeometry margin;
  final bool hasLeading;
  final double? leadingIndent;
  final Clip clipBehavior;
  final Color? backgroundColor;

  static const double _defaultListTileLeadingWidth = 40;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) {
      return const SizedBox.shrink();
    }

    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.64,
      child: Padding(
        padding: margin,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (header != null)
              Padding(
                key: headerKey,
                padding: const EdgeInsets.only(bottom: 8),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: DefaultTextStyle.merge(
                    style: AppStyles.sectionTitle.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    child: header!,
                  ),
                ),
              ),
            Card(
              key: cardKey,
              margin: EdgeInsets.zero,
              clipBehavior: clipBehavior,
              color: backgroundColor,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _divideTiles(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _divideTiles(BuildContext context) {
    if (Theme.of(context).platform != TargetPlatform.iOS ||
        children.length <= 1) {
      return children;
    }

    final List<Widget> divided = <Widget>[];
    for (int i = 0; i < children.length; i++) {
      divided.add(children[i]);
      if (i != children.length - 1) {
        divided.add(
          Divider(
            key: const Key('lichess_list_section_divider'),
            height: 0,
            thickness: 0,
            indent: hasLeading
                ? 16 + (leadingIndent ?? _defaultListTileLeadingWidth)
                : 16,
          ),
        );
      }
    }
    return divided;
  }
}
