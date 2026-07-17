// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// board_top_slider.dart

part of 'package:sanmill/appearance_settings/widgets/appearance_settings_page.dart';

class _BoardTopSlider extends StatelessWidget {
  const _BoardTopSlider();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Box<DisplaySettings>>(
      key: const Key('board_top_value_listenable_builder'),
      valueListenable: DB().listenDisplaySettings,
      builder: (BuildContext context, Box<DisplaySettings> box, _) {
        final DisplaySettings displaySettings = box.get(
          DB.displaySettingsKey,
          defaultValue: const DisplaySettings(),
        )!;
        final String valueLabel = displaySettings.boardTop.toStringAsFixed(1);

        return _SettingsSliderSheet(
          keyPrefix: 'board_top',
          title: S.of(context).boardTop,
          valueLabel: valueLabel,
          slider: Slider(
            key: const Key('board_top_slider'),
            value: displaySettings.boardTop,
            max: 288.0,
            divisions: 288,
            label: valueLabel,
            semanticFormatterCallback: (double value) =>
                value.toStringAsFixed(1),
            onChanged: (double value) {
              logger.t("[config] boardTop value: $value");
              DB().displaySettings = displaySettings.copyWith(boardTop: value);
            },
          ),
        );
      },
    );
  }
}
