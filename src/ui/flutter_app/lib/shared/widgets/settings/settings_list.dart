// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// settings_list.dart

part of 'settings.dart';

class SettingsList extends StatelessWidget {
  const SettingsList({
    super.key,
    required this.children,
  });

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => ListView.separated(
        key: const Key('settings_list'),
        padding: const EdgeInsets.all(16),
        itemBuilder: (_, int i) => children[i],
        separatorBuilder: (_, int i) =>
            const CustomSpacer(key: Key('custom_spacer')),
        itemCount: children.length,
      );
}
