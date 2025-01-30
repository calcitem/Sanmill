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
  });

  final T currentSelectedValue;
  final Function(T) onSelectionChanged;
  final T itemValue;
  final String itemTitle;
  final Icon itemIcon;

  bool get isSelected => currentSelectedValue == itemValue;

  @override
  Widget build(BuildContext context) {
    // TODO: drawerHighlightTextColor
    final Color color = isSelected
        ? DB().colorSettings.drawerTextColor
        : DB().colorSettings.drawerTextColor;

    final Icon listItemIcon = Icon(
      itemIcon.icon,
      color: color,
      key: const Key('custom_drawer_item_icon'),
    );

    final TextStyle titleStyle =
        Theme.of(context).textTheme.titleLarge!.copyWith(
              fontWeight: isSelected ? FontWeight.w500 : FontWeight.w400,
              color: color,
            );

    final Size titleSize = getBoundingTextSize(
      context,
      itemTitle,
      titleStyle,
      maxLines: 1,
    );
    final bool isExpand =
        (MediaQuery.of(context).size.width * 0.75 * 0.9 - 46) > titleSize.width;

    final Row drawerItem = Row(
      key: const Key('custom_drawer_item_row'),
      children: <Widget>[
        const SizedBox(height: 46.0, width: 6.0),
        const Padding(
          key: Key('custom_drawer_item_padding_left'),
          padding: EdgeInsets.all(4.0),
        ),
        listItemIcon,
        const Padding(
          key: Key('custom_drawer_item_padding_right'),
          padding: EdgeInsets.all(4.0),
        ),
        Expanded(
          key: const Key('custom_drawer_item_expanded'),
          child: isExpand || !isSelected
              ? Text(
                  itemTitle,
                  key: const Key('custom_drawer_item_text'),
                  maxLines: 1,
                  style: titleStyle,
                )
              : SizedBox(
                  height: AppTheme.drawerItemHeight,
                  child: Marquee(
                    key: const Key('custom_drawer_item_marquee'),
                    text: itemTitle,
                    style: titleStyle,
                  ),
                ),
        )
      ],
    );

    return InkWell(
      key: const Key('custom_drawer_item_inkwell'),
      splashColor: AppTheme.drawerSplashColor,
      highlightColor: Colors.transparent,
      onTap: () => onSelectionChanged(itemValue),
      child: drawerItem,
    );
  }
}
