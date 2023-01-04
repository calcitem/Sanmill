// This file is part of Sanmill.
// Copyright (C) 2019-2023 The Sanmill developers (see AUTHORS file)
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

part of '../custom_drawer.dart';

class CustomDrawerHeader extends StatelessWidget {
  const CustomDrawerHeader({
    super.key,
    required this.title,
  });

  final String title;

  @override
  Widget build(BuildContext context) {
    final List<Color> animatedTextsColors = <Color>[
      DB().colorSettings.drawerTextColor,
      Colors.black,
      Colors.blue,
      Colors.yellow,
      Colors.red,
      DB().colorSettings.darkBackgroundColor,
      DB().colorSettings.boardBackgroundColor,
      DB().colorSettings.drawerHighlightItemColor,
    ];

    final AnimatedTextKit animatedTitle = AnimatedTextKit(
      animatedTexts: <ColorizeAnimatedText>[
        ColorizeAnimatedText(
          title,
          textStyle: Theme.of(context).textTheme.headline4!.copyWith(
                fontWeight: FontWeight.w600,
              ),
          colors: animatedTextsColors,
          speed: const Duration(seconds: 3),
          textDirection: Directionality.of(context),
        ),
      ],
      pause: const Duration(seconds: 3),
      repeatForever: true,
      stopPauseOnTap: true,
    );

    final EdgeInsets padding = EdgeInsets.only(
      bottom: 16.0,
      top: 16.0 + (Constants.isLargeScreen ? 30.0 : 8.0),
      left: 20.0,
      right: 16.0,
    );

    return Padding(
      padding: padding,
      child: ExcludeSemantics(child: animatedTitle),
    );
  }
}
