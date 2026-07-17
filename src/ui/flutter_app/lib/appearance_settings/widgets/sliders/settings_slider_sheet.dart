// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// settings_slider_sheet.dart

part of 'package:sanmill/appearance_settings/widgets/appearance_settings_page.dart';

class _SettingsSliderSheet extends StatelessWidget {
  const _SettingsSliderSheet({
    required this.keyPrefix,
    required this.title,
    required this.valueLabel,
    required this.slider,
    this.preview,
  });

  final String keyPrefix;
  final String title;
  final String valueLabel;
  final Widget slider;
  final Widget? preview;

  @override
  Widget build(BuildContext context) {
    final TextTheme textTheme = Theme.of(context).textTheme;
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: Padding(
        key: Key('${keyPrefix}_sheet'),
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            ExcludeSemantics(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: <Widget>[
                  Expanded(
                    child: Text(
                      title,
                      key: Key('${keyPrefix}_sheet_title'),
                      style: textTheme.titleMedium,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    valueLabel,
                    key: Key('${keyPrefix}_sheet_value'),
                    style: textTheme.titleMedium?.copyWith(
                      color: colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            MergeSemantics(
              child: Semantics(label: title, child: slider),
            ),
            if (preview case final Widget preview) ...<Widget>[
              const SizedBox(height: 8),
              Center(child: preview),
            ],
          ],
        ),
      ),
    );
  }
}
