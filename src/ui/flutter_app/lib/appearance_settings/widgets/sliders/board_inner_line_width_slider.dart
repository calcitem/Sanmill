// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// board_inner_line_width_slider.dart

part of 'package:sanmill/appearance_settings/widgets/appearance_settings_page.dart';

class _BoardInnerLineWidthSlider extends StatelessWidget {
  const _BoardInnerLineWidthSlider();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Box<DisplaySettings>>(
      key: const Key('board_inner_line_width_value_listenable_builder'),
      valueListenable: DB().listenDisplaySettings,
      builder: (BuildContext context, Box<DisplaySettings> box, _) {
        final DisplaySettings displaySettings = box.get(
          DB.displaySettingsKey,
          defaultValue: const DisplaySettings(),
        )!;
        final String valueLabel = displaySettings.boardInnerLineWidth
            .toStringAsFixed(1);

        return _SettingsSliderSheet(
          keyPrefix: 'board_inner_line_width',
          title: S.of(context).boardInnerLineWidth,
          valueLabel: valueLabel,
          slider: Slider(
            key: const Key('board_inner_line_width_slider'),
            value: displaySettings.boardInnerLineWidth,
            max: 20,
            divisions: 200,
            label: valueLabel,
            semanticFormatterCallback: (double value) =>
                value.toStringAsFixed(1),
            onChanged: (double value) {
              logger.t("[config] BoardInnerLineWidth value: $value");
              DB().displaySettings = displaySettings.copyWith(
                boardInnerLineWidth: value,
              );
            },
          ),
        );
      },
    );
  }
}
