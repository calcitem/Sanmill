// This file is part of Sanmill.
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)
//
// Sanmill is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Sanmill is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

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

          return Center(
            key: const Key('board_top_center'),
            child: SizedBox(
              key: const Key('board_top_sized_box'),
              width: MediaQuery.of(context).size.width * 0.8,
              child: Slider(
                key: const Key('board_top_slider'),
                value: displaySettings.boardTop,
                max: 288.0,
                // TODO: Overflow, convert to v2 config
                divisions: 288,
                label: displaySettings.boardTop.toStringAsFixed(1),
                onChanged: (double value) {
                  logger.t("[config] boardTop value: $value");
                  DB().displaySettings =
                      displaySettings.copyWith(boardTop: value);
                },
              ),
            ),
          );
        },
      ),
    );
  }
}
