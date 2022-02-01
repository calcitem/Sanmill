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

part of '../settings.dart';

enum _SettingsTileType { standard, color, switchTile }

// TODO: [Leptopoda] Maybe add link list tile as it needs a separate icon
class SettingsListTile extends StatelessWidget {
  const SettingsListTile({
    Key? key,
    required this.titleString,
    required VoidCallback onTap,
    this.subtitleString,
    this.trailingString,
  })  : _type = _SettingsTileType.standard,
        _switchValue = null,
        _callback = onTap,
        _colorValue = null,
        super(key: key);

  const SettingsListTile.color({
    Key? key,
    required this.titleString,
    required Color value,
    required ValueChanged<Color> onChanged,
    this.subtitleString,
  })  : _type = _SettingsTileType.color,
        _switchValue = null,
        _callback = onChanged,
        trailingString = null,
        _colorValue = value,
        super(key: key);

  const SettingsListTile.switchTile({
    Key? key,
    required this.titleString,
    required bool value,
    required ValueChanged<bool> onChanged,
    this.subtitleString,
  })  : _type = _SettingsTileType.switchTile,
        _switchValue = value,
        _callback = onChanged,
        _colorValue = null,
        trailingString = null,
        super(key: key);

  final String titleString;
  final String? subtitleString;
  final String? trailingString;

  final _SettingsTileType _type;
  final bool? _switchValue;
  final Color? _colorValue;
  final Function _callback;

  Widget get title => Text(
        titleString,
        style: AppTheme.listTileTitleStyle,
      );
  Widget? get subTitle => subtitleString != null
      ? Text(subtitleString!, style: AppTheme.listTileSubtitleStyle)
      : null;

  @override
  Widget build(BuildContext context) {
    switch (_type) {
      case _SettingsTileType.switchTile:
        return SwitchListTile(
          value: _switchValue!,
          onChanged: (val) => _callback(val),
          title: title,
          subtitle: subTitle,
        );
      case _SettingsTileType.standard:
        final Widget trailing;
        if (trailingString != null) {
          trailing = Text(
            trailingString!,
            style: AppTheme.listTileSubtitleStyle,
          );
        } else {
          trailing = const Icon(
            FluentIcons.chevron_right_24_regular,
            color: AppTheme.listTileSubtitleColor,
          );
        }

        return ListTile(
          title: title,
          subtitle: subTitle,
          trailing: trailing,
          onTap: () => _callback(),
        );

      case _SettingsTileType.color:
        return ListTile(
          title: title,
          subtitle: subTitle,
          trailing: Text(
            _colorValue!.value.toRadixString(16),
            style: TextStyle(backgroundColor: _colorValue),
          ),
          onTap: () => showDialog(
            context: context,
            builder: (_) => _ColorPickerAlert(
              title: titleString,
              value: _colorValue!,
              onChanged: (val) => _callback(val),
            ),
          ),
        );
    }
  }
}

class _ColorPickerAlert extends StatefulWidget {
  const _ColorPickerAlert({
    Key? key,
    required this.value,
    required this.title,
    required this.onChanged,
  }) : super(key: key);

  final Color value;
  final String title;
  final Function(Color) onChanged;

  @override
  _ColorPickerAlertState createState() => _ColorPickerAlertState();
}

class _ColorPickerAlertState extends State<_ColorPickerAlert> {
  late Color pickedColor;

  void _changeColor(Color color) => setState(() => pickedColor = color);

  @override
  void initState() {
    pickedColor = widget.value;
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        S.of(context).pick(widget.title),
        style: AppTheme.dialogTitleTextStyle,
      ),
      content: ColorPicker(
        pickerColor: pickedColor,
        onColorChanged: _changeColor,
      ),
      actions: <Widget>[
        TextButton(
          child: Text(S.of(context).confirm),
          onPressed: () {
            logger.v("[config] pickerColor.value: ${pickedColor.value}");
            widget.onChanged(pickedColor);
            Navigator.pop(context);
          },
        ),
        TextButton(
          child: Text(S.of(context).cancel),
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }
}
