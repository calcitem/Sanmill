// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// font_size_slider.dart

part of 'package:sanmill/appearance_settings/widgets/appearance_settings_page.dart';

class _FontSizeSlider extends StatelessWidget {
  const _FontSizeSlider();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: const Key('font_size_slider_semantics'),
      label: S.of(context).fontSize,
      child: ValueListenableBuilder<Box<DisplaySettings>>(
        key: const Key('font_size_slider_value_listenable_builder'),
        valueListenable: DB().listenDisplaySettings,
        builder: (BuildContext context, Box<DisplaySettings> box, _) {
          final DisplaySettings displaySettings = box.get(
            DB.displaySettingsKey,
            defaultValue: const DisplaySettings(),
          )!;

          return Column(
            key: const Key('font_size_slider_column'),
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Center(
                key: const Key('font_size_slider_center'),
                child: SizedBox(
                  key: const Key('font_size_slider_sized_box'),
                  width: MediaQuery.of(context).size.width * 0.8,
                  child: Slider(
                    key: const Key('font_size_slider_slider'),
                    value: displaySettings.fontScale,
                    min: 1,
                    max: 2,
                    divisions: 16,
                    label: displaySettings.fontScale.toStringAsFixed(2),
                    onChanged: (double value) {
                      logger.t("[config] fontSize value: $value");
                      DB().displaySettings =
                          displaySettings.copyWith(fontScale: value);
                    },
                  ),
                ),
              ),
              const Text(
                "ABCDEFG1234567",
                key: Key('font_size_slider_text'),
              ),
            ],
          );
        },
      ),
    );
  }
}
