// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// board_top_slider.dart

part of 'package:sanmill/appearance_settings/widgets/appearance_settings_page.dart';

class _BoardTopSlider extends StatelessWidget {
  const _BoardTopSlider();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: const Key('board_top_semantics'),
      label: S.of(context).boardTop,
      child: ValueListenableBuilder<Box<DisplaySettings>>(
        key: const Key('board_top_value_listenable_builder'),
        valueListenable: DB().listenDisplaySettings,
        builder: (BuildContext context, Box<DisplaySettings> box, _) {
          final DisplaySettings displaySettings = box.get(
            DB.displaySettingsKey,
            defaultValue: const DisplaySettings(),
          )!;
          const double maxOffset = 288.0;
          final double clampedOffset =
              displaySettings.boardTop.clamp(0.0, maxOffset);

          return Center(
            key: const Key('board_top_center'),
            child: SizedBox(
              key: const Key('board_top_sized_box'),
              width: MediaQuery.of(context).size.width * 0.8,
              child: Slider(
                key: const Key('board_top_slider'),
                value: clampedOffset,
                max: maxOffset,
                divisions: maxOffset.toInt(),
                label: clampedOffset.toStringAsFixed(1),
                onChanged: (double value) {
                  logger.t("[config] boardTop value: $value");
                  DB().displaySettings =
                      displaySettings.copyWith(boardTop: value.clamp(0.0, maxOffset));
                },
              ),
            ),
          );
        },
      ),
    );
  }
}
