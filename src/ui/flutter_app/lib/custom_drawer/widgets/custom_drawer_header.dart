// This file is part of Sanmill.
// Copyright (C) 2019-2024 The Sanmill developers (see AUTHORS file)
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

part of '../../custom_drawer/custom_drawer.dart';

class CustomDrawerHeader extends StatelessWidget {
  const CustomDrawerHeader({
    super.key,
    required this.headerTitle,
  });

  final String headerTitle;

  @override
  Widget build(BuildContext context) {
    final List<Color> drawerHeaderAnimationColors = <Color>[
      DB().colorSettings.drawerTextColor,
      Colors.black,
      Colors.blue,
      Colors.yellow,
      Colors.red,
      DB().colorSettings.darkBackgroundColor,
      DB().colorSettings.boardBackgroundColor,
      DB().colorSettings.drawerHighlightItemColor,
    ];

    final AnimatedTextKit animatedHeaderText = AnimatedTextKit(
      animatedTexts: <ColorizeAnimatedText>[
        ColorizeAnimatedText(
          headerTitle,
          textStyle: Theme.of(context).textTheme.headlineMedium!.copyWith(
                fontWeight: FontWeight.w600,
              ),
          colors: drawerHeaderAnimationColors,
          speed: const Duration(seconds: 3),
          textDirection: Directionality.of(context),
        ),
      ],
      pause: const Duration(seconds: 3),
      repeatForever: true,
      stopPauseOnTap: true,
    );

    final EdgeInsets drawerHeaderPadding = EdgeInsets.only(
      bottom: 16.0,
      top: 16.0 + (Constants.isLargeScreen(context) ? 30.0 : 8.0),
      left: 20.0,
      right: 16.0,
    );

    return Padding(
      padding: drawerHeaderPadding,
      child: ExcludeSemantics(child: animatedHeaderText),
    );
  }
}
