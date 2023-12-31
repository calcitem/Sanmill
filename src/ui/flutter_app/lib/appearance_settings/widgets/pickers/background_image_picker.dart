/*
  This file is part of Sanmill.
  Copyright (C) 2019-2024 The Sanmill developers (see AUTHORS file)

  Sanmill is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  Sanmill is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

part of 'package:sanmill/appearance_settings/widgets/appearance_settings_page.dart';

final List<String> _bgPaths = <String>[
  Assets.images.backgroundImage1.path,
  Assets.images.backgroundImage2.path,
  Assets.images.backgroundImage3.path,
  Assets.images.backgroundImage4.path,
  Assets.images.backgroundImage5.path,
];

class _BackgroundImagePicker extends StatelessWidget {
  const _BackgroundImagePicker();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: S.of(context).backgroundImage,
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
              final String asset = index == 0 ? '' : _bgPaths[index - 1];
              return _BackgroundImageItem(
                asset: asset,
                isSelect: displaySettings.backgroundImagePath == asset,
                onChanged: () {
                  DB().displaySettings =
                      displaySettings.copyWith(backgroundImagePath: asset);
                },
              );
            },
            itemCount: _bgPaths.length + 1,
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
