// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// settings_card.dart

part of 'settings.dart';

class SettingsCard extends StatelessWidget {
  const SettingsCard({super.key, required this.children, required this.title});

  final Widget title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;
    final TextStyle textStyle = isDark
        ? theme.textTheme.titleLarge!.copyWith(
            color: theme.colorScheme.onSurface,
            fontWeight: FontWeight.w700,
          )
        : theme.textTheme.titleLarge!.apply(
            color: AppTheme.settingsHeaderTextColor,
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        DefaultTextStyle(
          key: const Key('settings_card_title'),
          style: textStyle,
          textAlign: TextAlign.start,
          child: title,
        ),
        Card(
          key: const Key('settings_card_card'),
          child: Padding(
            padding: EdgeInsets.zero,
            child: Column(
              children: <Widget>[
                for (int i = 0; i < children.length; i++)
                  i == children.length - 1
                      ? children[i]
                      : Column(
                          children: <Widget>[
                            children[i],
                            Divider(
                              color: isDark
                                  ? theme.colorScheme.onSurface.withValues(
                                      alpha: 0.12,
                                    )
                                  : AppTheme.listItemDividerColor,
                            ),
                          ],
                        ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
