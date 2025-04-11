// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// toolbar_item.dart

part of '../game_toolbar.dart';

/// A Material Design "Game Toolbar Button".
///
/// A toolbar button is a label [child] displayed on a (zero elevation)
/// [Material] widget. The label's [Text] and [Icon] widgets are
/// displayed in the [style]'s [ButtonStyle.foregroundColor]. The
/// button reacts to touches by filling with the [style]'s
/// [ButtonStyle.backgroundColor].
///
/// The toolbar button's default style is defined by [defaultStyleOf].
/// The style of this toolbar button can be overridden with its [style]
/// parameter. The style of all toolbar buttons in a subtree can be
/// overridden with the [ToolbarItemTheme].
///
/// The static [styleFrom] method is a convenient way to create a
/// toolbar button [ButtonStyle] from simple values.
///
/// If the [onPressed] and [onLongPress] callbacks are null, then this
/// button will be disabled, it will not react to touch.
///
/// {@tool dartpad --template=stateless_widget_scaffold}
///
/// This sample shows how to render a disabled ToolbarItem, an enabled ToolbarItem
/// and lastly a ToolbarItem with gradient background.
///
/// ```dart
/// Widget build(BuildContext context) {
///   return Center(
///     child: Column(
///       mainAxisSize: MainAxisSize.min,
///       children: <Widget>[
///         ToolbarItem(
///            style: ToolbarItem.styleFrom(
///              textStyle: const TextStyle(fontSize: 20),
///            ),
///            onPressed: null,
///            child: const Text('Disabled'),
///         ),
///         const SizedBox(height: 30),
///         ToolbarItem(
///           style: ToolbarItem.styleFrom(
///             textStyle: const TextStyle(fontSize: 20),
///           ),
///           onPressed: () {},
///           child: const Text('Enabled'),
///         ),
///         const SizedBox(height: 30),
///         ClipRRect(
///           borderRadius: BorderRadius.circular(4),
///           child: Stack(
///             children: <Widget>[
///               Positioned.fill(
///                 child: Container(
///                   decoration: const BoxDecoration(
///                     gradient: LinearGradient(
///                       colors: <Color>[
///                         Color(0xFF0D47A1),
///                         Color(0xFF1976D2),
///                         Color(0xFF42A5F5),
///                       ],
///                     ),
///                   ),
///                 ),
///               ),
///               ToolbarItem(
///                 style: ToolbarItem.styleFrom(
///                   padding: const EdgeInsets.all(16.0),
///                   primary: Colors.white,
///                   textStyle: const TextStyle(fontSize: 20),
///                 ),
///                 onPressed: () {},
///                  child: const Text('Gradient'),
///               ),
///             ],
///           ),
///         ),
///       ],
///     ),
///   );
/// }
///
/// ```
/// {@end-tool}
class ToolbarItem extends ButtonStyleButton {
  /// Create a ToolbarItem.
  ///
  /// The [autofocus] and [clipBehavior] arguments must not be null.
  const ToolbarItem({
    super.key,
    required super.onPressed,
    super.onLongPress,
    super.style,
    super.focusNode,
    super.autofocus = false,
    super.clipBehavior = Clip.none,
    required Widget super.child,
    super.onHover,
    super.onFocusChange,
  });

  /// Create a toolbar button from a pair of widgets that serve as the button's
  /// [icon] and [label].
  ///
  /// The icon and label are arranged in a column.
  ///
  /// The [icon] and [label] arguments must not be null.
  factory ToolbarItem.icon({
    Key? key,
    required VoidCallback? onPressed,
    VoidCallback? onLongPress,
    ButtonStyle? style,
    FocusNode? focusNode,
    bool? autofocus,
    Clip? clipBehavior,
    required Widget icon,
    required Widget label,
  }) = _ToolbarItemWithIcon;

  /// A static convenience method that constructs a text button
  /// [ButtonStyle] given simple values.
  ///
  /// The [primary], and [onSurface] colors are used to create a
  /// [MaterialStateProperty] [ButtonStyle.foregroundColor] value in the same
  /// way that [defaultStyleOf] uses the [ColorScheme] colors with the same
  /// names. Specify a value for [primary] to specify the color of the button's
  /// text and icons as well as the overlay colors used to indicate the hover,
  /// focus, and pressed states. Use [onSurface] to specify the button's
  /// disabled text and icon color.
  ///
  /// Similarly, the [enabledMouseCursor] and [disabledMouseCursor]
  /// parameters are used to construct [ButtonStyle.mouseCursor].
  ///
  /// All of the other parameters are either used directly or used to
  /// create a [WidgetStateProperty] with a single value for all
  /// states.
  ///
  /// All parameters default to null. By default this method returns
  /// a [ButtonStyle] that doesn't override anything.
  ///
  /// For example, to override the default text and icon colors for a
  /// [ToolbarItem], as well as its overlay color, with all of the
  /// standard opacity adjustments for the pressed, focused, and
  /// hovered states, one could write:
  ///
  /// ```dart
  /// ToolbarItem(
  ///   style: ToolbarItem.styleFrom(primary: Colors.green),
  /// )
  /// ```
  static ButtonStyle styleFrom({
    Color? primary,
    Color? onSurface,
    Color? backgroundColor,
    Color? shadowColor,
    double? elevation,
    TextStyle? textStyle,
    EdgeInsetsGeometry? padding,
    Size? minimumSize,
    Size? fixedSize,
    Size? maximumSize,
    BorderSide? side,
    OutlinedBorder? shape,
    MouseCursor? enabledMouseCursor,
    MouseCursor? disabledMouseCursor,
    VisualDensity? visualDensity,
    MaterialTapTargetSize? tapTargetSize,
    Duration? animationDuration,
    bool? enableFeedback,
    AlignmentGeometry? alignment,
    InteractiveInkFeatureFactory? splashFactory,
  }) {
    final WidgetStateProperty<Color?>? foregroundColor =
        (onSurface == null && primary == null)
            ? null
            : _ToolbarItemDefaultForeground(primary, onSurface);
    final WidgetStateProperty<Color?>? overlayColor =
        (primary == null) ? null : _ToolbarItemDefaultOverlay(primary);
    final WidgetStateProperty<MouseCursor>? mouseCursor =
        (enabledMouseCursor == null && disabledMouseCursor == null)
            ? null
            : _ToolbarItemDefaultMouseCursor(
                enabledMouseCursor!,
                disabledMouseCursor!,
              );

    return ButtonStyle(
      textStyle: ButtonStyleButton.allOrNull<TextStyle>(textStyle),
      backgroundColor: ButtonStyleButton.allOrNull<Color>(backgroundColor),
      foregroundColor: foregroundColor,
      overlayColor: overlayColor,
      shadowColor: ButtonStyleButton.allOrNull<Color>(shadowColor),
      elevation: ButtonStyleButton.allOrNull<double>(elevation),
      padding: ButtonStyleButton.allOrNull<EdgeInsetsGeometry>(padding),
      minimumSize: ButtonStyleButton.allOrNull<Size>(minimumSize),
      fixedSize: ButtonStyleButton.allOrNull<Size>(fixedSize),
      maximumSize: ButtonStyleButton.allOrNull<Size>(maximumSize),
      side: ButtonStyleButton.allOrNull<BorderSide>(side),
      shape: ButtonStyleButton.allOrNull<OutlinedBorder>(shape),
      mouseCursor: mouseCursor,
      visualDensity: visualDensity,
      tapTargetSize: tapTargetSize,
      animationDuration: animationDuration,
      enableFeedback: enableFeedback,
      alignment: alignment,
      splashFactory: splashFactory,
    );
  }

  /// Defines the button's default appearance.
  ///
  /// The button [child]'s [Text] and [Icon] widgets are rendered with
  /// the [ButtonStyle]'s foreground color. The button's [InkWell] adds
  /// the style's overlay color when the button is focused, hovered
  /// or pressed. The button's background color becomes its [Material]
  /// color and is transparent by default.
  ///
  /// All of the ButtonStyle's defaults appear below.
  ///
  /// In this list "Theme.foo" is shorthand for
  /// `Theme.of(context).foo`. Color scheme values like
  /// "onSurface(0.38)" are shorthand for
  /// `onSurface.withValues(alpha: 0.38)`. [WidgetStateProperty] valued
  /// properties that are not followed by a subList have the same
  /// value for all states, otherwise the values are as specified for
  /// each state and "others" means all other states.
  ///
  /// The `textScaleFactor` is the value of
  /// `MediaQuery.of(context).textScaleFactor` and the names of the
  /// EdgeInsets constructors and `EdgeInsetsGeometry.lerp` have been
  /// abbreviated for readability.
  ///
  /// The color of the [ButtonStyle.textStyle] is not used, the
  /// [ButtonStyle.foregroundColor] color is used instead.
  ///
  /// * `textStyle` - Theme.textTheme.button
  /// * `backgroundColor` - transparent
  /// * `foregroundColor`
  ///   * disabled - Theme.colorScheme.onSurface(0.38)
  ///   * others - Theme.colorScheme.primary
  /// * `overlayColor`
  ///   * hovered - Theme.colorScheme.primary(0.04)
  ///   * focused or pressed - Theme.colorScheme.primary(0.12)
  /// * `shadowColor` - Theme.shadowColor
  /// * `elevation` - 0
  /// * `padding`
  ///   * `textScaleFactor <= 1` - all(8)
  ///   * `1 < textScaleFactor <= 2` - lerp(all(8), horizontal(8))
  ///   * `2 < textScaleFactor <= 3` - lerp(horizontal(8), horizontal(4))
  ///   * `3 < textScaleFactor` - horizontal(4)
  /// * `minimumSize` - Size(64, 36)
  /// * `fixedSize` - null
  /// * `maximumSize` - Size.infinite
  /// * `side` - null
  /// * `shape` - RoundedRectangleBorder(borderRadius: BorderRadius.circular(4))
  /// * `mouseCursor`
  ///   * disabled - SystemMouseCursors.forbidden
  ///   * others - SystemMouseCursors.click
  /// * `visualDensity` - theme.visualDensity
  /// * `tapTargetSize` - theme.materialTapTargetSize
  /// * `animationDuration` - kThemeChangeDuration
  /// * `enableFeedback` - true
  /// * `alignment` - Alignment.center
  /// * `splashFactory` - InkRipple.splashFactory
  ///
  /// The default padding values for the [ToolbarItem.icon] factory are slightly different:
  ///
  /// * `padding`
  ///   * `textScaleFactor <= 1` - all(8)
  ///   * `1 < textScaleFactor <= 2 `- lerp(all(8), horizontal(4))
  ///   * `2 < textScaleFactor` - horizontal(4)
  ///
  /// The default value for `side`, which defines the appearance of the button's
  /// outline, is null. That means that the outline is defined by the button
  /// shape's [OutlinedBorder.side]. Typically the default value of an
  /// [OutlinedBorder]'s side is [BorderSide.none], so an outline is not drawn.
  @override
  ButtonStyle defaultStyleOf(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;

    const TextScaler scaler = TextScaler.noScaling;

    const double fontSize = 1.0;
    final double scaledFontSize = scaler.scale(fontSize);
    final double scaleFactor = scaledFontSize / fontSize;

    final EdgeInsetsGeometry scaledPadding = ButtonStyleButton.scaledPadding(
      const EdgeInsets.all(8),
      const EdgeInsets.symmetric(horizontal: 8),
      const EdgeInsets.symmetric(horizontal: 4),
      scaleFactor,
    );

    return styleFrom(
      primary: colorScheme.primary,
      onSurface: colorScheme.onSurface,
      backgroundColor: Colors.transparent,
      shadowColor: theme.shadowColor,
      elevation: 0,
      textStyle: theme.textTheme.labelLarge,
      padding: scaledPadding,
      minimumSize: const Size(64, 36),
      maximumSize: Size.infinite,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(4)),
      ),
      enabledMouseCursor: SystemMouseCursors.click,
      disabledMouseCursor: SystemMouseCursors.forbidden,
      visualDensity: theme.visualDensity,
      tapTargetSize: theme.materialTapTargetSize,
      animationDuration: kThemeChangeDuration,
      enableFeedback: true,
      alignment: Alignment.center,
      splashFactory: InkRipple.splashFactory,
    );
  }

  /// Returns the [ToolbarItemThemeData.style] of the closest
  /// [ToolbarItemTheme] ancestor.
  @override
  ButtonStyle? themeStyleOf(BuildContext context) {
    return ToolbarItemTheme.of(context).style;
  }
}

@immutable
class _ToolbarItemDefaultForeground extends WidgetStateProperty<Color?> {
  _ToolbarItemDefaultForeground(this.primary, this.onSurface);

  final Color? primary;
  final Color? onSurface;

  @override
  Color? resolve(Set<WidgetState> states) {
    if (states.contains(WidgetState.disabled)) {
      return onSurface?.withValues(alpha: 0.38);
    }
    return primary;
  }

  @override
  String toString() {
    return '{disabled: ${onSurface?.withValues(alpha: 0.38)}, otherwise: $primary}';
  }
}

@immutable
class _ToolbarItemDefaultOverlay extends WidgetStateProperty<Color?> {
  _ToolbarItemDefaultOverlay(this.primary);

  final Color primary;

  @override
  Color? resolve(Set<WidgetState> states) {
    if (states.contains(WidgetState.hovered)) {
      return primary.withValues(alpha: 0.04);
    }
    if (states.contains(WidgetState.focused) ||
        states.contains(WidgetState.pressed)) {
      return primary.withValues(alpha: 0.12);
    }
    return null;
  }

  @override
  String toString() {
    return '{hovered: ${primary.withValues(alpha: 0.04)}, focused,pressed: ${primary.withValues(alpha: 0.12)}, otherwise: null}';
  }
}

@immutable
class _ToolbarItemDefaultMouseCursor extends WidgetStateProperty<MouseCursor>
    with Diagnosticable {
  _ToolbarItemDefaultMouseCursor(this.enabledCursor, this.disabledCursor);

  final MouseCursor enabledCursor;
  final MouseCursor disabledCursor;

  @override
  MouseCursor resolve(Set<WidgetState> states) {
    if (states.contains(WidgetState.disabled)) {
      return disabledCursor;
    }
    return enabledCursor;
  }
}

class _ToolbarItemWithIcon extends ToolbarItem {
  _ToolbarItemWithIcon({
    super.key,
    required super.onPressed,
    super.onLongPress,
    super.style,
    super.focusNode,
    bool? autofocus,
    Clip? clipBehavior,
    required Widget icon,
    required Widget label,
  }) : super(
          autofocus: autofocus ?? false,
          clipBehavior: clipBehavior ?? Clip.none,
          child: _ToolbarItemChild(
            icon: icon,
            label: label,
            key: const Key('toolbar_item_child'),
          ),
        );

  static const TextScaler scaler = TextScaler.noScaling;

  static const double fontSize = 1.0;
  final double scaleFactor = scaler.scale(fontSize) / fontSize;

  @override
  ButtonStyle defaultStyleOf(BuildContext context) {
    final EdgeInsetsGeometry scaledPadding = ButtonStyleButton.scaledPadding(
      const EdgeInsets.all(8),
      const EdgeInsets.symmetric(horizontal: 4),
      const EdgeInsets.symmetric(horizontal: 4),
      scaleFactor,
    );
    return super.defaultStyleOf(context).copyWith(
          padding: WidgetStateProperty.all<EdgeInsetsGeometry>(scaledPadding),
        );
  }
}

class _ToolbarItemChild extends StatelessWidget {
  const _ToolbarItemChild({
    required this.label,
    required this.icon,
    super.key,
  });

  final Widget label;
  final Widget icon;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('toolbar_item_child_column'),
      // TODO: [Calcitem] Replace with a Row for horizontal icon + text
      children: <Widget>[icon, label],
    );
  }
}
