// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../generated/intl/l10n.dart';
import 'mill_opening_recognizer.dart';
import 'opening_book_source_models.dart';
import 'opening_book_studio_repository.dart';

class OpeningBookStudioPage extends StatefulWidget {
  const OpeningBookStudioPage({
    super.key,
    this.repository = const OpeningBookStudioRepository(),
    this.initialPackage,
    this.showSnackBars = true,
  });

  final OpeningBookStudioRepository repository;
  final SanmillOpeningBookSourcePackage? initialPackage;
  final bool showSnackBars;

  @override
  State<OpeningBookStudioPage> createState() => _OpeningBookStudioPageState();
}

class _OpeningBookStudioPageState extends State<OpeningBookStudioPage> {
  SanmillOpeningBookSourcePackage? _package;
  int _selectedIndex = 0;
  Object? _loadError;
  bool _loading = true;
  bool _busy = false;

  SanmillOpeningSourceEntry? get _selectedOpening {
    final SanmillOpeningBookSourcePackage? package = _package;
    if (package == null || package.openings.isEmpty) {
      return null;
    }
    return package.openings[_boundedSelectedIndex(package)];
  }

  int _boundedSelectedIndex(SanmillOpeningBookSourcePackage package) {
    assert(package.openings.isNotEmpty, 'Opening list must not be empty.');
    return _selectedIndex.clamp(0, package.openings.length - 1);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final SanmillOpeningBookSourcePackage package =
          widget.initialPackage ?? await widget.repository.loadNmmSource();
      if (!mounted) {
        return;
      }
      setState(() {
        _package = package;
        _selectedIndex = 0;
        _loadError = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadError = e;
        _loading = false;
      });
    }
  }

  void _showSnack(String message) {
    if (!widget.showSnackBars) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _replacePackage(SanmillOpeningBookSourcePackage package) {
    setState(() {
      _package = package;
      _selectedIndex = package.openings.isEmpty
          ? 0
          : _selectedIndex.clamp(0, package.openings.length - 1);
    });
  }

  void _replaceOpening(SanmillOpeningSourceEntry opening) {
    final SanmillOpeningBookSourcePackage package = _package!;
    final List<SanmillOpeningSourceEntry> openings = package.openings.toList(
      growable: true,
    );
    openings[_boundedSelectedIndex(package)] = opening;
    _replacePackage(package.copyWith(openings: openings));
  }

  void _addOpening() {
    final SanmillOpeningBookSourcePackage package =
        _package ??
        SanmillOpeningBookSourcePackage.nmm(
          openings: const <SanmillOpeningSourceEntry>[],
        );
    final List<SanmillOpeningSourceEntry> openings = package.openings.toList(
      growable: true,
    );
    openings.add(SanmillOpeningSourceEntry.empty(openings.length + 1));
    setState(() {
      _package = package.copyWith(openings: openings);
      _selectedIndex = openings.length - 1;
    });
  }

  void _deleteSelectedOpening() {
    final SanmillOpeningBookSourcePackage? package = _package;
    if (package == null || package.openings.isEmpty) {
      return;
    }
    final List<SanmillOpeningSourceEntry> openings = package.openings.toList(
      growable: true,
    );
    openings.removeAt(_boundedSelectedIndex(package));
    setState(() {
      _package = package.copyWith(openings: openings);
      _selectedIndex = openings.isEmpty
          ? 0
          : math.min(_selectedIndex, openings.length - 1);
    });
  }

  void _addVariation(SanmillOpeningSourceEntry opening) {
    final List<SanmillOpeningVariation> variations = opening.line.variations
        .toList(growable: true);
    final int index = variations.length + 1;
    variations.add(
      SanmillOpeningVariation(
        id: '${opening.id}-variation-$index',
        name: 'Variation $index',
        afterPly: math.min(opening.line.moves.length, 2),
        moves: const <String>['g7'],
      ),
    );
    _replaceOpening(
      opening.copyWith(line: opening.line.copyWith(variations: variations)),
    );
  }

  void _replaceVariation(
    SanmillOpeningSourceEntry opening,
    int index,
    SanmillOpeningVariation variation,
  ) {
    final List<SanmillOpeningVariation> variations = opening.line.variations
        .toList(growable: true);
    variations[index] = variation;
    _replaceOpening(
      opening.copyWith(line: opening.line.copyWith(variations: variations)),
    );
  }

  void _deleteVariation(SanmillOpeningSourceEntry opening, int index) {
    final List<SanmillOpeningVariation> variations = opening.line.variations
        .toList(growable: true);
    variations.removeAt(index);
    _replaceOpening(
      opening.copyWith(line: opening.line.copyWith(variations: variations)),
    );
  }

  Future<void> _saveAsset() async {
    final SanmillOpeningBookSourcePackage package = _package!;
    final OpeningBookSourceValidationResult validation =
        validateSanmillOpeningBookSource(package);
    if (!validation.isValid) {
      _showSnack(S.of(context).openingBookStudioValidationFailed);
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.repository.saveNmmSource(package);
      if (mounted) {
        _showSnack(S.of(context).openingBookStudioAssetSaved);
      }
    } catch (e) {
      if (mounted) {
        _showSnack(e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _export() async {
    final SanmillOpeningBookSourcePackage package = _package!;
    final OpeningBookSourceValidationResult validation =
        validateSanmillOpeningBookSource(package);
    if (!validation.isValid) {
      _showSnack(S.of(context).openingBookStudioValidationFailed);
      return;
    }
    setState(() => _busy = true);
    try {
      final bool? exported = await widget.repository.exportSourcePackage(
        package,
        dialogTitle: S.of(context).openingBookStudioExportDialogTitle,
      );
      if (mounted) {
        _showSnack(
          exported == null
              ? S.of(context).openingBookStudioImportCancelled
              : exported
              ? S.of(context).openingBookStudioExported
              : S.of(context).openingBookStudioExportUnavailable,
        );
      }
    } catch (e) {
      if (mounted) {
        _showSnack(e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _import() async {
    setState(() => _busy = true);
    try {
      final SanmillOpeningBookSourcePackage? package = await widget.repository
          .importSourcePackage();
      if (!mounted) {
        return;
      }
      if (package == null) {
        _showSnack(S.of(context).openingBookStudioImportCancelled);
      } else {
        setState(() {
          _package = package;
          _selectedIndex = 0;
        });
        _showSnack(S.of(context).openingBookStudioImported);
      }
    } catch (e) {
      if (mounted) {
        _showSnack(e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final S l10n = S.of(context);
    return Scaffold(
      key: const Key('opening_book_studio_page'),
      appBar: AppBar(
        title: Text(l10n.openingBookStudio),
        actions: <Widget>[
          IconButton(
            key: const Key('opening_book_studio_import_button'),
            tooltip: l10n.import,
            onPressed: _busy || _loading ? null : _import,
            icon: const Icon(Icons.file_open),
          ),
          IconButton(
            key: const Key('opening_book_studio_export_button'),
            tooltip: l10n.export,
            onPressed: _busy || _package == null ? null : _export,
            icon: const Icon(Icons.ios_share),
          ),
          IconButton(
            key: const Key('opening_book_studio_save_asset_button'),
            tooltip: l10n.openingBookStudioSaveAsset,
            onPressed: _busy || _package == null ? null : _saveAsset,
            icon: const Icon(Icons.save),
          ),
        ],
      ),
      body: RepaintBoundary(
        key: const Key('opening_book_studio_repaint_boundary'),
        child: _buildBody(l10n),
      ),
    );
  }

  Widget _buildBody(S l10n) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('${l10n.openingBookStudioLoadFailed}\n$_loadError'),
        ),
      );
    }

    final SanmillOpeningBookSourcePackage package = _package!;
    final OpeningBookSourceValidationResult validation =
        validateSanmillOpeningBookSource(package);

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool wide = constraints.maxWidth >= 900;
        final Widget openingList = _OpeningListPanel(
          package: package,
          selectedIndex: _selectedIndex,
          onSelect: (int index) => setState(() => _selectedIndex = index),
          onAdd: _addOpening,
        );
        final Widget editor = _selectedOpening == null
            ? Center(child: Text(l10n.openingBookStudioNoOpeningSelected))
            : _OpeningEditorPanel(
                opening: _selectedOpening!,
                package: package,
                validation: validation,
                onChanged: _replaceOpening,
                onDelete: _deleteSelectedOpening,
                onAddVariation: _addVariation,
                onChangedVariation: _replaceVariation,
                onDeleteVariation: _deleteVariation,
              );
        final Widget validationPanel = _ValidationPanel(
          package: package,
          validation: validation,
        );

        final Widget content = wide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  SizedBox(width: 320, child: openingList),
                  const VerticalDivider(width: 1),
                  Expanded(flex: 3, child: editor),
                  const VerticalDivider(width: 1),
                  SizedBox(width: 320, child: validationPanel),
                ],
              )
            : ListView(
                children: <Widget>[
                  SizedBox(height: 280, child: openingList),
                  const Divider(height: 1),
                  SizedBox(height: 640, child: editor),
                  const Divider(height: 1),
                  SizedBox(height: 320, child: validationPanel),
                ],
              );

        return Stack(
          children: <Widget>[
            content,
            if (_busy)
              const Positioned.fill(
                child: ColoredBox(
                  color: Color(0x33000000),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _OpeningListPanel extends StatelessWidget {
  const _OpeningListPanel({
    required this.package,
    required this.selectedIndex,
    required this.onSelect,
    required this.onAdd,
  });

  final SanmillOpeningBookSourcePackage package;
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final S l10n = S.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _PanelHeader(
          title: l10n.openingBookStudioOpeningList,
          trailing: IconButton(
            key: const Key('opening_book_studio_add_opening_button'),
            tooltip: l10n.openingBookStudioAddOpening,
            onPressed: onAdd,
            icon: const Icon(Icons.add),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            l10n.openingBookStudioSourceSummary(
              package.book.name,
              package.openings.length,
            ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        Expanded(
          child: ListView.builder(
            key: const Key('opening_book_studio_opening_list'),
            itemCount: package.openings.length,
            itemBuilder: (BuildContext context, int index) {
              final SanmillOpeningSourceEntry opening = package.openings[index];
              return ListTile(
                key: Key('opening_book_studio_opening_$index'),
                selected: index == selectedIndex,
                dense: true,
                title: Text(opening.name),
                subtitle: Text(
                  '${formatOpeningMoveList(opening.line.moves)} | ${opening.favoredSide}',
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => onSelect(index),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _OpeningEditorPanel extends StatelessWidget {
  const _OpeningEditorPanel({
    required this.opening,
    required this.package,
    required this.validation,
    required this.onChanged,
    required this.onDelete,
    required this.onAddVariation,
    required this.onChangedVariation,
    required this.onDeleteVariation,
  });

  final SanmillOpeningSourceEntry opening;
  final SanmillOpeningBookSourcePackage package;
  final OpeningBookSourceValidationResult validation;
  final ValueChanged<SanmillOpeningSourceEntry> onChanged;
  final VoidCallback onDelete;
  final ValueChanged<SanmillOpeningSourceEntry> onAddVariation;
  final void Function(
    SanmillOpeningSourceEntry opening,
    int index,
    SanmillOpeningVariation variation,
  )
  onChangedVariation;
  final void Function(SanmillOpeningSourceEntry opening, int index)
  onDeleteVariation;

  @override
  Widget build(BuildContext context) {
    final S l10n = S.of(context);
    return SingleChildScrollView(
      key: const Key('opening_book_studio_editor'),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  l10n.openingBookStudioEditor,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                key: const Key('opening_book_studio_delete_opening_button'),
                tooltip: l10n.openingBookStudioDeleteOpening,
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: <Widget>[
              SizedBox(
                width: 280,
                child: _TextField(
                  keyValue: 'opening_book_studio_id_field_${opening.id}',
                  label: 'ID',
                  value: opening.id,
                  onChanged: (String value) =>
                      onChanged(opening.copyWith(id: value.trim())),
                ),
              ),
              SizedBox(
                width: 360,
                child: _TextField(
                  keyValue: 'opening_book_studio_name_field_${opening.id}',
                  publicKey: const Key('opening_book_studio_name_field'),
                  label: l10n.openingBookStudioOpeningName,
                  value: opening.name,
                  onChanged: (String value) =>
                      onChanged(opening.copyWith(name: value)),
                ),
              ),
              SizedBox(
                width: 260,
                child: _TextField(
                  keyValue: 'opening_book_studio_family_field_${opening.id}',
                  label: l10n.openingBookStudioFamily,
                  value: opening.family,
                  onChanged: (String value) =>
                      onChanged(opening.copyWith(family: value)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              SizedBox(
                width: 160,
                child: _ChoiceField(
                  label: l10n.openingBookStudioSide,
                  value: opening.side,
                  values: const <String>['W', 'B', 'both'],
                  onChanged: (String value) =>
                      onChanged(opening.copyWith(side: value)),
                ),
              ),
              SizedBox(
                width: 180,
                child: _ChoiceField(
                  label: l10n.openingBookStudioFavoredSide,
                  value: opening.favoredSide,
                  values: const <String>['W', 'B', 'equal'],
                  onChanged: (String value) =>
                      onChanged(opening.copyWith(favoredSide: value)),
                ),
              ),
              SizedBox(
                width: 320,
                child: _ConfidenceSlider(
                  value: opening.confidence,
                  onChanged: (double value) =>
                      onChanged(opening.copyWith(confidence: value)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _TextField(
            keyValue: 'opening_book_studio_line_moves_field_${opening.id}',
            publicKey: const Key('opening_book_studio_line_moves_field'),
            label: l10n.openingBookStudioLineMoves,
            value: formatOpeningMoveList(opening.line.moves),
            onChanged: (String value) => onChanged(
              opening.copyWith(
                line: opening.line.copyWith(moves: parseOpeningMoveList(value)),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: <Widget>[
              SizedBox(
                width: 360,
                child: _TextField(
                  keyValue: 'opening_book_studio_aliases_field_${opening.id}',
                  label: l10n.openingBookStudioAliases,
                  value: opening.aliases.join(', '),
                  onChanged: (String value) =>
                      onChanged(opening.copyWith(aliases: _commaList(value))),
                ),
              ),
              SizedBox(
                width: 360,
                child: _TextField(
                  keyValue: 'opening_book_studio_tags_field_${opening.id}',
                  label: l10n.openingBookStudioTags,
                  value: opening.tags.join(', '),
                  onChanged: (String value) =>
                      onChanged(opening.copyWith(tags: _commaList(value))),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _TextField(
            keyValue: 'opening_book_studio_notes_field_${opening.id}',
            label: l10n.openingBookStudioStrategicNotes,
            value: opening.line.comment,
            maxLines: 3,
            onChanged: (String value) => onChanged(
              opening.copyWith(line: opening.line.copyWith(comment: value)),
            ),
          ),
          const SizedBox(height: 12),
          _TextField(
            keyValue: 'opening_book_studio_blunders_field_${opening.id}',
            label: l10n.openingBookStudioCommonBlunders,
            value: opening.commonBlunders.join(', '),
            onChanged: (String value) =>
                onChanged(opening.copyWith(commonBlunders: _commaList(value))),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: <Widget>[
              SizedBox(
                width: 360,
                child: _TextField(
                  keyValue: 'opening_book_studio_reply_w_field_${opening.id}',
                  label: l10n.openingBookStudioRecommendedWhite,
                  value: formatOpeningMoveList(
                    opening.recommendedResponses['W'] ?? const <String>[],
                  ),
                  onChanged: (String value) => onChanged(
                    opening.copyWith(
                      recommendedResponses: _updatedResponse(
                        opening.recommendedResponses,
                        'W',
                        parseOpeningMoveList(value),
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: 360,
                child: _TextField(
                  keyValue: 'opening_book_studio_reply_b_field_${opening.id}',
                  label: l10n.openingBookStudioRecommendedBlack,
                  value: formatOpeningMoveList(
                    opening.recommendedResponses['B'] ?? const <String>[],
                  ),
                  onChanged: (String value) => onChanged(
                    opening.copyWith(
                      recommendedResponses: _updatedResponse(
                        opening.recommendedResponses,
                        'B',
                        parseOpeningMoveList(value),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _StatsEditor(
            stats: opening.stats,
            onChanged: (SanmillOpeningStats stats) =>
                onChanged(opening.copyWith(stats: stats)),
          ),
          const SizedBox(height: 24),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  l10n.openingBookStudioVariations,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                key: const Key('opening_book_studio_add_variation_button'),
                tooltip: l10n.openingBookStudioAddVariation,
                onPressed: () => onAddVariation(opening),
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          for (int i = 0; i < opening.line.variations.length; i++)
            _VariationEditor(
              opening: opening,
              index: i,
              variation: opening.line.variations[i],
              onChanged: onChangedVariation,
              onDelete: onDeleteVariation,
            ),
          const SizedBox(height: 24),
          _OpeningPreview(opening: opening, package: package),
        ],
      ),
    );
  }
}

class _ValidationPanel extends StatelessWidget {
  const _ValidationPanel({required this.package, required this.validation});

  final SanmillOpeningBookSourcePackage package;
  final OpeningBookSourceValidationResult validation;

  @override
  Widget build(BuildContext context) {
    final S l10n = S.of(context);
    final TextTheme textTheme = Theme.of(context).textTheme;
    final List<String> lines = <String>[
      if (validation.isValid) l10n.openingBookStudioValidationPassed,
      ...validation.errors,
      ...validation.warnings,
    ];
    return ListView(
      key: const Key('opening_book_studio_validation_panel'),
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Text(l10n.openingBookStudioValidation, style: textTheme.titleLarge),
        const SizedBox(height: 12),
        Text('${package.format} v${package.schemaVersion}'),
        Text('${package.game}/${package.variant} | ${package.book.id}'),
        const SizedBox(height: 12),
        for (final String line in lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(
                  validation.isValid && line == lines.first
                      ? Icons.check_circle_outline
                      : validation.errors.contains(line)
                      ? Icons.error_outline
                      : Icons.info_outline,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(line)),
              ],
            ),
          ),
      ],
    );
  }
}

class _OpeningPreview extends StatelessWidget {
  const _OpeningPreview({required this.opening, required this.package});

  final SanmillOpeningSourceEntry opening;
  final SanmillOpeningBookSourcePackage package;

  @override
  Widget build(BuildContext context) {
    final S l10n = S.of(context);
    final MillOpeningRecognition recognition = MillOpeningRecognizer.recognize(
      opening.line.moves.take(math.min(4, opening.line.moves.length)).toList(),
      package.toOpeningEntries(),
    );
    final String status = recognition.status.name;
    final String nextMove = recognition.nextMove ?? '-';
    return DecoratedBox(
      key: const Key('opening_book_studio_preview'),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              l10n.openingBookStudioPreview,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text('${l10n.status}: $status'),
            Text('${l10n.openingBookStudioNextMove}: $nextMove'),
          ],
        ),
      ),
    );
  }
}

class _VariationEditor extends StatelessWidget {
  const _VariationEditor({
    required this.opening,
    required this.index,
    required this.variation,
    required this.onChanged,
    required this.onDelete,
  });

  final SanmillOpeningSourceEntry opening;
  final int index;
  final SanmillOpeningVariation variation;
  final void Function(
    SanmillOpeningSourceEntry opening,
    int index,
    SanmillOpeningVariation variation,
  )
  onChanged;
  final void Function(SanmillOpeningSourceEntry opening, int index) onDelete;

  @override
  Widget build(BuildContext context) {
    final S l10n = S.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: _TextField(
                      keyValue:
                          'opening_book_studio_variation_name_${variation.id}',
                      label: l10n.openingBookStudioVariationName,
                      value: variation.name,
                      onChanged: (String value) => onChanged(
                        opening,
                        index,
                        variation.copyWith(name: value),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: l10n.openingBookStudioDeleteVariation,
                    onPressed: () => onDelete(opening, index),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: <Widget>[
                  SizedBox(
                    width: 180,
                    child: _TextField(
                      keyValue:
                          'opening_book_studio_variation_after_${variation.id}',
                      label: l10n.openingBookStudioAfterPly,
                      value: variation.afterPly.toString(),
                      keyboardType: TextInputType.number,
                      onChanged: (String value) {
                        final int? parsed = int.tryParse(value);
                        if (parsed != null) {
                          onChanged(
                            opening,
                            index,
                            variation.copyWith(afterPly: parsed),
                          );
                        }
                      },
                    ),
                  ),
                  SizedBox(
                    width: 360,
                    child: _TextField(
                      keyValue:
                          'opening_book_studio_variation_moves_${variation.id}',
                      label: l10n.openingBookStudioVariationMoves,
                      value: formatOpeningMoveList(variation.moves),
                      onChanged: (String value) => onChanged(
                        opening,
                        index,
                        variation.copyWith(moves: parseOpeningMoveList(value)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _TextField(
                keyValue:
                    'opening_book_studio_variation_comment_${variation.id}',
                label: l10n.openingBookStudioStrategicNotes,
                value: variation.comment,
                onChanged: (String value) => onChanged(
                  opening,
                  index,
                  variation.copyWith(comment: value),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatsEditor extends StatelessWidget {
  const _StatsEditor({required this.stats, required this.onChanged});

  final SanmillOpeningStats stats;
  final ValueChanged<SanmillOpeningStats> onChanged;

  @override
  Widget build(BuildContext context) {
    final S l10n = S.of(context);
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: <Widget>[
        _NumberField(
          label: l10n.openingBookStudioWhiteWins,
          value: stats.whiteWins,
          onChanged: (int value) => onChanged(stats.copyWith(whiteWins: value)),
        ),
        _NumberField(
          label: l10n.openingBookStudioBlackWins,
          value: stats.blackWins,
          onChanged: (int value) => onChanged(stats.copyWith(blackWins: value)),
        ),
        _NumberField(
          label: l10n.openingBookStudioDraws,
          value: stats.draws,
          onChanged: (int value) => onChanged(stats.copyWith(draws: value)),
        ),
        _NumberField(
          label: l10n.openingBookStudioSampleSize,
          value: stats.sampleSize,
          onChanged: (int value) =>
              onChanged(stats.copyWith(sampleSize: value)),
        ),
      ],
    );
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 160,
      child: _TextField(
        keyValue: 'opening_book_studio_number_${label}_$value',
        label: label,
        value: value.toString(),
        keyboardType: TextInputType.number,
        onChanged: (String raw) {
          final int? parsed = int.tryParse(raw);
          if (parsed != null) {
            onChanged(parsed);
          }
        },
      ),
    );
  }
}

class _TextField extends StatelessWidget {
  const _TextField({
    required this.keyValue,
    required this.label,
    required this.value,
    required this.onChanged,
    this.publicKey,
    this.maxLines = 1,
    this.keyboardType,
  });

  final String keyValue;
  final Key? publicKey;
  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  final int maxLines;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      key: publicKey ?? ValueKey<String>(keyValue),
      initialValue: value,
      decoration: InputDecoration(
        border: const OutlineInputBorder(),
        labelText: label,
      ),
      keyboardType: keyboardType,
      maxLines: maxLines,
      onChanged: onChanged,
    );
  }
}

class _ChoiceField extends StatelessWidget {
  const _ChoiceField({
    required this.label,
    required this.value,
    required this.values,
    required this.onChanged,
  });

  final String label;
  final String value;
  final List<String> values;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        border: const OutlineInputBorder(),
        labelText: label,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isDense: true,
          isExpanded: true,
          value: values.contains(value) ? value : values.first,
          items: values
              .map(
                (String item) =>
                    DropdownMenuItem<String>(value: item, child: Text(item)),
              )
              .toList(growable: false),
          onChanged: (String? item) {
            assert(item != null, 'Dropdown value must be non-null.');
            onChanged(item!);
          },
        ),
      ),
    );
  }
}

class _ConfidenceSlider extends StatelessWidget {
  const _ConfidenceSlider({required this.value, required this.onChanged});

  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final S l10n = S.of(context);
    final double clamped = value.clamp(0, 1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          '${l10n.openingBookStudioConfidence}: '
          '${clamped.toStringAsFixed(2)}',
        ),
        Slider(value: clamped, onChanged: onChanged),
      ],
    );
  }
}

class _PanelHeader extends StatelessWidget {
  const _PanelHeader({required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(title, style: Theme.of(context).textTheme.titleLarge),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

List<String> _commaList(String value) {
  return value
      .split(',')
      .map((String token) => token.trim())
      .where((String token) => token.isNotEmpty)
      .toList(growable: false);
}

Map<String, List<String>> _updatedResponse(
  Map<String, List<String>> source,
  String side,
  List<String> moves,
) {
  final Map<String, List<String>> updated = <String, List<String>>{...source};
  if (moves.isEmpty) {
    updated.remove(side);
  } else {
    updated[side] = moves;
  }
  return updated;
}
