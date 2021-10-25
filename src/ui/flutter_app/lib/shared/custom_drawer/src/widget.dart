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

part of '../custom_drawer.dart';

/// CustomDrawer Widget
///
/// The widget laying out the custom drawer
class CustomDrawer extends StatefulWidget {
  const CustomDrawer({
    Key? key,
    required this.child,
    required this.items,
    required this.header,
    this.controller,
    this.disabledGestures = false,
  }) : super(key: key);

  /// Child widget. (Usually awidget that represents the main screen)
  final Widget child;

  /// controller that controls the widget state. By default a new controller will be geneerated.
  final CustomDrawerController? controller;

  /// disables the gestures.
  final bool disabledGestures;

  /// items the drawer holds
  final List<CustomDrawerItem> items;

  /// header widget of the drawer
  final Widget header;

  @override
  _CustomDrawerState createState() => _CustomDrawerState();
}

class _CustomDrawerState extends State<CustomDrawer>
    with SingleTickerProviderStateMixin {
  // TODO: [Leptopoda] maybe integrate the animation controller into the drawerController
  late final CustomDrawerController _controller;
  late final AnimationController _animationController;
  late final Animation<Offset> _childSlideAnimation;
  late final Animation<Offset> _overlaySlideAnimation;
  late double _offsetValue;
  late Offset _freshPosition;
  late Offset _startPosition;
  bool _captured = false;

  static const _duration = Duration(milliseconds: 250);
  static const _slideThreshold = 0.5;
  static const _openRatio = 0.75;
  static const _overlayRadius = 28.0;

  @override
  void initState() {
    super.initState();

    _controller = widget.controller ?? CustomDrawerController();
    _controller.addListener(_handleControllerChanged);

    _animationController = AnimationController(
      vsync: this,
      duration: _duration,
      value: _controller.value.visible ? 1 : 0,
    );

    _childSlideAnimation = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(_openRatio, 0),
    ).animate(
      _animationController,
    );

    _overlaySlideAnimation = Tween<Offset>(
      begin: const Offset(-1, 0),
      end: Offset.zero,
    ).animate(
      _animationController,
    );
  }

  @override
  Widget build(BuildContext context) {
    final _drawer = Align(
      alignment: AlignmentDirectional.centerStart,
      child: FractionallySizedBox(
        widthFactor: _openRatio,
        child: Material(
          color: LocalDatabaseService.colorSettings.drawerColor,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              widget.header,
              Divider(height: 1, color: AppTheme.drawerDividerColor),
              ListView.builder(
                padding: const EdgeInsets.only(top: 4.0),
                physics: const BouncingScrollPhysics(),
                shrinkWrap: true,
                itemCount: widget.items.length,
                itemBuilder: _buildItem,
              ),
            ],
          ),
        ),
      ),
    );

    // TODO: [Leptopoda] move the drawer overlay into the main scaffold so we don't need to deal with positioning
    final rtl = Directionality.of(context) == TextDirection.rtl;

    /// menu and arrow icon animation overlay
    final _drawerOverlay = IconButton(
      icon: AnimatedIcon(
        icon: AnimatedIcons.arrow_menu,
        color: AppTheme.drawerAnimationIconColor,
        progress: ReverseAnimation(_animationController),
      ),
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + (rtl ? 25 : 10),
      ),
      tooltip: S.of(context).mainMenu,
      onPressed: () => _controller.toggleDrawer(),
    );

    final _mainView = SlideTransition(
      position: _childSlideAnimation,
      textDirection: Directionality.of(context),
      child: ValueListenableBuilder<CustomDrawerValue>(
        valueListenable: _controller,
        // TODO: [Leptopdoa] why isn't it working with GestureDetector?
        builder: (_, value, child) => InkWell(
          onTap: _controller.hideDrawer,
          focusColor: Colors.transparent,
          child: IgnorePointer(
            ignoring: value.visible,
            child: child,
          ),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: LocalDatabaseService.colorSettings.drawerColor,
            boxShadow: [
              BoxShadow(
                color: AppTheme.drawerBoxerShadowColor,
                blurRadius: 24,
              ),
            ],
          ),
          child: Stack(
            children: <Widget>[
              widget.child,
              _drawerOverlay,
            ],
          ),
        ),
      ),
    );

    // TODO: [Leptopdoa] should the geture also apply to the drawer?
    return Stack(
      children: <Widget>[
        _drawer,
        GestureDetector(
          onHorizontalDragStart:
              widget.disabledGestures ? null : _handleDragStart,
          onHorizontalDragUpdate:
              widget.disabledGestures ? null : _handleDragUpdate,
          onHorizontalDragEnd: widget.disabledGestures ? null : _handleDragEnd,
          onHorizontalDragCancel:
              widget.disabledGestures ? null : _handleDragCancel,
          child: _mainView,
        ),
      ],
    );
  }

  Widget _buildItem(BuildContext context, int index) {
    final item = widget.items[index];

    final Widget child;

    if (item.selected) {
      final overlay = SlideTransition(
        position: _overlaySlideAnimation,
        textDirection: Directionality.of(context),
        child: Container(
          width: MediaQuery.of(context).size.width * 0.75 - 64,
          height: 46,
          decoration: BoxDecoration(
            color: LocalDatabaseService.colorSettings.drawerHighlightItemColor,
            borderRadius: const BorderRadiusDirectional.horizontal(
              end: Radius.circular(_overlayRadius),
            ),
          ),
        ),
      );

      child = Stack(
        children: <Widget>[
          overlay,
          item,
        ],
      );
    } else {
      child = item;
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: child,
    );
  }

  void _handleControllerChanged() {
    _controller.value.visible
        ? _animationController.forward()
        : _animationController.reverse();
  }

  void _handleDragStart(DragStartDetails details) {
    _captured = true;
    _startPosition = details.globalPosition;
    _offsetValue = _animationController.value;
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    if (!_captured) return;

    final screenSize = MediaQuery.of(context).size;
    final rtl = Directionality.of(context) == TextDirection.rtl;

    _freshPosition = details.globalPosition;

    final diff = (_freshPosition - _startPosition).dx;

    _animationController.value = _offsetValue +
        (diff / (screenSize.width * _openRatio)) * (rtl ? -1 : 1);
  }

  void _handleDragEnd(DragEndDetails details) {
    if (!_captured) return;

    _captured = false;

    if (_animationController.value >= _slideThreshold) {
      if (_controller.value.visible) {
        _animationController.forward();
      } else {
        _controller.showDrawer();
      }
    } else {
      if (!_controller.value.visible) {
        _animationController.reverse();
      } else {
        _controller.hideDrawer();
      }
    }
  }

  void _handleDragCancel() {
    _captured = false;
  }

  @override
  void dispose() {
    _controller.removeListener(_handleControllerChanged);
    _animationController.dispose();

    _controller.dispose();

    super.dispose();
  }
}
