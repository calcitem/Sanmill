// This file is part of Sanmill.
// Copyright (C) 2019-2022 The Sanmill developers (see AUTHORS file)
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

part of 'package:sanmill/screens/appearance_settings/appearance_settings_page.dart';

final List<String> _bgList = <String>[
  Assets.images.icBoardBg1.path,
  Assets.images.icBoardBg2.path,
  Assets.images.icBoardBg3.path,
  Assets.images.icBoardBg4.path,
  Assets.images.icBoardBg5.path,
];

class _BoardBackgroundSelect extends StatelessWidget {
  const _BoardBackgroundSelect();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '棋盘背景',
      child: ValueListenableBuilder<Box<DisplaySettings>>(
        valueListenable: DB().listenDisplaySettings,
        builder: (BuildContext context, Box<DisplaySettings> box, _) {
          final DisplaySettings displaySettings = box.get(
            DB.displaySettingsKey,
            defaultValue: const DisplaySettings(),
          )!;

          return GridView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              childAspectRatio: 1080 / 1920,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemBuilder: (BuildContext context, int index) {
              final String asset = index == 0 ? '' : _bgList[index - 1];
              return _BackgroundImageItem(
                asset: asset,
                isSelect: displaySettings.boardBackground == asset,
                onChanged: () {
                  DB().displaySettings = displaySettings.copyWith(boardBackground: asset);
                },
              );
            },
            itemCount: _bgList.length + 1,
          );
        },
      ),
    );
  }
}

class _BackgroundImageItem extends StatelessWidget {
  const _BackgroundImageItem({
    required this.asset,
    this.isSelect = false,
    this.onChanged,
  });

  final String asset;
  final bool isSelect;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    final bool isDefault = asset.isEmpty;
    return GestureDetector(
      onTap: () {
        if (!isSelect) {
          onChanged?.call();
        }
      },
      child: Stack(
        children: <Widget>[
          Container(
            decoration: BoxDecoration(
              color: isDefault ? DB().colorSettings.darkBackgroundColor : null,
              image: isDefault
                  ? null
                  : DecorationImage(
                      image: AssetImage(asset),
                      fit: BoxFit.cover,
                    ),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          Positioned(
            right: 8,
            top: 8,
            child: Icon(
              isSelect ? Icons.check_circle : Icons.check_circle_outline,
              color: Colors.white,
            ),
          )
        ],
      ),
    );
  }
}
