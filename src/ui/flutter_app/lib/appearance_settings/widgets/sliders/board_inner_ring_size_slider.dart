// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// board_inner_ring_size_slider.dart

part of 'package:sanmill/appearance_settings/widgets/appearance_settings_page.dart';

class _BoardInnerRingSizeSlider extends StatelessWidget {
  const _BoardInnerRingSizeSlider();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Box<DisplaySettings>>(
      key: const Key('board_inner_ring_size_value_listenable_builder'),
      valueListenable: DB().listenDisplaySettings,
      builder: (BuildContext context, Box<DisplaySettings> box, _) {
        final DisplaySettings displaySettings = box.get(
          DB.displaySettingsKey,
          defaultValue: const DisplaySettings(),
        )!;
        final String valueLabel = displaySettings.boardInnerRingSize
            .toStringAsFixed(2);

        return _SettingsSliderSheet(
          keyPrefix: 'board_inner_ring_size',
          title: S.of(context).boardInnerRingSize,
          valueLabel: valueLabel,
          slider: Slider(
            key: const Key('board_inner_ring_size_slider'),
            value: displaySettings.boardInnerRingSize,
            min: 1.0,
            max: 1.5,
            divisions: 100,
            label: valueLabel,
            semanticFormatterCallback: (double value) =>
                value.toStringAsFixed(2),
            onChanged: (double value) {
              // Round to nearest 0.05 increment
              final double roundedValue = (value * 20).round() / 20;
              logger.t("[config] BoardInnerRingSize value: $roundedValue");
              DB().displaySettings = displaySettings.copyWith(
                boardInnerRingSize: roundedValue,
              );
            },
          ),
        );
      },
    );
  }
}
