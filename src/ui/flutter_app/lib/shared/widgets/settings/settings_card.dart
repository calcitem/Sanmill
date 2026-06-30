// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// settings_card.dart

part of 'settings.dart';

class SettingsCard extends StatelessWidget {
  const SettingsCard({super.key, required this.children, required this.title});

  final Widget title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LichessListSection(
    header: title,
    headerKey: const Key('settings_card_title'),
    cardKey: const Key('settings_card_card'),
    margin: const EdgeInsets.all(AppStyles.bodyPadding),
    children: children,
  );
}
