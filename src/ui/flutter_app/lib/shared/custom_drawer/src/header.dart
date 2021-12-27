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

class CustomDrawerHeader extends StatelessWidget {
  const CustomDrawerHeader({
    Key? key,
    required this.title,
  }) : super(key: key);

  final String title;

  @override
  Widget build(BuildContext context) {
    final List<Color> _animatedTextsColors = [
      DB().colorSettings.drawerTextColor,
      Colors.black,
      Colors.blue,
      Colors.yellow,
      Colors.red,
      DB().colorSettings.darkBackgroundColor,
      DB().colorSettings.boardBackgroundColor,
      DB().colorSettings.drawerHighlightItemColor,
    ];

    final animation = AnimatedTextKit(
      animatedTexts: [
        ColorizeAnimatedText(
          title,
          textStyle: AppTheme.drawerHeaderTextStyle,
          colors: _animatedTextsColors,
          speed: const Duration(seconds: 3),
        ),
      ],
      pause: const Duration(seconds: 3),
      repeatForever: true,
      stopPauseOnTap: true,
    );

    final _padding = EdgeInsets.only(
      bottom: 16.0,
      top: 16.0 + (Constants.isLargeScreen ? 30 : 8),
      left: 20,
      right: 16,
    );

    return Padding(
      padding: _padding,
      child: ExcludeSemantics(child: animation),
    );
  }
}
