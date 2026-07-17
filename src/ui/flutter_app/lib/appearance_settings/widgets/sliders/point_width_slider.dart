// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// point_width_slider.dart

part of 'package:sanmill/appearance_settings/widgets/appearance_settings_page.dart';

class _PointWidthSlider extends StatelessWidget {
  const _PointWidthSlider();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Box<DisplaySettings>>(
      key: const Key('point_width_slider_value_listenable_builder'),
      valueListenable: DB().listenDisplaySettings,
      builder: (BuildContext context, Box<DisplaySettings> box, _) {
        final DisplaySettings displaySettings = box.get(
          DB.displaySettingsKey,
          defaultValue: const DisplaySettings(),
        )!;
        final String valueLabel = displaySettings.pointWidth.toStringAsFixed(1);

        // Divided by [MigrationValues.pieceWidth] To represent the old behavior
        return _SettingsSliderSheet(
          keyPrefix: 'point_width_slider',
          title: S.of(context).pointWidth,
          valueLabel: valueLabel,
          slider: Slider(
            key: const Key('point_width_slider_slider'),
            value: displaySettings.pointWidth,
            max: 30.0,
            divisions: 30,
            label: valueLabel,
            semanticFormatterCallback: (double value) =>
                value.toStringAsFixed(1),
            onChanged: (double value) {
              logger.t("[config] pointWidth value: $value");
              DB().displaySettings = displaySettings.copyWith(
                pointWidth: value,
              );
            },
          ),
        );
      },
    );
  }
}
