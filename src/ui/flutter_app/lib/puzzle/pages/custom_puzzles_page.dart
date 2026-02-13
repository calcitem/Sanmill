// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// custom_puzzles_page.dart
//
// Page for managing user-created custom puzzles

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_flutter.dart' show Box;

import '../../appearance_settings/models/color_settings.dart';
import '../../generated/intl/l10n.dart';
import '../../shared/database/database.dart';
import '../../shared/themes/app_theme.dart';
import '../models/puzzle_models.dart';
import '../services/puzzle_export_service.dart';
import '../services/puzzle_manager.dart';
import '../widgets/puzzle_card.dart';
import 'puzzle_creation_page.dart';
import 'puzzle_page.dart';

/// Page for managing custom puzzles
class CustomPuzzlesPage extends StatefulWidget {
  const CustomPuzzlesPage({super.key});

  @override
  State<CustomPuzzlesPage> createState() => _CustomPuzzlesPageState();
}

class _CustomPuzzlesPageState extends State<CustomPuzzlesPage> {
  final PuzzleManager _puzzleManager = PuzzleManager();

  // Multi-select mode
  bool _isMultiSelectMode = false;
  final Set<String> _selectedPuzzleIds = <String>{};

  @override
  Widget build(BuildContext context) {
    final S s = S.of(context);

    return ValueListenableBuilder<Box<ColorSettings>>(
      valueListenable: DB().listenColorSettings,
      builder: (BuildContext context, Box<ColorSettings> box, Widget? child) {
        final ColorSettings colors = box.get(
          DB.colorSettingsKey,
          defaultValue: const ColorSettings(),
        )!;
        final bool useDarkSettingsUi = AppTheme.shouldUseDarkSettingsUi(colors);
        final ThemeData settingsTheme = useDarkSettingsUi
            ? AppTheme.buildAccessibleSettingsDarkTheme(colors)
            : Theme.of(context);

        // Use Builder to ensure the context has the correct theme.
        // This prevents computing text styles from a context outside the Theme wrapper.
        return Theme(
          data: settingsTheme,
          child: Builder(
            builder: (BuildContext context) {
              return Scaffold(
                backgroundColor: useDarkSettingsUi
                    ? settingsTheme.scaffoldBackgroundColor
                    : AppTheme.lightBackgroundColor,
                appBar: AppBar(
                  title: _isMultiSelectMode
                      ? Text(
                          s.puzzleSelectedCount(_selectedPuzzleIds.length),
                          style: useDarkSettingsUi
                              ? null
                              : AppTheme.appBarTheme.titleTextStyle,
                        )
                      : Text(
                          s.customPuzzles,
                          style: useDarkSettingsUi
                              ? null
                              : AppTheme.appBarTheme.titleTextStyle,
                        ),
                  leading: _isMultiSelectMode
                      ? IconButton(
                          icon: const Icon(FluentIcons.dismiss_24_regular),
                          onPressed: _toggleMultiSelectMode,
                        )
                      : null,
                  actions: <Widget>[
                    if (_isMultiSelectMode) ...<Widget>[
                      // Select all
                      IconButton(
                        icon: const Icon(FluentIcons.select_all_on_24_regular),
                        onPressed: _selectAllPuzzles,
                        tooltip: s.puzzleSelectAll,
                      ),
                      // Contribute selected
                      if (_selectedPuzzleIds.isNotEmpty)
                        IconButton(
                          icon: const Icon(FluentIcons.arrow_upload_24_regular),
                          onPressed: () => _contributeSelectedPuzzles(
                            context,
                            settingsTheme,
                          ),
                          tooltip: s.contributeToSanmill,
                        ),
                      // Export selected
                      if (_selectedPuzzleIds.isNotEmpty)
                        IconButton(
                          icon: const Icon(FluentIcons.share_24_regular),
                          onPressed: _exportSelectedPuzzles,
                          tooltip: s.puzzleExport,
                        ),
                      // Delete selected
                      if (_selectedPuzzleIds.isNotEmpty)
                        IconButton(
                          icon: const Icon(FluentIcons.delete_24_regular),
                          onPressed: () =>
                              _deleteSelectedPuzzles(context, settingsTheme),
                          tooltip: s.delete,
                        ),
                    ] else ...<Widget>[
                      // Import button (open file to import puzzles)
                      IconButton(
                        icon: const Icon(FluentIcons.folder_open_24_regular),
                        onPressed: _importPuzzles,
                        tooltip: s.puzzleImport,
                      ),
                      // Contribution info button
                      IconButton(
                        icon: const Icon(FluentIcons.info_24_regular),
                        onPressed: () =>
                            _showContributionInfo(context, settingsTheme),
                        tooltip: s.howToContribute,
                      ),
                      // Multi-select button
                      IconButton(
                        icon: const Icon(
                          FluentIcons.checkbox_checked_24_regular,
                        ),
                        onPressed: _toggleMultiSelectMode,
                        tooltip: s.puzzleSelect,
                      ),
                    ],
                  ],
                ),
                floatingActionButton: _isMultiSelectMode
                    ? null
                    : FloatingActionButton(
                        onPressed: _createNewPuzzle,
                        tooltip: s.puzzleCreateNew,
                        child: const Icon(FluentIcons.add_24_regular),
                      ),
                body: ValueListenableBuilder<PuzzleSettings>(
                  valueListenable: _puzzleManager.settingsNotifier,
                  builder: (BuildContext context, PuzzleSettings settings, _) {
                    final List<PuzzleInfo> customPuzzles = _puzzleManager
                        .getCustomPuzzles();

                    if (customPuzzles.isEmpty) {
                      return _buildEmptyState(context, s);
                    }

                    return ListView.builder(
                      padding: const EdgeInsets.all(8.0),
                      itemCount: customPuzzles.length,
                      itemBuilder: (BuildContext context, int index) {
                        final PuzzleInfo puzzle = customPuzzles[index];
                        final PuzzleProgress? progress = settings.getProgress(
                          puzzle.id,
                        );
                        final bool isSelected = _selectedPuzzleIds.contains(
                          puzzle.id,
                        );

                        return PuzzleCard(
                          puzzle: puzzle,
                          progress: progress,
                          onTap: _isMultiSelectMode
                              ? () => _togglePuzzleSelection(puzzle.id)
                              : () => _openPuzzle(puzzle),
                          onLongPress: _isMultiSelectMode
                              ? null
                              : () {
                                  _toggleMultiSelectMode();
                                  _togglePuzzleSelection(puzzle.id);
                                },
                          isSelected: _isMultiSelectMode ? isSelected : null,
                          showCustomBadge: true,
                          onEdit: !_isMultiSelectMode
                              ? () => _editPuzzle(puzzle)
                              : null,
                          onDelete: !_isMultiSelectMode
                              ? () => _deleteSinglePuzzle(puzzle.id)
                              : null,
                        );
                      },
                    );
                  },
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(BuildContext context, S s) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(
              FluentIcons.puzzle_piece_24_regular,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              s.noCustomPuzzles,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              s.noCustomPuzzlesHint,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                ElevatedButton.icon(
                  onPressed: _createNewPuzzle,
                  icon: const Icon(FluentIcons.add_24_regular),
                  label: Text(s.puzzleCreateNew),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: _importPuzzles,
                  icon: const Icon(FluentIcons.folder_open_24_regular),
                  label: Text(s.puzzleImport),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _toggleMultiSelectMode() {
    setState(() {
      _isMultiSelectMode = !_isMultiSelectMode;
      if (!_isMultiSelectMode) {
        _selectedPuzzleIds.clear();
      }
    });
  }

  void _togglePuzzleSelection(String puzzleId) {
    setState(() {
      if (_selectedPuzzleIds.contains(puzzleId)) {
        _selectedPuzzleIds.remove(puzzleId);
      } else {
        _selectedPuzzleIds.add(puzzleId);
      }
    });
  }

  void _selectAllPuzzles() {
    setState(() {
      _selectedPuzzleIds.clear();
      _selectedPuzzleIds.addAll(
        _puzzleManager.getCustomPuzzles().map((PuzzleInfo p) => p.id),
      );
    });
  }

  Future<void> _exportSelectedPuzzles() async {
    if (_selectedPuzzleIds.isEmpty) {
      return;
    }

    final List<PuzzleInfo> puzzlesToExport = _selectedPuzzleIds
        .map((String id) => _puzzleManager.getPuzzleById(id))
        .whereType<PuzzleInfo>()
        .toList();

    if (puzzlesToExport.isEmpty) {
      return;
    }

    final S s = S.of(context);
    final bool success = await _puzzleManager.exportAndSharePuzzles(
      puzzlesToExport,
      shareText: s.puzzleShareMessage(puzzlesToExport.length),
      shareSubject: s.puzzleShareSubject(puzzlesToExport.length),
    );

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? S.of(context).puzzleExportSuccess(puzzlesToExport.length)
              : S.of(context).puzzleExportFailed,
        ),
        backgroundColor: success ? Colors.green : Colors.red,
      ),
    );

    if (success) {
      setState(() {
        _isMultiSelectMode = false;
        _selectedPuzzleIds.clear();
      });
    }
  }

  Future<void> _deleteSelectedPuzzles(
    BuildContext context,
    ThemeData settingsTheme,
  ) async {
    if (_selectedPuzzleIds.isEmpty) {
      return;
    }

    // Confirm deletion
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        final S s = S.of(dialogContext);
        return Theme(
          data: settingsTheme,
          child: AlertDialog(
            title: Text(s.confirm),
            content: Text(s.puzzleDeleteConfirm(_selectedPuzzleIds.length)),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(s.cancel),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: Text(s.delete),
              ),
            ],
          ),
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    final int deletedCount = _puzzleManager.deletePuzzles(
      _selectedPuzzleIds.toList(),
    );

    if (!mounted || !context.mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(S.of(context).puzzleDeleted(deletedCount)),
        backgroundColor: Colors.green,
      ),
    );

    setState(() {
      _isMultiSelectMode = false;
      _selectedPuzzleIds.clear();
    });
  }

  /// Delete a single puzzle (called from swipe action)
  void _deleteSinglePuzzle(String puzzleId) {
    // Delete the puzzle immediately (confirmation already shown in Dismissible)
    final int deletedCount = _puzzleManager.deletePuzzles(<String>[puzzleId]);

    if (!mounted) {
      return;
    }

    if (deletedCount > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(S.of(context).puzzleDeleted(deletedCount)),
          backgroundColor: Colors.green,
        ),
      );
    }

    setState(() {});
  }

  Future<void> _importPuzzles() async {
    final ImportResult result = await _puzzleManager.importPuzzles();

    if (!mounted) {
      return;
    }

    if (result.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            S.of(context).puzzleImportSuccess(result.puzzles.length),
          ),
          backgroundColor: Colors.green,
        ),
      );
      setState(() {});
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.errorMessage ?? S.of(context).puzzleImportFailed,
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _createNewPuzzle() async {
    final bool? created = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (BuildContext context) => const PuzzleCreationPage(),
      ),
    );

    if (created ?? false) {
      setState(() {});
    }
  }

  Future<void> _editPuzzle(PuzzleInfo puzzle) async {
    final bool? updated = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (BuildContext context) =>
            PuzzleCreationPage(puzzleToEdit: puzzle),
      ),
    );

    if (updated ?? false) {
      setState(() {});
    }
  }

  void _openPuzzle(PuzzleInfo puzzle) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => PuzzlePage(puzzle: puzzle),
      ),
    );
  }

  Future<void> _contributeSelectedPuzzles(
    BuildContext context,
    ThemeData settingsTheme,
  ) async {
    if (_selectedPuzzleIds.isEmpty) {
      return;
    }

    final List<PuzzleInfo> puzzlesToContribute = _selectedPuzzleIds
        .map((String id) => _puzzleManager.getPuzzleById(id))
        .whereType<PuzzleInfo>()
        .toList();

    if (puzzlesToContribute.isEmpty) {
      return;
    }

    // Validate puzzles before contribution
    final List<String> invalidPuzzles = <String>[];
    for (final PuzzleInfo puzzle in puzzlesToContribute) {
      final String? errorKey = PuzzleExportService.validateForContribution(
        puzzle,
      );
      if (errorKey != null) {
        // Translate error key to localized message
        final String localizedError = _getLocalizedValidationError(
          context,
          errorKey,
        );
        invalidPuzzles.add('${puzzle.title}: $localizedError');
      }
    }

    // If there are validation errors, show them
    if (invalidPuzzles.isNotEmpty && mounted) {
      await showDialog<void>(
        context: context,
        builder: (BuildContext dialogContext) {
          return Theme(
            data: settingsTheme,
            child: AlertDialog(
              title: Text(S.of(dialogContext).puzzleValidationErrors),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(S.of(dialogContext).puzzleValidationErrorsMessage),
                    const SizedBox(height: 12),
                    ...invalidPuzzles.map(
                      (String error) => Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: Text(error),
                      ),
                    ),
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text(S.of(dialogContext).ok),
                ),
              ],
            ),
          );
        },
      );
      return;
    }

    // Show contribution info dialog before exporting
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return Theme(
          data: settingsTheme,
          child: AlertDialog(
            title: Text(S.of(dialogContext).puzzleContributeDialogTitle),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    S
                        .of(dialogContext)
                        .puzzleContributeCount(puzzlesToContribute.length),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  Text(S.of(dialogContext).puzzleContributeWhatNext),
                  const SizedBox(height: 8),
                  Text(S.of(dialogContext).puzzleContributeStep1),
                  Text(S.of(dialogContext).puzzleContributeStep2),
                  Text(S.of(dialogContext).puzzleContributeStep3),
                  Text(S.of(dialogContext).puzzleContributeStep4),
                  Text(S.of(dialogContext).puzzleContributeStep5),
                  const SizedBox(height: 16),
                  Text(
                    S.of(dialogContext).puzzleContributeLicense,
                    style: const TextStyle(
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(S.of(dialogContext).cancel),
              ),
              ElevatedButton.icon(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                icon: const Icon(FluentIcons.arrow_upload_24_regular),
                label: Text(S.of(dialogContext).puzzleExportForContribution),
              ),
            ],
          ),
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    if (!mounted || !context.mounted) {
      return;
    }

    // Export puzzles in contribution format
    final S s = S.of(context);
    final bool success = puzzlesToContribute.length == 1
        ? await PuzzleExportService.shareForContribution(
            puzzlesToContribute.first,
            shareText: s.puzzleContributionShareText,
            shareSubject: s.puzzleContributionShareSubject(
              puzzlesToContribute.first.title,
            ),
          )
        : await PuzzleExportService.shareMultipleForContribution(
            puzzlesToContribute,
            shareText: s.puzzleContributionsShareText,
            shareSubject: s.puzzleContributionsShareSubject(
              puzzlesToContribute.length,
            ),
          );

    if (!mounted || !context.mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? 'Exported ${puzzlesToContribute.length} puzzle(s) for contribution!'
              : 'Failed to export puzzles',
        ),
        backgroundColor: success ? Colors.green : Colors.red,
        action: success
            ? SnackBarAction(
                label: 'View Guide',
                textColor: Colors.white,
                onPressed: () => _showContributionInfo(context, settingsTheme),
              )
            : null,
      ),
    );

    if (success) {
      setState(() {
        _isMultiSelectMode = false;
        _selectedPuzzleIds.clear();
      });
    }
  }

  void _showContributionInfo(BuildContext context, ThemeData settingsTheme) {
    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        final S s = S.of(dialogContext);
        final Color primary = Theme.of(dialogContext).colorScheme.primary;
        final Color onSurfaceVariant = Theme.of(
          dialogContext,
        ).colorScheme.onSurfaceVariant;
        return Theme(
          data: settingsTheme,
          child: AlertDialog(
            title: Row(
              children: <Widget>[
                Icon(
                  FluentIcons.info_24_regular,
                  color: primary, // Use primary color
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    s.puzzleContributeInfo,
                    style: Theme.of(dialogContext).textTheme.titleLarge,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            content: ConstrainedBox(
              // Use ConstrainedBox instead of fixed width to avoid overflow on small screens
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(dialogContext).size.width * 0.85,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      s.puzzleContributeHelp,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      s.puzzleContributeQuickStart,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildInfoStep(
                      dialogContext,
                      '1',
                      s.puzzleContributeStep1Title,
                      s.puzzleContributeStep1Desc,
                    ),
                    const SizedBox(height: 8),
                    _buildInfoStep(
                      dialogContext,
                      '2',
                      s.puzzleContributeStep2Title,
                      s.puzzleContributeStep2Desc,
                    ),
                    const SizedBox(height: 8),
                    _buildInfoStep(
                      dialogContext,
                      '3',
                      s.puzzleContributeStep3Title,
                      s.puzzleContributeStep3Desc,
                    ),
                    const SizedBox(height: 8),
                    _buildInfoStep(
                      dialogContext,
                      '4',
                      s.puzzleContributeStep4Title,
                      s.puzzleContributeStep4Desc,
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        // Theme-aware surface to keep text readable in both light and dark modes.
                        color: primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: primary.withValues(alpha: 0.25),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Icon(
                                FluentIcons.document_24_regular,
                                size: 16,
                                color: primary, // Use primary color
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  s.puzzleContributeFullDocs,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: primary,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            s.puzzleContributeDocsDesc,
                            style: TextStyle(
                              fontSize: 13,
                              color: onSurfaceVariant,
                            ),
                            softWrap: true,
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      s.puzzleContributeQualityRequirements,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      s.puzzleContributeReqClearSolution,
                      style: const TextStyle(fontSize: 13),
                    ),
                    Text(
                      s.puzzleContributeReqMetadata,
                      style: const TextStyle(fontSize: 13),
                    ),
                    Text(
                      s.puzzleContributeReqAttribution,
                      style: const TextStyle(fontSize: 13),
                    ),
                    Text(
                      s.puzzleContributeReqDifficulty,
                      style: const TextStyle(fontSize: 13),
                    ),
                    Text(
                      s.puzzleContributeReqInstructive,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(s.close),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  _toggleMultiSelectMode();
                },
                child: Text(s.puzzleStartContributing),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInfoStep(
    BuildContext context,
    String number,
    String title,
    String description,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary, // Use primary color
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Text(
              number,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                description,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Get localized validation error message from error key
  String _getLocalizedValidationError(BuildContext context, String errorKey) {
    final S s = S.of(context);
    switch (errorKey) {
      case 'puzzleValidationTitleRequired':
        return s.puzzleValidationTitleRequired;
      case 'puzzleValidationDescriptionRequired':
        return s.puzzleValidationDescriptionRequired;
      case 'puzzleValidationPositionRequired':
        return s.puzzleValidationPositionRequired;
      case 'puzzleValidationInvalidFen':
        return s.puzzleValidationInvalidFen;
      case 'puzzleValidationSolutionRequired':
        return s.puzzleValidationSolutionRequired;
      case 'puzzleValidationTitleTooShort':
        return s.puzzleValidationTitleTooShort;
      case 'puzzleValidationTitleTooLong':
        return s.puzzleValidationTitleTooLong;
      case 'puzzleValidationDescriptionTooShort':
        return s.puzzleValidationDescriptionTooShort;
      case 'puzzleValidationDescriptionTooLong':
        return s.puzzleValidationDescriptionTooLong;
      case 'puzzleValidationAuthorRequired':
        return s.puzzleValidationAuthorRequired;
      default:
        return errorKey; // Fallback to key itself
    }
  }
}
