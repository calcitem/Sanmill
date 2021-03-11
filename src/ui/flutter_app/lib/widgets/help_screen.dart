import 'package:flutter/material.dart';
import 'package:sanmill/common/config.dart';
import 'package:sanmill/style/app_theme.dart';
import 'package:sanmill/style/colors.dart';

class HelpScreen extends StatefulWidget {
  @override
  _HelpScreenState createState() => _HelpScreenState();
}

class _HelpScreenState extends State<HelpScreen> {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.nearlyWhite,
      child: SafeArea(
        top: false,
        child: Scaffold(
          backgroundColor: Color(Config.darkBackgroundColor),
          body: ListView(
            children: <Widget>[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.only(top: 32),
                child: Text(
                  'How to play',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: UIColors.burlyWoodColor,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.only(top: 16),
                child: const Text(
                  'The aim of the game is to leave the opponent with fewer than three pieces or no legal moves.\n'
                  '\n'
                  'The game is automatically drawn if a position occurs for the third time, or if no remove has been made in the last fifty moves.\n'
                  '\n'
                  'The game proceeds in three phases:\n'
                  '\n'
                  '1. Placing pieces on vacant points\n'
                  '2. Moving pieces to adjacent points\n'
                  '3. (optional phase) Moving pieces to any vacant point when the player has been reduced to three pieces\n'
                  '\n'
                  'Placing\n'
                  '\n'
                  'The game begins with an empty board, which consists of a grid with twenty-four points.'
                  'Players take turns placing their pieces on vacant points until each player has placed all pieces on the board.'
                  'If a player is able to place three of his pieces in a straight line, he has a \"mill\" and may remove one of his opponent\'s pieces from the board.\n'
                  '\n'
                  'In some variants of rules, players must remove any other pieces first before removing a piece from a formed mill.\n'
                  '\n'
                  'In some variants of rules, all the points of removed pieces may not be placed again in the placing phrase.\n'
                  '\n'
                  'Once all pieces have been used players take turns moving.\n'
                  '\n'
                  'Moving\n'
                  '\n'
                  'To move, a player moves one of his pieces along a board line to a vacant adjacent point. '
                  'If he cannot do so, he has lost the game. '
                  'As in the placing phase, a player who aligns three of his pieces on a board line has a mill and may remove one of his opponent\'s pieces. '
                  'Any player reduces to two pieces and has no option to form new mills and thus loses the game. '
                  'A player can also lose with more than three pieces, if his opponent blocks them so that they cannot be moved.\n'
                  '\n'
                  'Flying\n'
                  '\n'
                  'In some variants of rules, once a player has only three pieces left, his pieces may \"fly\", \"hop\", or \"jump\" to any vacant points, not only adjacent ones.\n'
                  '\n',
                  textAlign: TextAlign.left,
                  style: TextStyle(
                    fontSize: 16,
                    color: UIColors.burlyWoodColor,
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}
