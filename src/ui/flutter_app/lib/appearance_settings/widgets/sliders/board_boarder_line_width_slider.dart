// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// board_boarder_line_width_slider.dart

part of 'package:sanmill/appearance_settings/widgets/appearance_settings_page.dart';

class _BoardBorderLineWidthSlider extends StatelessWidget {
  const _BoardBorderLineWidthSlider();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: const Key('board_border_line_width_semantics'),
      label: S.of(context).boardBorderLineWidth,
      child: ValueListenableBuilder<Box<DisplaySettings>>(
        key: const Key('board_border_line_width_value_listenable_builder'),
        valueListenable: DB().listenDisplaySettings,
        builder: (BuildContext context, Box<DisplaySettings> box, _) {
          final DisplaySettings displaySettings = box.get(
            DB.displaySettingsKey,
            defaultValue: const DisplaySettings(),
          )!;

          return Center(
            key: const Key('board_border_line_width_center'),
            child: SizedBox(
              key: const Key('board_border_line_width_sized_box'),
              width: MediaQuery.of(context).size.width * 0.8,
              child: Slider(
                key: const Key('board_border_line_width_slider'),
                value: displaySettings.boardBorderLineWidth,
                max: 20.0,
                divisions: 200,
                label: displaySettings.boardBorderLineWidth.toStringAsFixed(1),
                onChanged: (double value) {
                  logger.t("[config] BoardBorderLineWidth value: $value");
                  DB().displaySettings =
                      displaySettings.copyWith(boardBorderLineWidth: value);
                },
              ),
            ),
          );
        },
      ),
    );
  }
}
