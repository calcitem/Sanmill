// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// your_widget_name.dart

import 'package:flutter/material.dart';

/// Brief one-sentence description of what this widget does.
///
/// Longer description explaining:
/// - Purpose and responsibility
/// - When to use this widget
/// - Key behaviors
///
/// Example:
/// ```dart
/// YourWidgetName(
///   parameter: value,
///   onAction: () {
///     // Handle action
///   },
/// )
/// ```
///
/// See also:
/// - [RelatedWidget]: Related functionality
/// - [Documentation](../docs/COMPONENTS.md): Component catalog
class YourWidgetName extends StatelessWidget {
  /// Creates a [YourWidgetName].
  ///
  /// The [requiredParameter] must not be null.
  const YourWidgetName({
    required this.requiredParameter,
    this.optionalParameter,
    this.onAction,
    super.key,
  });

  /// Description of what this parameter does.
  ///
  /// Explain any constraints or special values.
  final String requiredParameter;

  /// Optional parameter description.
  ///
  /// Default: null (or describe default behavior)
  final int? optionalParameter;

  /// Callback when user performs action.
  ///
  /// Called when [describe when this is called].
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    // Implementation

    return Container(
      child: Column(
        children: [
          Text(requiredParameter),
          if (optionalParameter != null)
            Text('Optional: $optionalParameter'),
          ElevatedButton(
            onPressed: onAction,
            child: const Text('Action'),
          ),
        ],
      ),
    );
  }

  /// Helper method description (if needed).
  ///
  /// Explain what this does and when it's called.
  String _helperMethod() {
    // Implementation
    return 'result';
  }
}

// If you need a StatefulWidget instead:

/// Brief description of stateful widget.
///
/// Use StatefulWidget when you need:
/// - Local mutable state
/// - Animation controllers
/// - Stream subscriptions
/// - Lifecycle management
class YourStatefulWidget extends StatefulWidget {
  const YourStatefulWidget({
    required this.parameter,
    super.key,
  });

  final String parameter;

  @override
  State<YourStatefulWidget> createState() => _YourStatefulWidgetState();
}

class _YourStatefulWidgetState extends State<YourStatefulWidget> {
  // State variables
  int _counter = 0;

  // Controllers (if needed)
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();

    // Initialize state, controllers, listeners
    _scrollController = ScrollController();

    // Setup listeners
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    // Clean up resources
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();

    super.dispose(); // ALWAYS call super.dispose() last
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      child: Column(
        children: [
          Text('Counter: $_counter'),
          ElevatedButton(
            onPressed: _incrementCounter,
            child: const Text('Increment'),
          ),
        ],
      ),
    );
  }

  void _incrementCounter() {
    setState(() {
      _counter++;
    });
  }

  void _onScroll() {
    // Handle scroll events
  }
}

// Widget with ValueNotifier for reactive state:

/// Widget that rebuilds when notifier changes.
class ReactiveWidget extends StatelessWidget {
  const ReactiveWidget({
    required this.notifier,
    super.key,
  });

  final ValueNotifier<int> notifier;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: notifier,
      builder: (context, value, child) {
        // This rebuilds when notifier.value changes
        return Text('Value: $value');
      },
    );
  }
}

// Using with animations:

/// Widget with animation.
class AnimatedWidget extends StatefulWidget {
  const AnimatedWidget({super.key});

  @override
  State<AnimatedWidget> createState() => _AnimatedWidgetState();
}

class _AnimatedWidgetState extends State<AnimatedWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _animation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    ));

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Opacity(
          opacity: _animation.value,
          child: child,
        );
      },
      child: const Text('Animated content'),
    );
  }
}

// Best Practices Checklist:
// [ ] GPL v3 header present
// [ ] Docstrings for class and public methods
// [ ] Const constructors where possible
// [ ] Proper disposal of resources
// [ ] Localized strings (no hardcoded text)
// [ ] Accessibility (semantic labels)
// [ ] Type-safe (no dynamic)
// [ ] Formatted with dart format

