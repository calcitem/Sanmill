// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// piece_width_slider.dart

part of 'package:sanmill/appearance_settings/widgets/appearance_settings_page.dart';

class _PieceWidthSlider extends StatelessWidget {
  const _PieceWidthSlider();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: const Key('piece_width_slider_semantics'),
      label: S.of(context).pieceWidth,
      child: ValueListenableBuilder<Box<DisplaySettings>>(
        key: const Key('piece_width_slider_value_listenable_builder'),
        valueListenable: DB().listenDisplaySettings,
        builder: (BuildContext context, Box<DisplaySettings> box, _) {
          final DisplaySettings displaySettings = box.get(
            DB.displaySettingsKey,
            defaultValue: const DisplaySettings(),
          )!;

          // Divided by [MigrationValues.pieceWidth] To represent the old behavior
          return Center(
            key: const Key('piece_width_slider_center'),
            child: SizedBox(
              key: const Key('piece_width_slider_sized_box'),
              width: MediaQuery.of(context).size.width * 0.8,
              child: Slider(
                key: const Key('piece_width_slider_slider'),
                value: displaySettings.pieceWidth,
                min: 0.5,
                divisions: 50,
                label: displaySettings.pieceWidth.toStringAsFixed(1),
                onChanged: (double value) {
                  logger.t("[config] pieceWidth value: $value");
                  DB().displaySettings =
                      displaySettings.copyWith(pieceWidth: value);
                },
              ),
            ),
          );
        },
      ),
    );
  }
}
