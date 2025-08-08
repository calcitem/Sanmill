// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// kids_game_page.dart

// ignore_for_file: directives_ordering

import 'package:flutter/material.dart';

import '../../shared/services/kids_ui_service.dart';
import '../../shared/themes/kids_theme.dart';
import '../../educational/widgets/learning_assistant.dart';
import '../services/mill.dart';
import 'kids_board.dart';

/// Kids-friendly game page designed for Teacher Approved and Family programs
/// Features simplified UI, educational elements, and child-safe design
class KidsGamePage extends StatefulWidget {
  const KidsGamePage({
    super.key,
    required this.gameMode,
    this.showTutorial = true,
  });

  final GameMode gameMode;
  final bool showTutorial;

  @override
  State<KidsGamePage> createState() => _KidsGamePageState();
}

class _KidsGamePageState extends State<KidsGamePage>
    with TickerProviderStateMixin {
  late AnimationController _celebrationController;
  late AnimationController _hintController;

  final KidsUIService _kidsUIService = KidsUIService.instance;

  // Educational hints for teaching game rules
  List<String> educationalHints = <String>[];
  int currentHintIndex = 0;
  bool showHint = false;

  // Tutorial progress tracking
  bool isFirstMove = true;
  bool showingTutorial = false;

  @override
  void initState() {
    super.initState();

    // Disable adult UI elements when kids mode is active
    _disableAdultUIElements();

    _celebrationController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );

    _hintController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );

    _initializeEducationalContent();

    if (widget.showTutorial) {
      _startTutorial();
    }
  }

  @override
  void dispose() {
    _celebrationController.dispose();
    _hintController.dispose();
    super.dispose();
  }

  /// Disable adult UI elements like notation, history, piece count
  void _disableAdultUIElements() {
    if (KidsUIService.instance.isKidsModeEnabled) {
      try {
        // TODO: Use copyWith when build_runner generates the methods
        // Temporarily disable adult UI elements manually
        // This should be replaced with proper copyWith calls after build_runner
        // DB().displaySettings = DB().displaySettings.copyWith(
        //   isNotationsShown: false,
        //   isHistoryShown: false,
        //   isPieceCountInHandShown: false,
        //   isPointsShown: false,
        // );
      } catch (e) {
        // Silent catch for now until copyWith is available
      }
    }
  }

  void _initializeEducationalContent() {
    // Initialize educational hints based on current locale
    // These hints teach children about the game rules in a fun way
    educationalHints = <String>[
      "Welcome to Nine Men's Morris! Let's learn together! 🎯",
      'Try to get three pieces in a row to make a "mill"! ⭐',
      "When you make a mill, you can remove one of your opponent's pieces! 🎪",
      'Be careful! Your opponent is trying to make mills too! 🤔',
      'You can move your pieces to empty spaces connected by lines! 🚶',
      "Great job! You're becoming a Nine Men's Morris champion! 🏆",
    ];
  }

  void _startTutorial() {
    if (!mounted) {
      return;
    }

    setState(() {
      showingTutorial = true;
      showHint = true;
      currentHintIndex = 0;
    });

    _hintController.forward();
  }

  void _nextHint() {
    if (currentHintIndex < educationalHints.length - 1) {
      setState(() {
        currentHintIndex++;
      });
      _hintController.reset();
      _hintController.forward();
    } else {
      _dismissHint();
    }
  }

  void _dismissHint() {
    _hintController.reverse().then((_) {
      if (mounted) {
        setState(() {
          showHint = false;
          showingTutorial = false;
        });
      }
    });
  }

  void _showCelebrationForGoodMove() {
    _celebrationController.forward().then((_) {
      _celebrationController.reset();
    });

    _kidsUIService.showCelebration(
      context,
      message: "Excellent move! You're getting better at this game! 🌟",
    );
  }

  // Removed unused reinforcement helper; messages are integrated inline where needed.

  // Game end handling moved to onMoveComplete for simplicity

  Widget _buildEducationalHint() {
    // Only show educational hints in kids mode and tutorial mode
    if (!KidsUIService.instance.isKidsModeEnabled ||
        !widget.showTutorial ||
        !showHint ||
        currentHintIndex >= educationalHints.length) {
      return const SizedBox.shrink();
    }

    return Positioned(
      top: 100,
      left: 16,
      right: 16,
      child: AnimatedBuilder(
        animation: _hintController,
        builder: (BuildContext context, Widget? child) {
          return Transform.scale(
            scale: 0.8 + (_hintController.value * 0.2),
            child: Opacity(
              opacity: _hintController.value,
              child: _kidsUIService.createEducationalHint(
                message: educationalHints[currentHintIndex],
                icon: Icons.lightbulb_outline,
                onDismiss: _dismissHint,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildKidsToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      decoration: BoxDecoration(
        color: KidsTheme.kidsColorThemes[_kidsUIService.currentKidsTheme]!
            .darkBackgroundColor
            .withOpacity(0.9),
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(20.0),
        ),
      ),
      child: SafeArea(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: <Widget>[
            _kidsUIService.createKidsButton(
              text: 'Help', // Show help as Learn to Play in kids mode
              icon: Icons.help_outline,
              onPressed: () => _openLearnToPlay(),
              width: 80,
              height: 48,
            ),
            _kidsUIService.createKidsButton(
              text: 'Hint', // Show educational hint
              icon: Icons.lightbulb_outline,
              onPressed: () => _showNextHint(),
              width: 80,
              height: 48,
            ),
            _kidsUIService.createKidsButton(
              text: 'New Game', // Start new game
              icon: Icons.refresh,
              onPressed: () => _startNewGame(),
              width: 100,
              height: 48,
            ),
          ],
        ),
      ),
    );
  }

  void _openLearnToPlay() {
    // Navigate to the Learning Assistant page for guided tutorial
    Navigator.of(context).push(
      MaterialPageRoute<dynamic>(
        builder: (BuildContext context) => const LearningAssistant(),
      ),
    );
  }

  void _showNextHint() {
    if (!showHint) {
      setState(() {
        showHint = true;
        currentHintIndex = 0;
      });
      _hintController.forward();
    } else {
      _nextHint();
    }
  }

  void _startNewGame() {
    // Show confirmation dialog for kids
    showDialog(
      context: context,
      builder: (BuildContext context) => _kidsUIService.createKidsDialog(
        title: 'New Game',
        content: 'Do you want to start a new game?',
        icon: const Icon(Icons.sports_esports, color: Colors.green, size: 32),
        actions: <Widget>[
          _kidsUIService.createKidsButton(
            text: 'No, Keep Playing',
            onPressed: () => Navigator.of(context).pop(),
            isPrimary: false,
          ),
          _kidsUIService.createKidsButton(
            text: 'Yes, New Game!',
            onPressed: () {
              Navigator.of(context).pop();
              _resetGame();
            },
            icon: Icons.play_arrow,
          ),
        ],
      ),
    );
  }

  void _resetGame() {
    // Reset game state
    GameController().reset();

    // Reset tutorial state
    setState(() {
      isFirstMove = true;
      currentHintIndex = 0;
    });

    // Show encouraging message
    _kidsUIService.showCelebration(
      context,
      message: "New game started! Let's have fun! 🎮",
    );
  }

  Widget _buildKidsBoard() {
    // For now, continue using the existing KidsBoard but with a note about future refactoring
    // TODO: Refactor to use GameBoard directly with theme overrides
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24.0),
        border: Border.all(
          color: KidsTheme.kidsColorThemes[_kidsUIService.currentKidsTheme]!
              .boardBackgroundColor,
          width: 4.0,
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20.0),
        child: KidsBoard(
          onMoveMade: () {
            // Handle tutorial progression
            if (showingTutorial && showHint) {
              Future.delayed(const Duration(milliseconds: 1000), () {
                _nextHint();
              });
            }
          },
          onMillFormed: () {
            // Show celebration when a mill is formed
            _showCelebrationForGoodMove();
          },
        ),
      ),
    );
  }

  // TODO: Implement move completion handling for educational feedback
  // void _onMoveComplete() { ... }

  @override
  Widget build(BuildContext context) {
    return Theme(
      // Apply kids theme to entire page
      data: KidsTheme.createKidsTheme(
        colorTheme: _kidsUIService.currentKidsTheme,
        brightness: Theme.of(context).brightness,
      ),
      child: Scaffold(
        backgroundColor: KidsTheme
            .kidsColorThemes[_kidsUIService.currentKidsTheme]!
            .boardBackgroundColor,
        appBar: AppBar(
          title: Text(
            "Nine Men's Morris for Kids",
            style: _kidsUIService.getKidsTextStyle(
              context,
              baseFontSize: KidsTheme.kidsLargeFontSize,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          backgroundColor: KidsTheme
              .kidsColorThemes[_kidsUIService.currentKidsTheme]!
              .darkBackgroundColor,
          elevation: 0,
          centerTitle: true,
          toolbarHeight: 72.0, // Taller for kids
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, size: 28),
            onPressed: () {
              Navigator.of(context).pop();
            },
            padding: const EdgeInsets.all(12.0),
          ),
          actions: <Widget>[
            IconButton(
              icon: const Icon(Icons.settings, size: 28),
              onPressed: () => _showKidsSettings(),
              padding: const EdgeInsets.all(12.0),
            ),
          ],
        ),
        body: Stack(
          children: <Widget>[
            // Main game content
            Column(
              children: <Widget>[
                Expanded(
                  child: Center(
                    child: _buildKidsBoard(),
                  ),
                ),
                _buildKidsToolbar(),
              ],
            ),

            // Educational hint overlay
            _buildEducationalHint(),

            // Celebration overlay
            AnimatedBuilder(
              animation: _celebrationController,
              builder: (BuildContext context, Widget? child) {
                if (_celebrationController.value == 0) {
                  return const SizedBox.shrink();
                }

                return Positioned.fill(
                  child: IgnorePointer(
                    child: Container(
                      color: Colors.transparent,
                      child: Center(
                        child: Transform.scale(
                          scale: _celebrationController.value,
                          child: Opacity(
                            opacity: 1.0 - _celebrationController.value,
                            child: const Icon(
                              Icons.star,
                              size: 100,
                              color: Colors.yellow,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showKidsSettings() {
    showDialog(
      context: context,
      builder: (BuildContext context) => _kidsUIService.createKidsDialog(
        title: 'Game Settings',
        content: 'Choose your favorite colors and settings!',
        icon: const Icon(Icons.palette, color: Colors.purple, size: 32),
        actions: <Widget>[
          _kidsUIService.createKidsButton(
            text: 'Change Colors',
            onPressed: () {
              Navigator.of(context).pop();
              _showColorPicker();
            },
            icon: Icons.color_lens,
          ),
          _kidsUIService.createKidsButton(
            text: 'Done',
            onPressed: () => Navigator.of(context).pop(),
            icon: Icons.check,
          ),
        ],
      ),
    );
  }

  void _showColorPicker() {
    showDialog(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(
          'Pick Your Favorite Colors!',
          style: _kidsUIService.getKidsTextStyle(
            context,
            baseFontSize: KidsTheme.kidsLargeFontSize,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: KidsColorTheme.values.length,
            itemBuilder: (BuildContext context, int index) {
              final KidsColorTheme theme = KidsColorTheme.values[index];
              final bool isSelected = theme == _kidsUIService.currentKidsTheme;

              return Card(
                margin: const EdgeInsets.symmetric(vertical: 4.0),
                color: KidsTheme.kidsColorThemes[theme]!.boardBackgroundColor,
                child: ListTile(
                  contentPadding: const EdgeInsets.all(16.0),
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color:
                          KidsTheme.kidsColorThemes[theme]!.darkBackgroundColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  title: Text(
                    theme.displayName,
                    style: _kidsUIService.getKidsTextStyle(
                      context,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    theme.description,
                    style: _kidsUIService.getKidsTextStyle(
                      context,
                      baseFontSize: KidsTheme.kidsSmallFontSize,
                    ),
                  ),
                  trailing: isSelected
                      ? const Icon(Icons.check_circle,
                          color: Colors.green, size: 28)
                      : null,
                  onTap: () {
                    _kidsUIService.switchKidsTheme(theme);
                    Navigator.of(context).pop();
                    setState(() {}); // Rebuild with new theme
                  },
                ),
              );
            },
          ),
        ),
        actions: <Widget>[
          _kidsUIService.createKidsButton(
            text: 'Close',
            onPressed: () => Navigator.of(context).pop(),
            icon: Icons.close,
          ),
        ],
      ),
    );
  }
}
