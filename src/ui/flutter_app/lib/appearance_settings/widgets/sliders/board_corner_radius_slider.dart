// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// board_corner_radius_slider.dart

part of 'package:sanmill/appearance_settings/widgets/appearance_settings_page.dart';

class _BoardCornerRadiusSlider extends StatelessWidget {
  const _BoardCornerRadiusSlider();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Box<DisplaySettings>>(
      key: const Key('board_corner_radius_value_listenable_builder'),
      valueListenable: DB().listenDisplaySettings,
      builder: (BuildContext context, Box<DisplaySettings> box, _) {
        final DisplaySettings displaySettings = box.get(
          DB.displaySettingsKey,
          defaultValue: const DisplaySettings(),
        )!;
        final String valueLabel = displaySettings.boardCornerRadius
            .toStringAsFixed(1);

        return _SettingsSliderSheet(
          keyPrefix: 'board_corner_radius',
          title: S.of(context).boardCornerRadius,
          valueLabel: valueLabel,
          slider: Slider(
            key: const Key('board_corner_radius_slider'),
            value: displaySettings.boardCornerRadius,
            max: 50.0,
            divisions: 50,
            label: valueLabel,
            semanticFormatterCallback: (double value) =>
                value.toStringAsFixed(1),
            onChanged: (double value) {
              logger.t("[config] BoardCornerRadius value: $value");
              DB().displaySettings = displaySettings.copyWith(
                boardCornerRadius: value,
              );
            },
          ),
        );
      },
    );
  }
}
