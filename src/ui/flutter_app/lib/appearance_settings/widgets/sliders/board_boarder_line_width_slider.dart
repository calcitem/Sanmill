// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// board_boarder_line_width_slider.dart

part of 'package:sanmill/appearance_settings/widgets/appearance_settings_page.dart';

class _BoardBorderLineWidthSlider extends StatelessWidget {
  const _BoardBorderLineWidthSlider();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Box<DisplaySettings>>(
      key: const Key('board_border_line_width_value_listenable_builder'),
      valueListenable: DB().listenDisplaySettings,
      builder: (BuildContext context, Box<DisplaySettings> box, _) {
        final DisplaySettings displaySettings = box.get(
          DB.displaySettingsKey,
          defaultValue: const DisplaySettings(),
        )!;
        final String valueLabel = displaySettings.boardBorderLineWidth
            .toStringAsFixed(1);

        return _SettingsSliderSheet(
          keyPrefix: 'board_border_line_width',
          title: S.of(context).boardBorderLineWidth,
          valueLabel: valueLabel,
          slider: Slider(
            key: const Key('board_border_line_width_slider'),
            value: displaySettings.boardBorderLineWidth,
            max: 20.0,
            divisions: 200,
            label: valueLabel,
            semanticFormatterCallback: (double value) =>
                value.toStringAsFixed(1),
            onChanged: (double value) {
              logger.t("[config] BoardBorderLineWidth value: $value");
              DB().displaySettings = displaySettings.copyWith(
                boardBorderLineWidth: value,
              );
            },
          ),
        );
      },
    );
  }
}
