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

part of 'package:sanmill/general_settings/widgets/general_settings_page.dart';

class _SkillLevelPicker extends StatefulWidget {
  const _SkillLevelPicker();

  @override
  State<_SkillLevelPicker> createState() => _SkillLevelPickerState();
}

class _SkillLevelPickerState extends State<_SkillLevelPicker> {
  late FixedExtentScrollController _controller;

  late int _level;

  @override
  void initState() {
    super.initState();
    _level = DB().generalSettings.skillLevel;
    _controller = FixedExtentScrollController(initialItem: _level - 1);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Box<GeneralSettings>>(
      valueListenable: DB().listenGeneralSettings,
      builder: (BuildContext context, Box<GeneralSettings> box, _) {
        final GeneralSettings generalSettings = box.get(
          DB.generalSettingsKey,
          defaultValue: const GeneralSettings(),
        )!;
        return AlertDialog(
          title: Text(
            S.of(context).skillLevel,
            style: AppTheme.dialogTitleTextStyle,
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 150),
            child: CupertinoPicker(
              scrollController: _controller,
              itemExtent: 44,
              children: List<Widget>.generate(Constants.highestSkillLevel,
                  (int level) => Center(child: Text('${level + 1}'))),
              onSelectedItemChanged: (int value) {
                _level = value + 1;
              },
            ),
          ),
          actions: <Widget>[
            if (EnvironmentConfig.test == false)
              TextButton(
                child: Text(
                  S.of(context).cancel,
                  style: TextStyle(
                      fontSize:
                          AppTheme.textScaler.scale(AppTheme.defaultFontSize)),
                ),
                onPressed: () {
                  Navigator.of(context).pop();

                  if (!kIsWeb &&
                      (Platform.isWindows ||
                          Platform.isLinux ||
                          Platform.isMacOS)) {
                    rootScaffoldMessengerKey.currentState!.showSnackBarClear(
                        S.of(context).youCanUseMouseWheelInPicker);
                  }
                },
              ),
            TextButton(
              child: Text(
                S.of(context).confirm,
                style: TextStyle(
                    fontSize:
                        AppTheme.textScaler.scale(AppTheme.defaultFontSize)),
              ),
              onPressed: () {
                DB().generalSettings =
                    generalSettings.copyWith(skillLevel: _level);

                if (DB().generalSettings.skillLevel > 15 &&
                    DB().generalSettings.moveTime < 10) {
                  rootScaffoldMessengerKey.currentState!.showSnackBarClear(
                      S.of(context).noteActualDifficultyLevelMayBeLimited);
                }

                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }
}
