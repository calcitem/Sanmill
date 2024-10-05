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

final List<String> _boardPaths = <String>[
  Assets.images.backgroundImage1.path,
  Assets.images.backgroundImage2.path,
  Assets.images.backgroundImage3.path,
  Assets.images.backgroundImage4.path,
  Assets.images.backgroundImage5.path,
  Assets.images.backgroundImage6.path,
  Assets.images.backgroundImage7.path,
];

class _BoardImagePicker extends StatelessWidget {
  const _BoardImagePicker();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: S.of(context).boardImage,
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
              // childAspectRatio: 1 / 1,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemBuilder: (BuildContext context, int index) {
              final String asset = index == 0 ? '' : _boardPaths[index - 1];
              return _BoardImageItem(
                asset: asset,
                isSelect: displaySettings.boardImagePath == asset,
                onChanged: () {
                  DB().displaySettings =
                      displaySettings.copyWith(boardImagePath: asset);
                },
                displaySettings: displaySettings,
              );
            },
            itemCount: _boardPaths.length + 1,
          );
        },
      ),
    );
  }
}

class _BoardImageItem extends StatelessWidget {
  const _BoardImageItem({
    required this.asset,
    this.isSelect = false,
    this.onChanged,
    required this.displaySettings,
  });

  final String asset;
  final bool isSelect;
  final VoidCallback? onChanged;
  final DisplaySettings displaySettings;

  @override
  Widget build(BuildContext context) {
    final bool isDefault = asset.isEmpty;
    return GestureDetector(
      onTap: () async {
        if (!isSelect) {
          onChanged?.call();

          if ((displaySettings.boardImagePath == null ||
                  displaySettings.boardImagePath.isEmpty) &&
              !isDefault) {
            final bool isNavigationToolbarOpaque =
                DB().colorSettings.navigationToolbarBackgroundColor.alpha !=
                    0x00;
            final bool isMainToolbarOpaque =
                DB().colorSettings.mainToolbarBackgroundColor.alpha != 0x00;
            final bool isAnalysisToolbarOpaque =
                DB().colorSettings.analysisToolbarBackgroundColor.alpha != 0x00;

            if (isNavigationToolbarOpaque ||
                isMainToolbarOpaque ||
                isAnalysisToolbarOpaque) {
              final bool? result = await showDialog<bool>(
                context: context,
                builder: (BuildContext context) {
                  return AlertDialog(
                    title: Text(S.of(context).color),
                    content: Text(S.of(context).promptMakeToolbarTransparent),
                    actions: <Widget>[
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: Text(
                          S.of(context).no,
                          style: TextStyle(
                              fontSize: AppTheme.textScaler
                                  .scale(AppTheme.defaultFontSize)),
                        ),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        child: Text(
                          S.of(context).yes,
                          style: TextStyle(
                              fontSize: AppTheme.textScaler
                                  .scale(AppTheme.defaultFontSize)),
                        ),
                      ),
                    ],
                  );
                },
              );

              if (result ?? false) {
                Color currentColor =
                    DB().colorSettings.mainToolbarBackgroundColor;
                Color newColor = currentColor.withAlpha(0x00);
                DB().colorSettings = DB()
                    .colorSettings
                    .copyWith(mainToolbarBackgroundColor: newColor);

                currentColor =
                    DB().colorSettings.navigationToolbarBackgroundColor;
                newColor = currentColor.withAlpha(0x00);
                DB().colorSettings = DB()
                    .colorSettings
                    .copyWith(navigationToolbarBackgroundColor: newColor);

                currentColor =
                    DB().colorSettings.analysisToolbarBackgroundColor;
                newColor = currentColor.withAlpha(0x00);
                DB().colorSettings = DB()
                    .colorSettings
                    .copyWith(analysisToolbarBackgroundColor: newColor);
              }
            }
          }
        }
      },
      child: Stack(
        children: <Widget>[
          Container(
            decoration: BoxDecoration(
              color: isDefault ? DB().colorSettings.boardBackgroundColor : null,
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
