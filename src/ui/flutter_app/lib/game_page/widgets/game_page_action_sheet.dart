// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// game_page_action_sheet.dart

part of 'game_page.dart';

@visibleForTesting
class GamePageActionSheet extends StatelessWidget {
  const GamePageActionSheet({
    super.key,
    required this.child,
    this.textColor = AppTheme.gamePageActionSheetTextColor,
  });

  final Color textColor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final TextTheme textTheme = theme.textTheme.apply(
      displayColor: textColor,
      bodyColor: textColor,
    );

    final DialogThemeData dialogTheme = DialogTheme.of(context).copyWith(
      backgroundColor: Colors.transparent,
    );

    final TextButtonThemeData buttonStyle = TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: textColor,
      ),
    );

    return Theme(
      key: const Key('game_page_action_sheet_theme'),
      data: theme.copyWith(
        primaryColor: textColor,
        textTheme: textTheme,
        dialogTheme: dialogTheme,
        textButtonTheme: buttonStyle,
      ),
      child: DefaultTextStyle(
        key: const Key('game_page_action_sheet_default_text_style'),
        style: textTheme.titleLarge!,
        child: child,
      ),
    );
  }
}

@visibleForTesting
class GamePageDialog extends StatelessWidget {
  const GamePageDialog({
    super.key,
    this.children = const <Widget>[],
    required this.semanticLabel,
  });

  final List<Widget> children;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    // The paddingScaleFactor is used to adjust the padding of Dialog
    // children.
    final double paddingScaleFactor =
        _paddingScaleFactor(TextScaler.noScaling.scale(1.0));

    final Builder contentWidget = Builder(
      key: const Key('game_page_dialog_builder'),
      builder: (BuildContext context) => DefaultTextStyle(
        key: const Key('game_page_dialog_default_text_style'),
        style: Theme.of(context)
            .textTheme
            .titleLarge!
            .copyWith(color: AppTheme.gamePageActionSheetTextColor),
        textAlign: TextAlign.center,
        child: SingleChildScrollView(
          key: const Key('game_page_dialog_single_child_scroll_view'),
          padding: const EdgeInsets.fromLTRB(0.0, 12.0, 0.0, 16.0) *
              paddingScaleFactor,
          child: ListBody(
            key: const Key('game_page_dialog_list_body'),
            children: children,
          ),
        ),
      ),
    );

    final IntrinsicWidth dialogChild = IntrinsicWidth(
      key: const Key('game_page_dialog_intrinsic_width'),
      stepWidth: 56.0,
      child: ConstrainedBox(
        key: const Key('game_page_dialog_constrained_box'),
        constraints: const BoxConstraints(minWidth: 280.0),
        child: contentWidget,
      ),
    );

    return GamePageActionSheet(
      key: const Key('game_page_dialog_action_sheet'),
      child: Dialog(
        key: const Key('game_page_dialog'),
        child: Container(
          key: const Key('game_page_dialog_container'),
          decoration: AppTheme.dialogDecoration,
          child: Semantics(
            key: const Key('game_page_dialog_semantics'),
            scopesRoute: true,
            explicitChildNodes: true,
            namesRoute: true,
            label: semanticLabel,
            child: dialogChild,
          ),
        ),
      ),
    );
  }
}

double _paddingScaleFactor(double textScaleFactor) {
  final double clampedTextScaleFactor = textScaleFactor.clamp(1.0, 2.0);
  // The final padding scale factor is clamped between 1/3 and 1. For example,
  // a non-scaled padding of 24 will produce a padding between 24 and 8.
  return lerpDouble(1.0, 1.0 / 3.0, clampedTextScaleFactor - 1.0)!;
}
