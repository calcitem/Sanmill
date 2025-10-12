// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// custom_drawer_item.dart

part of '../../custom_drawer/custom_drawer.dart';

class CustomDrawerItem<T> extends StatelessWidget {
  const CustomDrawerItem({
    super.key,
    required this.currentSelectedValue,
    required this.onSelectionChanged,
    required this.itemValue,
    required this.itemTitle,
    required this.itemIcon,
    this.children,
    this.onTapOverride,
    this.trailingContent,
  });

  final T currentSelectedValue;
  final Function(T) onSelectionChanged;
  final T itemValue;
  final String itemTitle;
  final Icon itemIcon;
  final List<CustomDrawerItem<dynamic>>? children;
  final VoidCallback? onTapOverride;
  final Widget? trailingContent;

  bool get isSelected => currentSelectedValue == itemValue;
  bool get isParent => children != null && children!.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    // TODO: drawerHighlightTextColor
    final Color color = isSelected
        ? DB().colorSettings.drawerTextColor
        : DB().colorSettings.drawerTextColor;

    final Icon listItemIcon = Icon(
      itemIcon.icon,
      color: color,
      size: 24.0,
      key: const Key('custom_drawer_item_icon'),
    );

    final TextStyle baseTitleStyle =
        Theme.of(context).textTheme.titleMedium ??
        Theme.of(context).textTheme.titleLarge ??
        const TextStyle();

    final TextStyle titleStyle = baseTitleStyle.copyWith(
      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
      color: color,
      letterSpacing: 0.2,
    );

    final Size titleSize = getBoundingTextSize(
      context,
      itemTitle,
      titleStyle,
      maxLines: 1,
    );
    final bool isExpand =
        (MediaQuery.of(context).size.width * 0.75 * 0.9 - 46) > titleSize.width;

    final Widget titleWidget = isExpand || !isSelected
        ? Text(
            itemTitle,
            key: const Key('custom_drawer_item_text'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: titleStyle,
          )
        : SizedBox(
            height: AppTheme.drawerItemHeight,
            child: Marquee(
              key: const Key('custom_drawer_item_marquee'),
              text: itemTitle,
              style: titleStyle,
            ),
          );

    final Widget drawerItem = Row(
      key: const Key('custom_drawer_item_row'),
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        listItemIcon,
        const SizedBox(width: 14.0),
        Expanded(
          key: const Key('custom_drawer_item_expanded'),
          child: titleWidget,
        ),
        if (trailingContent != null) ...<Widget>[
          const SizedBox(width: 12.0),
          trailingContent!,
        ],
      ],
    );

    final Color accentColor =
        DB().colorSettings.drawerHighlightItemColor.withOpacity(0.2);

    return InkWell(
      key: const Key('custom_drawer_item_inkwell'),
      borderRadius: BorderRadius.circular(18.0),
      splashColor: accentColor,
      focusColor: accentColor,
      hoverColor: accentColor.withOpacity(0.6),
      highlightColor: Colors.transparent,
      onTap: onTapOverride ?? () => onSelectionChanged(itemValue),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
        constraints: const BoxConstraints(minHeight: AppTheme.drawerItemHeight),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18.0),
          color: isSelected
              ? DB()
                  .colorSettings
                  .drawerHighlightItemColor
                  .withOpacity(0.08)
              : Colors.transparent,
        ),
        child: drawerItem,
      ),
    );
  }
}
