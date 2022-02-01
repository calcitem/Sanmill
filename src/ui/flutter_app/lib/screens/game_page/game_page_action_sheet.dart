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

part of './game_page.dart';

@visibleForTesting
class GamePageActionSheet extends StatelessWidget {
  const GamePageActionSheet({
    Key? key,
    required this.child,
    this.textColor = AppTheme.gamePageActionSheetTextColor,
  }) : super(key: key);

  final Color textColor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme.apply(
      displayColor: textColor,
      bodyColor: textColor,
    );

    final dialogTheme = DialogTheme.of(context).copyWith(
      backgroundColor: Colors.transparent,
    );

    final buttonStyle = TextButtonThemeData(
      style: TextButton.styleFrom(
        primary: textColor,
      ),
    );

    return Theme(
      data: theme.copyWith(
        primaryColor: textColor,
        textTheme: textTheme,
        dialogTheme: dialogTheme,
        textButtonTheme: buttonStyle,
      ),
      child: DefaultTextStyle(
        style: textTheme.headline6!,
        child: child,
      ),
    );
  }
}

@visibleForTesting
class GamePageDialog extends StatelessWidget {
  const GamePageDialog({
    Key? key,
    this.children = const <Widget>[],
    required this.semanticLabel,
  }) : super(key: key);

  final List<Widget> children;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    // The paddingScaleFactor is used to adjust the padding of Dialog
    // children.
    final double paddingScaleFactor =
        _paddingScaleFactor(MediaQuery.of(context).textScaleFactor);

    final contentWidget = Builder(
      builder: (context) => DefaultTextStyle(
        style: Theme.of(context)
            .textTheme
            .headline6!
            .copyWith(color: AppTheme.gamePageActionSheetTextColor),
        textAlign: TextAlign.center,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(0.0, 12.0, 0.0, 16.0) *
              paddingScaleFactor,
          child: ListBody(children: children),
        ),
      ),
    );

    final dialogChild = IntrinsicWidth(
      stepWidth: 56.0,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 280.0),
        child: contentWidget,
      ),
    );

    return GamePageActionSheet(
      child: Dialog(
        child: Semantics(
          scopesRoute: true,
          explicitChildNodes: true,
          namesRoute: true,
          label: semanticLabel,
          child: dialogChild,
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
