// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// board_inner_ring_size_slider.dart

part of 'package:sanmill/appearance_settings/widgets/appearance_settings_page.dart';

class _BoardInnerRingSizeSlider extends StatelessWidget {
  const _BoardInnerRingSizeSlider();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: const Key('board_inner_ring_size_semantics'),
      label: "Board Inner Ring Size",
      child: ValueListenableBuilder<Box<DisplaySettings>>(
        key: const Key('board_inner_ring_size_value_listenable_builder'),
        valueListenable: DB().listenDisplaySettings,
        builder: (BuildContext context, Box<DisplaySettings> box, _) {
          final DisplaySettings displaySettings = box.get(
            DB.displaySettingsKey,
            defaultValue: const DisplaySettings(),
          )!;

          return Center(
            key: const Key('board_inner_ring_size_center'),
            child: SizedBox(
              key: const Key('board_inner_ring_size_sized_box'),
              width: MediaQuery.of(context).size.width * 0.8,
              child: Slider(
                key: const Key('board_inner_ring_size_slider'),
                value: displaySettings.boardInnerRingSize,
                min: 1.0,
                max: 1.5,
                divisions: 100,
                label: displaySettings.boardInnerRingSize.toStringAsFixed(2),
                onChanged: (double value) {
                  // Round to nearest 0.05 increment
                  final double roundedValue = (value * 20).round() / 20;
                  logger.t("[config] BoardInnerRingSize value: $roundedValue");
                  DB().displaySettings = displaySettings.copyWith(
                    boardInnerRingSize: roundedValue,
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }
}
