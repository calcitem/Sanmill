// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// settings_list_tile.dart

part of 'settings.dart';

const int kSettingsTileTitleMaxLines = 3;

enum _SettingsTileType { standard, color, switchTile }

// Standard, color, and switch tiles cover the existing settings variants; link
// entries reuse the standard tile so the trailing chevron remains consistent.
class SettingsListTile extends StatelessWidget {
  const SettingsListTile({
    super.key,
    required this.titleString,
    required VoidCallback onTap,
    this.subtitleString,
    this.trailingString,
    this.leading,
  }) : _type = _SettingsTileType.standard,
       _switchValue = null,
       _switchCallback = null,
       _colorCallback = null,
       _standardCallback = onTap,
       _colorValue = null;

  const SettingsListTile.color({
    super.key,
    required this.titleString,
    required Color value,
    required ValueChanged<Color> onChanged,
    this.subtitleString,
    this.leading,
  }) : _type = _SettingsTileType.color,
       _switchValue = null,
       _colorValue = value,
       _switchCallback = null,
       _colorCallback = onChanged,
       _standardCallback = null,
       trailingString = null;

  const SettingsListTile.switchTile({
    super.key,
    required this.titleString,
    required bool value,
    required ValueChanged<bool> onChanged,
    this.subtitleString,
    this.leading,
  }) : _type = _SettingsTileType.switchTile,
       _switchValue = value,
       _colorValue = null,
       _switchCallback = onChanged,
       _colorCallback = null,
       _standardCallback = null,
       trailingString = null;

  final String titleString;
  final String? subtitleString;
  final String? trailingString;
  final Widget? leading;

  final _SettingsTileType _type;
  final bool? _switchValue;
  final Color? _colorValue;
  final ValueChanged<bool>? _switchCallback;
  final ValueChanged<Color>? _colorCallback;
  final VoidCallback? _standardCallback;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;

    final TextStyle titleStyle =
        theme.textTheme.bodyLarge?.copyWith(
          color: colorScheme.onSurface,
          letterSpacing: 0,
        ) ??
        AppStyles.tileTitle.copyWith(color: colorScheme.onSurface);

    final TextStyle subtitleStyle =
        theme.textTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurfaceVariant.withValues(
            alpha: AppStyles.subtitleOpacity,
          ),
          letterSpacing: 0,
        ) ??
        AppStyles.tileSubtitle.copyWith(
          color: colorScheme.onSurfaceVariant.withValues(
            alpha: AppStyles.subtitleOpacity,
          ),
        );

    final Widget title = Text(
      titleString,
      maxLines: kSettingsTileTitleMaxLines,
      overflow: TextOverflow.ellipsis,
      style: titleStyle,
    );
    final Widget? subTitle = subtitleString != null
        ? Text(subtitleString!, maxLines: 5, style: subtitleStyle)
        : null;

    switch (_type) {
      case _SettingsTileType.switchTile:
        return ListTile(
          leading: leading,
          title: title,
          subtitle: subTitle,
          trailing: Switch.adaptive(
            value: _switchValue!,
            onChanged: _switchCallback,
            padding: const EdgeInsetsDirectional.only(start: 8),
          ),
        );
      case _SettingsTileType.standard:
        Widget? trailing;
        if (trailingString != null) {
          trailing = ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width * 0.25,
            ),
            child: Text(
              trailingString!,
              style: subtitleStyle,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              maxLines: kSettingsTileTitleMaxLines,
            ),
          );
        } else if (theme.platform == TargetPlatform.iOS) {
          trailing = Icon(
            Icons.chevron_right,
            size: 20,
            color: colorScheme.onSurfaceVariant.withValues(
              alpha: AppStyles.subtitleOpacity,
            ),
          );
        }

        return Semantics(
          container: true,
          button: true,
          label: trailingString == null
              ? titleString
              : '$titleString: $trailingString',
          excludeSemantics: true,
          child: ListTile(
            leading: leading,
            title: title,
            subtitle: subTitle,
            trailing: trailing,
            onTap: _standardCallback,
          ),
        );

      case _SettingsTileType.color:
        return ListTile(
          leading: leading,
          title: title,
          subtitle: subTitle,
          trailing: DecoratedBox(
            decoration: BoxDecoration(
              color: _colorValue,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.7),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              child: Text(
                _colorValue!.toHexString(),
                style: TextStyle(
                  color: _colorValue.computeLuminance() > 0.5
                      ? Colors.black
                      : Colors.white,
                ),
              ),
            ),
          ),
          onTap: () => showDialog(
            context: context,
            barrierDismissible: EnvironmentConfig.test == true,
            builder: (_) => _ColorPickerAlert(
              title: titleString,
              value: _colorValue,
              onChanged: _colorCallback!,
            ),
          ),
        );
    }
  }
}

class _ColorPickerAlert extends StatefulWidget {
  const _ColorPickerAlert({
    required this.value,
    required this.title,
    required this.onChanged,
  });

  final Color value;
  final String title;
  final ValueChanged<Color> onChanged;

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
      key: const Key('color_picker_alert_dialog'),
      title: DB().displaySettings.fontScale == 1.0
          ? Text(
              S.of(context).pick(widget.title),
              style: AppTheme.dialogTitleTextStyle,
            )
          : null,
      content: SingleChildScrollView(
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 1.0,
          child: SlidePicker(
            key: const Key('color_picker_slide_picker'),
            pickerColor: pickedColor,
            labelTypes: DB().displaySettings.fontScale == 1.0
                ? const <ColorLabelType>[
                    ColorLabelType.hex,
                    ColorLabelType.rgb,
                    ColorLabelType.hsv,
                    ColorLabelType.hsl,
                  ]
                : const <ColorLabelType>[],
            onColorChanged: _changeColor,
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          key: const Key('color_picker_confirm_button'),
          child: Text(
            S.of(context).confirm,
            style: TextStyle(
              fontSize: AppTheme.textScaler.scale(AppTheme.defaultFontSize),
            ),
          ),
          onPressed: () {
            logger.t("[config] pickerColor.value: $pickedColor");
            widget.onChanged(pickedColor);
            Navigator.pop(context);
          },
        ),
        TextButton(
          key: const Key('color_picker_cancel_button'),
          child: Text(
            S.of(context).cancel,
            style: TextStyle(
              fontSize: AppTheme.textScaler.scale(AppTheme.defaultFontSize),
            ),
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }
}
