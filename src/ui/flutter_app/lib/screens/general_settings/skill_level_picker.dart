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

part of 'package:sanmill/screens/general_settings/general_settings_page.dart';

class _SkillLevelPicker extends StatefulWidget {
  const _SkillLevelPicker({Key? key}) : super(key: key);

  @override
  State<_SkillLevelPicker> createState() => _SkillLevelPickerState();
}

class _SkillLevelPickerState extends State<_SkillLevelPicker> {
  late FixedExtentScrollController _controller;

  @override
  void initState() {
    super.initState();
    _controller = FixedExtentScrollController(
        initialItem: DB().generalSettings.skillLevel - 1);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = Theme.of(context).textTheme.bodyText1!.fontSize!;

    return Semantics(
      label: S.of(context).skillLevel,
      child: ValueListenableBuilder(
        valueListenable: DB().listenGeneralSettings,
        builder: (context, Box<GeneralSettings> box, _) {
          final GeneralSettings generalSettings = box.get(
            DB.generalSettingsKey,
            defaultValue: const GeneralSettings(),
          )!;

          return CupertinoPicker(
            scrollController: _controller,
            itemExtent: size + 12,
            children: List.generate(
                Constants.topSkillLevel, (index) => Text('${index + 1}')),
            onSelectedItemChanged: (numb) {
              DB().generalSettings =
                  generalSettings.copyWith(skillLevel: numb + 1);
            },
          );
        },
      ),
    );
  }
}
