// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// annotation_toolbar.dart

part of '../game_toolbar.dart';

/// A toolbar for annotation tools that can be toggled between
/// a collapsed view (showing one button) and an expanded view (showing three rows):
///   1) Tool selection (line/arrow/circle/dot/cross/rect/text) – 'move' tool is excluded.
///   2) Color selection (single-select with highlight).
///   3) Control buttons (toggle annotation mode, undo, redo, clear all annotations, screenshot).
class AnnotationToolbar extends StatefulWidget {
  const AnnotationToolbar({
    super.key,
    required this.annotationManager,
    required this.isAnnotationMode,
    required this.onToggleAnnotationMode,
  });

  final AnnotationManager annotationManager;

  /// Indicates whether the full annotation mode is active.
  final bool isAnnotationMode;

  /// Callback to toggle annotation mode on/off.
  final VoidCallback onToggleAnnotationMode;

  @override
  State<AnnotationToolbar> createState() => _AnnotationToolbarState();
}

class _AnnotationToolbarState extends State<AnnotationToolbar> {
  final List<Color> _colorOptions = const <Color>[
    Colors.white, // 1st color
    Colors.black, // 2nd color
    Colors.grey, // 3rd color, added between white and red (after black)
    Colors.red, // 4th color, shifted from original 3rd position
    Colors.yellow, // 5th color
    Colors.blue, // 6th color
    Colors.green, // 7th color
    Colors.pink, // 8th color, added after green
    Colors.purple, // 9th color, shifted from original 7th position
    Colors.indigo, // 10th color
  ];

  /// Takes a screenshot and saves it to the specified [storageLocation]
  /// with an optional [filename].
  Future<void> _takeScreenshot(String storageLocation,
      [String? filename]) async {
    await ScreenshotService.takeScreenshot(storageLocation, filename);
  }

  /// Shows a confirmation dialog before clearing all annotations.
  Future<bool?> _showClearConfirmationDialog(BuildContext context) async {
    return showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Confirm Clear'),
        content: const Text('Are you sure you want to clear all annotations?'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(S.of(context).no),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(S.of(context).yes),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Show full toolbar if annotation mode is active,
    // otherwise show a single toggle button.
    return Container(
      color: Colors.grey[850],
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: widget.isAnnotationMode
          ? _buildExpandedToolbar(context)
          : _buildCollapsedToolbar(context),
    );
  }

  /// Builds the collapsed toolbar with just one button.
  Widget _buildCollapsedToolbar(BuildContext context) {
    return Center(
      child: IconButton(
        tooltip: 'Enter Annotation Mode',
        icon: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          transitionBuilder: (Widget child, Animation<double> animation) {
            return ScaleTransition(scale: animation, child: child);
          },
          // Use a regular (outlined) icon when collapsed.
          child: const Icon(
            FluentIcons.draw_image_24_regular,
            key: ValueKey<String>('annotation_off_collapsed'),
            color: Colors.white,
          ),
        ),
        onPressed: widget.onToggleAnnotationMode,
      ),
    );
  }

  /// Builds the expanded toolbar with three rows.
  Widget _buildExpandedToolbar(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _buildToolRow(context),
        const SizedBox(height: 4),
        _buildColorRow(context),
        const SizedBox(height: 4),
        _buildControlRow(context),
      ],
    );
  }

  /// Builds the first row: tool selection (excluding the 'move' tool).
  Widget _buildToolRow(BuildContext context) {
    final List<AnnotationTool> tools = AnnotationTool.values
        .where((AnnotationTool tool) => tool != AnnotationTool.move)
        .toList();
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: tools.map((AnnotationTool tool) {
        final bool isSelected = (widget.annotationManager.currentTool == tool);
        return IconButton(
          icon: Icon(
            _iconForTool(tool),
            color: isSelected ? Colors.yellow : Colors.white,
          ),
          onPressed: () {
            setState(() {
              widget.annotationManager.currentTool = tool;
            });
          },
          tooltip: tool.toString(),
        );
      }).toList(),
    );
  }

  /// Builds the second row: color selection icons.
  Widget _buildColorRow(BuildContext context) {
    final Color currentColor = widget.annotationManager.currentColor;
    // If a shape is selected, use its color as the active color.
    final AnnotationShape? selected = widget.annotationManager.selectedShape;
    final Color activeColor = selected?.color ?? currentColor;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: _colorOptions.map((Color color) {
          final bool isSelected = (color == activeColor);
          return GestureDetector(
            onTap: () {
              setState(() {
                if (selected != null) {
                  widget.annotationManager.changeColor(selected, color);
                } else {
                  widget.annotationManager.currentColor = color;
                }
              });
            },
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 6),
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: isSelected
                    ? Border.all(color: Colors.white, width: 3)
                    : null,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  /// Builds the third row: control buttons.
  /// Contains:
  /// - Toggle annotation mode button (exit icon when in annotation mode)
  /// - Undo button
  /// - Redo button
  /// - Clear annotations button (with confirmation dialog)
  /// - Screenshot button
  /// Note: Move tool button is hidden but functionality is retained.
  Widget _buildControlRow(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: <Widget>[
        // Toggle annotation mode with an exit icon.
        IconButton(
          tooltip: 'Exit Annotation Mode',
          icon: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (Widget child, Animation<double> animation) {
              return ScaleTransition(scale: animation, child: child);
            },
            // Use an exit arrow icon instead of a filled edit icon.
            child: const Icon(
              FluentIcons.games_24_regular, // Changed to games icon
              key: ValueKey<String>('annotation_exit_expanded'),
              color: Colors.white,
            ),
          ),
          onPressed: widget.onToggleAnnotationMode,
        ),
        // Undo button.
        IconButton(
          tooltip: 'Undo',
          icon: const Icon(
            FluentIcons.arrow_undo_24_regular,
            color: Colors.white,
          ),
          onPressed: () {
            setState(() {
              widget.annotationManager.undo();
            });
          },
        ),
        // Redo button.
        IconButton(
          tooltip: 'Redo',
          icon: const Icon(
            FluentIcons.arrow_redo_24_regular,
            color: Colors.white,
          ),
          onPressed: () {
            setState(() {
              widget.annotationManager.redo();
            });
          },
        ),
        // Clear annotations button with confirmation.
        IconButton(
          tooltip: 'Clear all annotations',
          icon: const Icon(
            FluentIcons.delete_24_regular,
            color: Colors.white,
          ),
          onPressed: () async {
            final bool? confirmed = await _showClearConfirmationDialog(context);
            if (confirmed != null && confirmed) {
              // Changed to check for true explicitly
              setState(() {
                widget.annotationManager.clear();
              });
            }
          },
        ),
        // Screenshot button.
        IconButton(
          tooltip: 'Take Screenshot',
          icon: const Icon(
            FluentIcons.camera_24_regular,
            color: Colors.white,
          ),
          onPressed: () {
            _takeScreenshot("gallery");
          },
        ),
      ],
    );
  }

  /// Maps each AnnotationTool to a FluentUI icon.
  IconData _iconForTool(AnnotationTool tool) {
    switch (tool) {
      case AnnotationTool.line:
        return FluentIcons.line_horizontal_1_24_regular;
      case AnnotationTool.arrow:
        return FluentIcons.arrow_right_24_regular;
      case AnnotationTool.circle:
        return FluentIcons.circle_24_regular;
      case AnnotationTool.dot:
        return FluentIcons.circle_small_24_filled;
      case AnnotationTool.cross:
        return FluentIcons.dismiss_24_regular;
      case AnnotationTool.rect:
        return FluentIcons.rectangle_landscape_24_regular;
      case AnnotationTool.text:
        return FluentIcons.text_font_24_regular;
      case AnnotationTool.move:
        return FluentIcons.arrow_move_24_regular;
    }
  }
}
