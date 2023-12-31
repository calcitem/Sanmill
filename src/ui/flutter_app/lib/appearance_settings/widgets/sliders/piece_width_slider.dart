// This file is part of Sanmill.
// Copyright (C) 2019-2024 The Sanmill developers (see AUTHORS file)
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

class _PieceWidthSlider extends StatelessWidget {
  const _PieceWidthSlider();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: S.of(context).pieceWidth,
      child: ValueListenableBuilder<Box<DisplaySettings>>(
        valueListenable: DB().listenDisplaySettings,
        builder: (BuildContext context, Box<DisplaySettings> box, _) {
          final DisplaySettings displaySettings = box.get(
            DB.displaySettingsKey,
            defaultValue: const DisplaySettings(),
          )!;

          // Divided by [MigrationValues.pieceWidth] To represent the old behavior
          return Center(
            child: SizedBox(
              width: MediaQuery.of(context).size.width * 0.8,
              child: Slider(
                value: displaySettings.pieceWidth,
                min: 0.5,
                divisions: 50,
                label: displaySettings.pieceWidth.toStringAsFixed(1),
                onChanged: (double value) {
                  logger.v("[config] pieceWidth value: $value");
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
