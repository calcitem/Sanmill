/*
  This file is part of Sanmill.
  Copyright (C) 2019-2021 The Sanmill developers (see AUTHORS file)

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

part of 'package:sanmill/screens/personalization_settings/personalization_settings_page.dart';

class _ColorSelectorListTile extends StatelessWidget {
  const _ColorSelectorListTile({
    Key? key,
    required this.value,
    required this.title,
    required this.onChanged,
  }) : super(key: key);

  final Color value;
  final String title;
  final Function(Color) onChanged;

  Future<void> showColorDialog(BuildContext context) async {
    // show the dialog
    showDialog(
      context: context,
      builder: (_) => _ColorPickerAlert(
        title: title,
        value: value,
        onChanged: onChanged,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SettingsListTile(
      titleString: title,
      trailingColor: value,
      onTap: () => showColorDialog(context),
    );
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

  void changeColor(Color color) => setState(() => pickedColor = color);

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
      content: SingleChildScrollView(
        child: ColorPicker(
          pickerColor: pickedColor,
          onColorChanged: changeColor,
        ),
      ),
      actions: <Widget>[
        TextButton(
          child: Text(
            S.of(context).confirm,
          ),
          onPressed: () {
            debugPrint("[config] colorPicker.value: $pickedColor");
            widget.onChanged(pickedColor);
            Navigator.pop(context);
          },
        ),
        TextButton(
          child: Text(
            S.of(context).cancel,
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }
}
