// This file is part of Sanmill.
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)
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

part of 'game_page.dart';

@visibleForTesting
class GameHeader extends StatefulWidget implements PreferredSizeWidget {
  GameHeader({super.key});

  @override
  final Size preferredSize = Size.fromHeight(
    kToolbarHeight + DB().displaySettings.boardTop + AppTheme.boardMargin,
  );

  @override
  State<GameHeader> createState() => _GameHeaderState();
}

class _GameHeaderState extends State<GameHeader> {
  ScrollNotificationObserverState? _scrollNotificationObserver;
  bool _scrolledUnder = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateScrollObserver();
    _validatePosition();
  }

  void _updateScrollObserver() {
    if (_scrollNotificationObserver != null) {
      _scrollNotificationObserver!.removeListener(_handleScrollNotification);
    }
    _scrollNotificationObserver = ScrollNotificationObserver.of(context);
    if (_scrollNotificationObserver != null) {
      _scrollNotificationObserver!.addListener(_handleScrollNotification);
    }
  }

  void _validatePosition() {
    final String? fen = GameController().position.fen;
    if (fen == null || !GameController().position.validateFen(fen)) {
      GameController().headerTipNotifier.showTip(S.of(context).invalidPosition);
    }
  }

  @override
  void dispose() {
    _removeScrollObserver();
    super.dispose();
  }

  void _removeScrollObserver() {
    if (_scrollNotificationObserver != null) {
      _scrollNotificationObserver!.removeListener(_handleScrollNotification);
      _scrollNotificationObserver = null;
    }
  }

  void _handleScrollNotification(ScrollNotification notification) {
    if (notification is ScrollUpdateNotification) {
      final bool oldScrolledUnder = _scrolledUnder;
      _scrolledUnder = notification.depth == 0 &&
          notification.metrics.extentBefore > 0 &&
          notification.metrics.axis == Axis.vertical;
      if (_scrolledUnder != oldScrolledUnder) {
        setState(() {
          // React to a change in MaterialState.scrolledUnder
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      key: const Key('game_header_align'),
      alignment: Alignment.topCenter,
      child: BlockSemantics(
        key: const Key('game_header_block_semantics'),
        child: Center(
          key: const Key('game_header_center'),
          child: Padding(
            key: const Key('game_header_padding'),
            padding: EdgeInsets.only(top: DB().displaySettings.boardTop),
            child: Column(
              key: const Key('game_header_column'),
              children: <Widget>[
                const HeaderIcons(key: Key('header_icons')),
                _buildDivider(),
                const HeaderTip(key: Key('header_tip')),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDivider() {
    if (DB().displaySettings.isPositionalAdvantageIndicatorShown) {
      return _buildPositionalAdvantageDivider();
    } else {
      return _buildDefaultDivider();
    }
  }

  Widget _buildPositionalAdvantageDivider() {
    int value =
        GameController().value == null ? 0 : int.parse(GameController().value!);
    const double opacity = 1;
    const int valueLimit = 100;

    if ((value == valueUnique || value == -valueUnique) ||
        GameController().gameInstance.gameMode == GameMode.humanVsHuman) {
      value = valueEachPiece * GameController().position.pieceCountDiff();
    }

    value = (value * 2).clamp(-valueLimit, valueLimit);

    final num dividerWhiteLength = valueLimit + value;
    final num dividerBlackLength = valueLimit - value;

    return Container(
      key: const Key('positional_advantage_divider'),
      height: 2,
      width: valueLimit * 2,
      margin: const EdgeInsets.only(bottom: AppTheme.boardMargin),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(2),
      ),
      child: Row(
        key: const Key('positional_advantage_row'),
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Container(
            key: const Key('divider_white_container'),
            height: 2,
            width: dividerWhiteLength.toDouble(),
            color:
                DB().colorSettings.whitePieceColor.withValues(alpha: opacity),
          ),
          Container(
            key: const Key('divider_black_container'),
            height: 2,
            width: dividerBlackLength.toDouble(),
            color:
                DB().colorSettings.blackPieceColor.withValues(alpha: opacity),
          ),
        ],
      ),
    );
  }

  Widget _buildDefaultDivider() {
    const double opacity = 1;
    return Container(
      key: const Key('default_divider'),
      height: 2,
      width: 180,
      margin: const EdgeInsets.only(bottom: AppTheme.boardMargin),
      decoration: BoxDecoration(
        color: (DB().colorSettings.darkBackgroundColor == Colors.white ||
                DB().colorSettings.darkBackgroundColor ==
                    const Color.fromARGB(1, 255, 255, 255))
            ? DB().colorSettings.messageColor.withValues(alpha: opacity)
            : DB()
                .colorSettings
                .boardBackgroundColor
                .withValues(alpha: opacity),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

@visibleForTesting
class HeaderTip extends StatefulWidget {
  const HeaderTip({super.key});

  @override
  HeaderTipState createState() => HeaderTipState();
}

class HeaderTipState extends State<HeaderTip> {
  final ValueNotifier<String> _messageNotifier = ValueNotifier<String>("");

  @override
  void initState() {
    super.initState();
    GameController().headerTipNotifier.addListener(_showTip);
  }

  void _showTip() {
    final HeaderTipNotifier headerTipNotifier =
        GameController().headerTipNotifier;

    if (headerTipNotifier.showSnackBar) {
      rootScaffoldMessengerKey.currentState!
          .showSnackBarClear(headerTipNotifier.message);
    }

    _messageNotifier.value = headerTipNotifier.message;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      key: const Key('header_tip_value_listenable_builder'),
      valueListenable: _messageNotifier,
      builder: (BuildContext context, String value, Widget? child) {
        return Semantics(
          key: const Key('header_tip_semantics'),
          enabled: true,
          child: SizedBox(
            key: const Key('header_tip_sized_box'),
            height: 24 * DB().displaySettings.fontScale,
            child: Text(
              value.isEmpty ? S.of(context).welcome : value,
              key: const Key('header_tip_text'),
              maxLines: 1,
              style: TextStyle(
                color: DB().colorSettings.messageColor,
                fontSize: AppTheme.textScaler.scale(AppTheme.defaultFontSize),
                fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    GameController().headerTipNotifier.removeListener(_showTip);
    super.dispose();
  }
}

@visibleForTesting
class HeaderIcons extends StatefulWidget {
  const HeaderIcons({super.key});

  @override
  HeaderStateIcons createState() => HeaderStateIcons();
}

class HeaderStateIcons extends State<HeaderIcons> {
  final ValueNotifier<IconData> _iconDataNotifier =
      ValueNotifier<IconData>(GameController().position.sideToMove.icon);

  @override
  void initState() {
    super.initState();
    GameController().headerIconsNotifier.addListener(_updateIcons);
  }

  void _updateIcons() {
    _iconDataNotifier.value = GameController().position.sideToMove.icon;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<IconData>(
      key: const Key('header_icons_value_listenable_builder'),
      valueListenable: _iconDataNotifier,
      builder: (BuildContext context, IconData value, Widget? child) {
        return IconTheme(
          key: const Key('header_icons_icon_theme'),
          data: IconThemeData(
            color: DB().colorSettings.messageColor,
          ),
          child: Row(
            key: const Key('header_icon_row'),
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(GameController().gameInstance.gameMode.leftHeaderIcon,
                  key: const Key('left_header_icon')),
              Icon(value, key: const Key('current_side_icon')),
              Icon(GameController().gameInstance.gameMode.rightHeaderIcon,
                  key: const Key('right_header_icon')),
            ],
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    GameController().headerIconsNotifier.removeListener(_updateIcons);
    super.dispose();
  }
}
