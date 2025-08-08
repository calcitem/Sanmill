// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// learning_assistant.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../shared/services/kids_ui_service.dart';
import '../../shared/themes/kids_theme.dart';

/// Educational learning assistant for teaching kids how to play Mill
/// Supports the 4Cs of learning: Creativity, Critical thinking, Collaboration, Communication
class LearningAssistant extends StatefulWidget {
  const LearningAssistant({
    super.key,
    this.onLessonComplete,
  });

  final VoidCallback? onLessonComplete;

  @override
  State<LearningAssistant> createState() => _LearningAssistantState();
}

class _LearningAssistantState extends State<LearningAssistant>
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  late AnimationController _progressController;

  final KidsUIService _kidsUIService = KidsUIService.instance;

  int currentLessonIndex = 0;
  int totalLessons = 0;
  bool isLessonComplete = false;

  List<EducationalLesson> lessons = <EducationalLesson>[];

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );

    _progressController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );

    _initializeLessons();
    _startCurrentLesson();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _progressController.dispose();
    super.dispose();
  }

  void _initializeLessons() {
    lessons = <EducationalLesson>[
      EducationalLesson(
        id: 'basics',
        title: "Welcome to Nine Men's Morris! 🎯",
        description: "Let's learn the basics of this amazing strategy game!",
        content: <LessonStep>[
          LessonStep(
            title: "What is Nine Men's Morris?",
            description:
                "It's a fun strategy game where you try to get three pieces in a row!",
            icon: Icons.help_outline,
            interactiveElement: _buildBasicBoard(),
          ),
          LessonStep(
            title: 'The Goal',
            description:
                'Try to make "mills" - three pieces in a straight line!',
            icon: Icons.flag,
            interactiveElement: _buildMillExample(),
          ),
          LessonStep(
            title: 'Having Fun!',
            description: 'Every move is a chance to learn and improve! 🌟',
            icon: Icons.emoji_emotions,
            interactiveElement: _buildEncouragementWidget(),
          ),
        ],
      ),
      EducationalLesson(
        id: 'placing',
        title: 'Placing Your Pieces 🎪',
        description:
            'Learn how to place your pieces on the board strategically!',
        content: <LessonStep>[
          LessonStep(
            title: 'Choose Your Spot',
            description: 'Click on any empty dot to place your piece!',
            icon: Icons.place,
            interactiveElement: _buildPlacingDemo(),
          ),
          LessonStep(
            title: 'Think Ahead',
            description: 'Try to place pieces where you can make a mill!',
            icon: Icons.psychology,
            interactiveElement: _buildStrategyTip(),
          ),
          LessonStep(
            title: 'Take Turns',
            description: 'You and your opponent take turns placing pieces!',
            icon: Icons.sync_alt,
            interactiveElement: _buildTurnIndicator(),
          ),
        ],
      ),
      EducationalLesson(
        id: 'mills',
        title: 'Making Mills! ⭐',
        description: 'Learn how to make mills and remove opponent pieces!',
        content: <LessonStep>[
          LessonStep(
            title: 'Three in a Row',
            description:
                'When you get three pieces in a line, you made a mill!',
            icon: Icons.linear_scale,
            interactiveElement: _buildMillVisualization(),
          ),
          LessonStep(
            title: 'Remove a Piece',
            description:
                "When you make a mill, you can remove one of your opponent's pieces!",
            icon: Icons.remove_circle_outline,
            interactiveElement: _buildRemovalDemo(),
          ),
          LessonStep(
            title: 'Protect Your Pieces',
            description: 'Try to keep your pieces safe from being removed!',
            icon: Icons.shield,
            interactiveElement: _buildProtectionTip(),
          ),
        ],
      ),
      EducationalLesson(
        id: 'moving',
        title: 'Moving Your Pieces 🚶',
        description: 'Learn how to move pieces around the board!',
        content: <LessonStep>[
          LessonStep(
            title: 'Connected Lines',
            description:
                'You can only move along the lines to connected empty spots!',
            icon: Icons.timeline,
            interactiveElement: _buildMovementDemo(),
          ),
          LessonStep(
            title: 'Plan Your Moves',
            description: 'Think about where you want to go before moving!',
            icon: Icons.route,
            interactiveElement: _buildPlanningTip(),
          ),
          LessonStep(
            title: 'Make New Mills',
            description: 'Moving pieces can help you make new mills!',
            icon: Icons.refresh,
            interactiveElement: _buildMoveMill(),
          ),
        ],
      ),
      EducationalLesson(
        id: 'strategy',
        title: 'Winning Strategies! 🏆',
        description: 'Learn smart strategies to become a great player!',
        content: <LessonStep>[
          LessonStep(
            title: 'Control the Center',
            description:
                'Pieces in the center can make mills in more directions!',
            icon: Icons.center_focus_strong,
            interactiveElement: _buildCenterStrategy(),
          ),
          LessonStep(
            title: 'Block Your Opponent',
            description:
                "Sometimes it's good to stop your opponent from making mills!",
            icon: Icons.block,
            interactiveElement: _buildBlockingStrategy(),
          ),
          LessonStep(
            title: 'Multiple Threats',
            description:
                'Try to create situations where you can make mills in different ways!',
            icon: Icons.call_split,
            interactiveElement: _buildMultipleThreatDemo(),
          ),
        ],
      ),
    ];

    totalLessons = lessons.length;
  }

  void _startCurrentLesson() {
    if (currentLessonIndex < lessons.length) {
      _animationController.forward();
      _updateProgress();
    }
  }

  void _updateProgress() {
    final double progress = (currentLessonIndex + 1) / totalLessons;
    _progressController.animateTo(progress);
  }

  void _nextLesson() {
    if (currentLessonIndex < lessons.length - 1) {
      setState(() {
        currentLessonIndex++;
        isLessonComplete = false;
      });
      _animationController.reset();
      _startCurrentLesson();
    } else {
      _completeLearning();
    }
  }

  void _previousLesson() {
    if (currentLessonIndex > 0) {
      setState(() {
        currentLessonIndex--;
        isLessonComplete = false;
      });
      _animationController.reset();
      _startCurrentLesson();
    }
  }

  void _completeLearning() {
    setState(() {
      isLessonComplete = true;
    });

    _kidsUIService.showCelebration(
      context,
      message:
          "🎓 Congratulations! You've completed all lessons! You're ready to play! 🎓",
    );

    widget.onLessonComplete?.call();
  }

  Widget _buildProgressIndicator() {
    return Container(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: <Widget>[
          Text(
            'Learning Progress',
            style: _kidsUIService.getKidsTextStyle(
              context,
              baseFontSize: KidsTheme.kidsDefaultFontSize,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8.0),
          AnimatedBuilder(
            animation: _progressController,
            builder: (BuildContext context, Widget? child) {
              return LinearProgressIndicator(
                value: _progressController.value,
                backgroundColor: Colors.grey[300],
                valueColor: AlwaysStoppedAnimation<Color>(
                  KidsTheme.kidsColorThemes[_kidsUIService.currentKidsTheme]!
                      .pieceHighlightColor,
                ),
                minHeight: 8.0,
              );
            },
          ),
          const SizedBox(height: 8.0),
          Text(
            'Lesson ${currentLessonIndex + 1} of $totalLessons',
            style: _kidsUIService.getKidsTextStyle(
              context,
              baseFontSize: KidsTheme.kidsSmallFontSize,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLessonContent() {
    if (currentLessonIndex >= lessons.length) {
      return _buildCompletionScreen();
    }

    final EducationalLesson lesson = lessons[currentLessonIndex];

    return AnimatedBuilder(
      animation: _animationController,
      builder: (BuildContext context, Widget? child) {
        return Transform.translate(
          offset: Offset(0, 50 * (1 - _animationController.value)),
          child: Opacity(
            opacity: _animationController.value,
            child: _kidsUIService.createKidsCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  // Lesson title and description
                  Text(
                    lesson.title,
                    style: _kidsUIService.getKidsTextStyle(
                      context,
                      baseFontSize: KidsTheme.kidsLargeFontSize,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8.0),
                  Text(
                    lesson.description,
                    style: _kidsUIService.getKidsTextStyle(
                      context,
                      baseFontSize: KidsTheme.kidsDefaultFontSize,
                    ),
                  ),
                  const SizedBox(height: 20.0),

                  // Lesson steps
                  ...lesson.content
                      .map((LessonStep step) => _buildLessonStep(step)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildLessonStep(LessonStep step) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // Step icon
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: KidsTheme.kidsColorThemes[_kidsUIService.currentKidsTheme]!
                  .pieceHighlightColor
                  .withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(
              step.icon,
              color: KidsTheme.kidsColorThemes[_kidsUIService.currentKidsTheme]!
                  .pieceHighlightColor,
              size: 28,
            ),
          ),
          const SizedBox(width: 16.0),

          // Step content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  step.title,
                  style: _kidsUIService.getKidsTextStyle(
                    context,
                    baseFontSize: KidsTheme.kidsDefaultFontSize,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4.0),
                Text(
                  step.description,
                  style: _kidsUIService.getKidsTextStyle(
                    context,
                    baseFontSize: KidsTheme.kidsSmallFontSize,
                  ),
                ),
                if (step.interactiveElement != null) ...<Widget>[
                  const SizedBox(height: 12.0),
                  step.interactiveElement!,
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavigationButtons() {
    return Container(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          // Previous button
          _kidsUIService.createKidsButton(
            text: 'Previous',
            icon: Icons.arrow_back,
            onPressed: currentLessonIndex > 0 ? () => _previousLesson() : () {},
            isPrimary: false,
            width: 120,
          ),

          // Next/Complete button
          _kidsUIService.createKidsButton(
            text:
                currentLessonIndex < lessons.length - 1 ? 'Next' : 'Complete!',
            icon: currentLessonIndex < lessons.length - 1
                ? Icons.arrow_forward
                : Icons.check_circle,
            onPressed: _nextLesson,
            width: 120,
          ),
        ],
      ),
    );
  }

  Widget _buildCompletionScreen() {
    return _kidsUIService.createKidsCard(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          const Icon(
            Icons.school,
            size: 80,
            color: Colors.green,
          ),
          const SizedBox(height: 20.0),
          Text(
            '🎓 Learning Complete! 🎓',
            style: _kidsUIService.getKidsTextStyle(
              context,
              baseFontSize: KidsTheme.kidsHugeFontSize,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16.0),
          Text(
            "You've learned all the basics of Nine Men's Morris! Now you're ready to play and have fun!",
            style: _kidsUIService.getKidsTextStyle(
              context,
              baseFontSize: KidsTheme.kidsDefaultFontSize,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24.0),
          _kidsUIService.createKidsButton(
            text: 'Start Playing!',
            icon: Icons.play_arrow,
            onPressed: () => Navigator.of(context).pop(),
            width: 200,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
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
            'Learning Assistant',
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
          centerTitle: true,
          toolbarHeight: 72.0,
        ),
        body: Column(
          children: <Widget>[
            _buildProgressIndicator(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: _buildLessonContent(),
              ),
            ),
            _buildNavigationButtons(),
          ],
        ),
      ),
    );
  }

  // Interactive elements for lessons
  Widget _buildBasicBoard() {
    return Container(
      height: 150,
      width: 150,
      decoration: BoxDecoration(
        color: Colors.brown[200],
        borderRadius: BorderRadius.circular(12.0),
        border: Border.all(color: Colors.brown, width: 2),
      ),
      child: CustomPaint(
        painter: SimpleBoardPainter(),
      ),
    );
  }

  Widget _buildMillExample() {
    return Container(
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        color: Colors.green[100],
        borderRadius: BorderRadius.circular(12.0),
        border: Border.all(color: Colors.green, width: 2),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          _buildGamePiece(Colors.blue),
          const SizedBox(width: 8),
          Container(width: 20, height: 2, color: Colors.black),
          const SizedBox(width: 8),
          _buildGamePiece(Colors.blue),
          const SizedBox(width: 8),
          Container(width: 20, height: 2, color: Colors.black),
          const SizedBox(width: 8),
          _buildGamePiece(Colors.blue),
        ],
      ),
    );
  }

  Widget _buildGamePiece(Color color) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(),
      ),
    );
  }

  Widget _buildEncouragementWidget() {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[Colors.yellow[200]!, Colors.orange[200]!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16.0),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          const Icon(Icons.emoji_emotions, size: 32, color: Colors.orange),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              "Remember: It's okay to make mistakes! Every game helps you learn!",
              style: _kidsUIService.getKidsTextStyle(
                context,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  // Placeholder implementations for other interactive elements
  Widget _buildPlacingDemo() => _buildInteractiveDemo('Tap here to place!');
  Widget _buildStrategyTip() => _buildInteractiveDemo('Think ahead!');
  Widget _buildTurnIndicator() => _buildInteractiveDemo('Your turn!');
  Widget _buildMillVisualization() => _buildInteractiveDemo('Three in a row!');
  Widget _buildRemovalDemo() => _buildInteractiveDemo('Remove opponent piece!');
  Widget _buildProtectionTip() => _buildInteractiveDemo('Keep pieces safe!');
  Widget _buildMovementDemo() => _buildInteractiveDemo('Move along lines!');
  Widget _buildPlanningTip() => _buildInteractiveDemo('Plan your path!');
  Widget _buildMoveMill() => _buildInteractiveDemo('Move to make mills!');
  Widget _buildCenterStrategy() => _buildInteractiveDemo('Control the center!');
  Widget _buildBlockingStrategy() => _buildInteractiveDemo('Block opponents!');
  Widget _buildMultipleThreatDemo() => _buildInteractiveDemo('Multiple mills!');

  Widget _buildInteractiveDemo(String message) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Great job! $message'),
            duration: const Duration(seconds: 2),
            backgroundColor: Colors.green,
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(16.0),
        decoration: BoxDecoration(
          color: Colors.blue[100],
          borderRadius: BorderRadius.circular(12.0),
          border: Border.all(color: Colors.blue, width: 2),
        ),
        child: Center(
          child: Text(
            '🎯 $message',
            style: _kidsUIService.getKidsTextStyle(
              context,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

// Data models
class EducationalLesson {
  EducationalLesson({
    required this.id,
    required this.title,
    required this.description,
    required this.content,
  });
  final String id;
  final String title;
  final String description;
  final List<LessonStep> content;
}

class LessonStep {
  LessonStep({
    required this.title,
    required this.description,
    required this.icon,
    this.interactiveElement,
  });
  final String title;
  final String description;
  final IconData icon;
  final Widget? interactiveElement;
}

// Simple board painter for demonstration
class SimpleBoardPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = Colors.brown[800]!
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    final Offset center = Offset(size.width / 2, size.height / 2);
    final double radius = size.width * 0.4;

    // Draw simple mill board representation
    canvas.drawRect(
      Rect.fromCenter(center: center, width: radius * 2, height: radius * 2),
      paint,
    );

    canvas.drawRect(
      Rect.fromCenter(
          center: center, width: radius * 1.3, height: radius * 1.3),
      paint,
    );

    canvas.drawRect(
      Rect.fromCenter(
          center: center, width: radius * 0.6, height: radius * 0.6),
      paint,
    );
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}
