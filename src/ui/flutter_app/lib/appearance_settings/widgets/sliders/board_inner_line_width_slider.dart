// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// board_inner_line_width_slider.dart

part of 'package:sanmill/appearance_settings/widgets/appearance_settings_page.dart';

class _BoardInnerLineWidthSlider extends StatelessWidget {
  const _BoardInnerLineWidthSlider();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: const Key('board_inner_line_width_semantics'),
      label: S.of(context).boardInnerLineWidth,
      child: ValueListenableBuilder<Box<DisplaySettings>>(
        key: const Key('board_inner_line_width_value_listenable_builder'),
        valueListenable: DB().listenDisplaySettings,
        builder: (BuildContext context, Box<DisplaySettings> box, _) {
          final DisplaySettings displaySettings = box.get(
            DB.displaySettingsKey,
            defaultValue: const DisplaySettings(),
          )!;

          return Center(
            key: const Key('board_inner_line_width_center'),
            child: SizedBox(
              key: const Key('board_inner_line_width_sized_box'),
              width: MediaQuery.of(context).size.width * 0.8,
              child: Slider(
                key: const Key('board_inner_line_width_slider'),
                value: displaySettings.boardInnerLineWidth,
                max: 20,
                divisions: 200,
                label: displaySettings.boardInnerLineWidth.toStringAsFixed(1),
                onChanged: (double value) {
                  logger.t("[config] BoardInnerLineWidth value: $value");
                  DB().displaySettings =
                      displaySettings.copyWith(boardInnerLineWidth: value);
                },
              ),
            ),
          );
        },
      ),
    );
  }
}
