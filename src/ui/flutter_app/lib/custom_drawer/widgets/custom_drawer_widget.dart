// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// custom_drawer_widget.dart

part of '../../custom_drawer/custom_drawer.dart';

/// CustomDrawer Widget
///
/// The widget laying out the custom drawer
class CustomDrawer extends StatefulWidget {
  const CustomDrawer({
    super.key,
    required this.mainScreenWidget,
    required this.drawerItems,
    required this.drawerHeader,
    this.controller,
    this.disabledGestures = false,
    required this.orientation,
  });

  static const Key drawerMainKey = Key('custom_drawer_main');

  /// Child widget. (Usually a widget that represents the main screen)
  final Widget mainScreenWidget;

  /// Controller that controls the widget state. By default a new controller will be generated.
  final CustomDrawerController? controller;

  /// Disables the gestures.
  final bool disabledGestures;

  /// Items the drawer holds
  final List<CustomDrawerItem<dynamic>> drawerItems;

  /// Header widget of the drawer
  final Widget drawerHeader;

  final Orientation orientation;

  @override
  CustomDrawerState createState() => CustomDrawerState();
}

class CustomDrawerState extends State<CustomDrawer>
    with SingleTickerProviderStateMixin {
  late final CustomDrawerController _drawerController;
  late final AnimationController _drawerAnimationController;
  late Animation<Offset> _mainScreenSlideAnimation;
  late final Animation<Offset> _drawerOverlaySlideAnimation;
  late double _gestureOffsetValue;
  late Offset _gestureCurrentPosition;
  late Offset _gestureStartPosition;
  bool _isGestureCaptured = false;

  static const Duration _duration = Duration(milliseconds: 250);
  static const double _slideThreshold = 0.25;
  static const int _slideVelocityThreshold = 1300;
  late double _drawerOpenRatio;
  static const double _overlayRadius = 28.0;

  @override
  void initState() {
    super.initState();

    _drawerController = widget.controller ?? CustomDrawerController();
    _drawerController.addListener(_handleControllerChanged);

    _drawerAnimationController = AnimationController(
      vsync: this,
      duration: _duration,
      value: _drawerController.value.isDrawerVisible ? 1 : 0,
    );

    _drawerOverlaySlideAnimation = Tween<Offset>(
      begin: const Offset(-1, 0),
      end: Offset.zero,
    ).animate(
      _drawerAnimationController,
    );

    _drawerOpenRatio = widget.orientation == Orientation.portrait ? 0.75 : 0.45;

    _mainScreenSlideAnimation = Tween<Offset>(
      begin: Offset.zero,
      end: Offset(_drawerOpenRatio, 0),
    ).animate(
      _drawerAnimationController,
    );
  }

  Widget buildListMenus() {
    return SliverToBoxAdapter(
      key: const Key('custom_drawer_sliver_to_box_adapter'),
      child: ListView.builder(
        key: const Key('custom_drawer_list_view_builder'),
        controller: ScrollController(),
        padding: const EdgeInsets.only(top: 4.0),
        physics: const BouncingScrollPhysics(),
        shrinkWrap: true,
        itemCount: widget.drawerItems.length,
        itemBuilder: _buildItem,
      ),
    );
  }

  @override
  void didUpdateWidget(covariant CustomDrawer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.orientation != widget.orientation) {
      _drawerOpenRatio =
          widget.orientation == Orientation.portrait ? 0.75 : 0.45;

      _mainScreenSlideAnimation = Tween<Offset>(
        begin: Offset.zero,
        end: Offset(_drawerOpenRatio, 0),
      ).animate(
        _drawerAnimationController,
      );
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final Align drawerWidget = Align(
      key: const Key('custom_drawer_align'),
      alignment: AlignmentDirectional.topStart,
      child: FractionallySizedBox(
        key: const Key('custom_drawer_fractionally_sized_box'),
        widthFactor: _drawerOpenRatio,
        child: Material(
          key: const Key('custom_drawer_material'),
          color: DB().colorSettings.drawerColor,
          child: CustomScrollView(
            key: const Key('custom_drawer_custom_scroll_view'),
            slivers: <Widget>[
              SliverPinnedToBoxAdapter(
                key: const Key('custom_drawer_sliver_pinned_to_box_adapter'),
                child: Container(
                    key: const Key('custom_drawer_header_container'),
                    decoration:
                        BoxDecoration(color: DB().colorSettings.drawerColor),
                    child: widget.drawerHeader),
              ),
              buildListMenus()
            ],
          ),
        ),
      ),
    );

    /// Menu and arrow icon animation overlay
    final IconButton drawerOverlayButton = IconButton(
      key: const Key('custom_drawer_drawer_overlay_button'),
      icon: AnimatedIcon(
        icon: AnimatedIcons.arrow_menu,
        progress: ReverseAnimation(_drawerAnimationController),
        semanticLabel: S.of(context).menu,
        color: Colors.white,
      ),
      onPressed: () => _drawerController.toggleDrawer(),
    );

    final SlideTransition mainScreenView = SlideTransition(
      key: const Key('custom_drawer_main_screen_slide_transition'),
      position: _mainScreenSlideAnimation,
      textDirection: Directionality.of(context),
      child: ValueListenableBuilder<CustomDrawerValue>(
        key: const Key('custom_drawer_value_listenable_builder_main_screen'),
        valueListenable: _drawerController,
        builder: (_, CustomDrawerValue value, Widget? child) => InkWell(
          key: const Key('custom_drawer_main_screen_inkwell'),
          onTap: _drawerController.hideDrawer,
          focusColor: Colors.transparent,
          child: DB().generalSettings.screenReaderSupport
              ? (value.isDrawerVisible ? Container() : child)
              : IgnorePointer(
                  ignoring: value.isDrawerVisible,
                  child: child,
                ),
        ),
        child: DecoratedBox(
          key: const Key('custom_drawer_main_screen_decorated_box'),
          decoration: const BoxDecoration(
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: AppTheme.drawerBoxerShadowColor,
                blurRadius: 24,
              ),
            ],
          ),
          child: widget.mainScreenWidget,
        ),
      ),
    );

    return GestureDetector(
      key: const Key('custom_drawer_gesture_detector'),
      onHorizontalDragStart: widget.disabledGestures ? null : _handleDragStart,
      onHorizontalDragUpdate:
          widget.disabledGestures ? null : _handleDragUpdate,
      onHorizontalDragEnd: widget.disabledGestures ? null : _handleDragEnd,
      onHorizontalDragCancel:
          widget.disabledGestures ? null : _handleDragCancel,
      child: Stack(
        key: const Key('custom_drawer_stack'),
        children: <Widget>[
          drawerWidget,
          CustomDrawerIcon(
            key: const Key('custom_drawer_custom_drawer_icon'),
            drawerIcon: drawerOverlayButton,
            child: mainScreenView,
          ),
        ],
      ),
    );
  }

  Widget _buildItem(BuildContext context, int index) {
    final CustomDrawerItem<dynamic> item = widget.drawerItems[index];

    final double itemPadding =
        View.of(context).platformDispatcher.views.first.physicalSize.height >=
                1080
            ? AppTheme.drawerItemPadding
            : AppTheme.drawerItemPaddingSmallScreen;

    final Widget drawerItemWidget;

    if (item.isSelected) {
      final SlideTransition selectedItemOverlay = SlideTransition(
        key: Key('custom_drawer_selected_item_overlay_$index'),
        position: _drawerOverlaySlideAnimation,
        textDirection: Directionality.of(context),
        child: Container(
          key: Key('custom_drawer_selected_item_container_$index'),
          width: MediaQuery.of(context).size.width * _drawerOpenRatio * 0.9,
          height: AppTheme.drawerItemHeight +
              (DB().displaySettings.fontScale - 1) * 12,
          decoration: BoxDecoration(
            color: DB().colorSettings.drawerHighlightItemColor,
            borderRadius: const BorderRadiusDirectional.horizontal(
              end: Radius.circular(_overlayRadius),
            ),
          ),
        ),
      );

      drawerItemWidget = Stack(
        key: Key('custom_drawer_selected_item_stack_$index'),
        children: <Widget>[
          selectedItemOverlay,
          item,
        ],
      );
    } else {
      drawerItemWidget = item;
    }
    return Padding(
      key: Key('custom_drawer_item_padding_$index'),
      padding: EdgeInsets.symmetric(vertical: itemPadding),
      child: drawerItemWidget,
    );
  }

  void _handleControllerChanged() {
    _drawerController.value.isDrawerVisible
        ? _drawerAnimationController.forward()
        : _drawerAnimationController.reverse();
  }

  void _handleDragStart(DragStartDetails details) {
    _isGestureCaptured = true;
    _gestureStartPosition = details.globalPosition;
    _gestureOffsetValue = _drawerAnimationController.value;
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    if (!_isGestureCaptured) {
      return;
    }

    final Size screenSize = MediaQuery.of(context).size;
    final bool rtl = Directionality.of(context) == TextDirection.rtl;

    _gestureCurrentPosition = details.globalPosition;

    final double diff = (_gestureCurrentPosition - _gestureStartPosition).dx;

    _drawerAnimationController.value = _gestureOffsetValue +
        (diff / (screenSize.width * _drawerOpenRatio)) * (rtl ? -1 : 1);
  }

  void _handleDragEnd(DragEndDetails details) {
    if (!_isGestureCaptured) {
      return;
    }

    _isGestureCaptured = false;

    if (_drawerController.value.isDrawerVisible) {
      if (_drawerAnimationController.value <= 1 - _slideThreshold ||
          details.primaryVelocity! <= -_slideVelocityThreshold) {
        _drawerController.hideDrawer();
      } else {
        _drawerAnimationController.forward();
      }
    } else {
      if (_drawerAnimationController.value >= _slideThreshold ||
          details.primaryVelocity! >= _slideVelocityThreshold) {
        _drawerController.showDrawer();
      } else {
        _drawerAnimationController.reverse();
      }
    }
  }

  void _handleDragCancel() {
    _isGestureCaptured = false;
  }

  @override
  void dispose() {
    _drawerController.removeListener(_handleControllerChanged);
    _drawerAnimationController.dispose();

    _drawerController.dispose();

    super.dispose();
  }
}
