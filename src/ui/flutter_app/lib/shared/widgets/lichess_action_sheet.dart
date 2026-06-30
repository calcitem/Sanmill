// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../generated/intl/l10n.dart';

const double _kMaterialPopupMenuMaxWidth = 500;

Future<T?> showLichessActionSheet<T>({
  required BuildContext context,
  required List<LichessActionSheetAction> actions,
  Widget? title,
  Key? sheetKey,
  bool isDismissible = true,
}) {
  assert(actions.isNotEmpty, 'Action sheet must contain at least one action.');

  if (Theme.of(context).platform == TargetPlatform.iOS) {
    return _showCupertinoActionSheet<T>(
      context: context,
      title: title,
      actions: actions,
      sheetKey: sheetKey,
      isDismissible: isDismissible,
    );
  }
  return _showMaterialActionSheet<T>(
    context: context,
    title: title,
    actions: actions,
    sheetKey: sheetKey,
    isDismissible: isDismissible,
  );
}

Future<T?> _showCupertinoActionSheet<T>({
  required BuildContext context,
  required List<LichessActionSheetAction> actions,
  required bool isDismissible,
  Key? sheetKey,
  Widget? title,
}) {
  return showCupertinoModalPopup<T>(
    context: context,
    barrierDismissible: isDismissible,
    builder: (BuildContext context) {
      return CupertinoActionSheet(
        key: sheetKey,
        title: title,
        actions: <Widget>[
          for (final LichessActionSheetAction action in actions)
            Builder(
              builder: (BuildContext actionContext) {
                return CupertinoActionSheetAction(
                  key: action.key,
                  onPressed: () => _handleActionPressed(actionContext, action),
                  isDestructiveAction: action.isDestructiveAction,
                  isDefaultAction: action.isDefaultAction,
                  child: action.makeLabel(actionContext),
                );
              },
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.of(context).pop(),
          child: Text(S.of(context).cancel),
        ),
      );
    },
  );
}

Future<T?> _showMaterialActionSheet<T>({
  required BuildContext context,
  required List<LichessActionSheetAction> actions,
  required bool isDismissible,
  Widget? title,
  Key? sheetKey,
}) {
  final double screenWidth = MediaQuery.sizeOf(context).width;

  return showDialog<T>(
    context: context,
    barrierDismissible: isDismissible,
    builder: (BuildContext context) {
      final ThemeData theme = Theme.of(context);
      final ColorScheme colorScheme = theme.colorScheme;
      final TextStyle actionTextStyle =
          (theme.textTheme.titleMedium ?? const TextStyle(fontSize: 18))
              .copyWith(color: colorScheme.onSurface);
      return Dialog(
        key: sheetKey,
        backgroundColor:
            theme.dialogTheme.backgroundColor ?? colorScheme.surfaceContainer,
        child: SizedBox(
          width: math.min(screenWidth, _kMaterialPopupMenuMaxWidth),
          child: IconTheme.merge(
            data: IconThemeData(color: colorScheme.onSurfaceVariant),
            child: DefaultTextStyle.merge(
              style: TextStyle(color: colorScheme.onSurface),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (title != null)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Center(child: title),
                      ),
                    for (int index = 0; index < actions.length; index++)
                      _MaterialActionSheetTile(
                        action: actions[index],
                        textStyle: actionTextStyle,
                        isFirst: index == 0,
                        isLast: index == actions.length - 1,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

class LichessActionSheetAction {
  LichessActionSheetAction({
    required this.makeLabel,
    required this.onPressed,
    this.key,
    this.dismissOnPress = true,
    this.leading,
    this.trailing,
    this.isDestructiveAction = false,
    this.isDefaultAction = false,
  });

  final Key? key;
  final Widget Function(BuildContext context) makeLabel;
  final VoidCallback onPressed;
  final bool dismissOnPress;
  final Widget? leading;
  final Widget? trailing;
  final bool isDestructiveAction;
  final bool isDefaultAction;
}

class _MaterialActionSheetTile extends StatelessWidget {
  const _MaterialActionSheetTile({
    required this.action,
    required this.textStyle,
    required this.isFirst,
    required this.isLast,
  });

  final LichessActionSheetAction action;
  final TextStyle textStyle;
  final bool isFirst;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: action.key,
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(isFirst ? 28 : 0),
        bottom: Radius.circular(isLast ? 28 : 0),
      ),
      onTap: () => _handleActionPressed(context, action),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: <Widget>[
            if (action.leading != null) ...<Widget>[
              action.leading!,
              const SizedBox(width: 15),
            ],
            Expanded(
              child: DefaultTextStyle(
                style: textStyle,
                textAlign: action.leading != null
                    ? TextAlign.start
                    : TextAlign.center,
                child: action.makeLabel(context),
              ),
            ),
            if (action.trailing != null) ...<Widget>[
              const SizedBox(width: 10),
              action.trailing!,
            ],
          ],
        ),
      ),
    );
  }
}

void _handleActionPressed(
  BuildContext context,
  LichessActionSheetAction action,
) {
  if (!action.dismissOnPress) {
    action.onPressed();
    return;
  }

  Navigator.of(context).pop();
  WidgetsBinding.instance.addPostFrameCallback((_) => action.onPressed());
}
