// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// piece_image_picker.dart

part of 'package:sanmill/appearance_settings/widgets/appearance_settings_page.dart';

final List<String> _pieceBgPaths = <String>[
  '', // Pure color
  Assets.images.whitePieceImage1.path,
  Assets.images.blackPieceImage1.path,
  Assets.images.whitePieceImage2.path,
  Assets.images.blackPieceImage2.path,
  Assets.images.whitePieceImage3.path,
  Assets.images.blackPieceImage3.path,
  Assets.images.whitePieceImage4.path,
  Assets.images.blackPieceImage4.path,
  Assets.images.whitePieceImage5.path,
  Assets.images.blackPieceImage5.path,
  Assets.images.whitePieceImage6.path,
  Assets.images.blackPieceImage6.path,
  Assets.images.whitePieceImage7.path,
  Assets.images.blackPieceImage7.path,
  Assets.images.whitePieceImage8.path,
  Assets.images.blackPieceImage8.path,
];

final List<_PieceImageSet> _pieceImageSets = <_PieceImageSet>[
  const _PieceImageSet(index: 0, whiteImagePath: '', blackImagePath: ''),
  _PieceImageSet(
    index: 1,
    whiteImagePath: Assets.images.whitePieceImage1.path,
    blackImagePath: Assets.images.blackPieceImage1.path,
  ),
  _PieceImageSet(
    index: 2,
    whiteImagePath: Assets.images.whitePieceImage2.path,
    blackImagePath: Assets.images.blackPieceImage2.path,
  ),
  _PieceImageSet(
    index: 3,
    whiteImagePath: Assets.images.whitePieceImage3.path,
    blackImagePath: Assets.images.blackPieceImage3.path,
  ),
  _PieceImageSet(
    index: 4,
    whiteImagePath: Assets.images.whitePieceImage4.path,
    blackImagePath: Assets.images.blackPieceImage4.path,
  ),
  _PieceImageSet(
    index: 5,
    whiteImagePath: Assets.images.whitePieceImage5.path,
    blackImagePath: Assets.images.blackPieceImage5.path,
  ),
  _PieceImageSet(
    index: 6,
    whiteImagePath: Assets.images.whitePieceImage6.path,
    blackImagePath: Assets.images.blackPieceImage6.path,
  ),
  _PieceImageSet(
    index: 7,
    whiteImagePath: Assets.images.whitePieceImage7.path,
    blackImagePath: Assets.images.blackPieceImage7.path,
  ),
  _PieceImageSet(
    index: 8,
    whiteImagePath: Assets.images.whitePieceImage8.path,
    blackImagePath: Assets.images.blackPieceImage8.path,
  ),
];

class _PieceImageSet {
  const _PieceImageSet({
    required this.index,
    required this.whiteImagePath,
    required this.blackImagePath,
  });

  final int index;
  final String whiteImagePath;
  final String blackImagePath;
}

/// Lichess-style full-screen selector for both Mill piece images.
class _PieceImageSelectionPage extends StatefulWidget {
  const _PieceImageSelectionPage();

  @override
  State<_PieceImageSelectionPage> createState() =>
      _PieceImageSelectionPageState();
}

class _PieceImageSelectionPageState extends State<_PieceImageSelectionPage> {
  /// This flag prevents concurrent image picking operations. It is set to `true`
  /// when an image pick starts and reset to `false` when the operation completes.
  bool _isPicking = false;

  @override
  Widget build(BuildContext context) {
    final S strings = S.of(context);
    return Scaffold(
      key: const Key('piece_image_selection_page'),
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: Text(strings.pieceSet),
        actions: <Widget>[
          if (_isPicking)
            const Padding(
              padding: EdgeInsetsDirectional.only(end: 16),
              child: Center(
                child: SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: ValueListenableBuilder<Box<DisplaySettings>>(
          key: const Key('piece_image_selection_value_listenable_builder'),
          valueListenable: DB().listenDisplaySettings,
          builder: (BuildContext context, Box<DisplaySettings> box, _) {
            final DisplaySettings displaySettings = box.get(
              DB.displaySettingsKey,
              defaultValue: const DisplaySettings(),
            )!;
            return ListView(
              key: const Key('piece_image_selection_list'),
              padding: const EdgeInsets.only(top: 16, bottom: 24),
              children: <Widget>[
                _buildPieceSetSection(
                  context: context,
                  displaySettings: displaySettings,
                ),
                _buildPlayerSection(
                  context: context,
                  title: strings.player1,
                  isPlayerOne: true,
                  selectedImagePath: displaySettings.whitePieceImagePath,
                  customImagePath: displaySettings.customWhitePieceImagePath,
                  otherPlayerSelectedImagePath:
                      displaySettings.blackPieceImagePath,
                  displaySettings: displaySettings,
                ),
                _buildPlayerSection(
                  context: context,
                  title: strings.player2,
                  isPlayerOne: false,
                  selectedImagePath: displaySettings.blackPieceImagePath,
                  customImagePath: displaySettings.customBlackPieceImagePath,
                  otherPlayerSelectedImagePath:
                      displaySettings.whitePieceImagePath,
                  displaySettings: displaySettings,
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildPieceSetSection({
    required BuildContext context,
    required DisplaySettings displaySettings,
  }) {
    return SettingsCard(
      key: const Key('piece_image_selection_piece_sets_card'),
      title: Text(S.of(context).pieceSet),
      children: <Widget>[
        for (final _PieceImageSet set in _pieceImageSets)
          _PieceImageSetChoiceTile(
            key: Key('piece_image_selection_piece_set_${set.index}'),
            title: _pieceSetChoiceTitle(context, set),
            whiteImagePath: set.whiteImagePath,
            blackImagePath: set.blackImagePath,
            isSelected:
                displaySettings.whitePieceImagePath == set.whiteImagePath &&
                displaySettings.blackPieceImagePath == set.blackImagePath,
            onTap: () =>
                _selectPieceSet(displaySettings: displaySettings, set: set),
          ),
      ],
    );
  }

  Widget _buildPlayerSection({
    required BuildContext context,
    required String title,
    required bool isPlayerOne,
    required String selectedImagePath,
    required String? customImagePath,
    required String otherPlayerSelectedImagePath,
    required DisplaySettings displaySettings,
  }) {
    return SettingsCard(
      key: isPlayerOne
          ? const Key('piece_image_selection_player1_card')
          : const Key('piece_image_selection_player2_card'),
      title: Text(title),
      children: <Widget>[
        for (int index = 0; index < _pieceBgPaths.length; index++)
          _PieceImageChoiceTile(
            key: Key(
              'piece_image_selection_${isPlayerOne ? 'player1' : 'player2'}_$index',
            ),
            title: _pieceChoiceTitle(context, index),
            preview: _PieceImagePreview(
              asset: _pieceBgPaths[index],
              isPlayerOne: isPlayerOne,
            ),
            isSelected: selectedImagePath == _pieceBgPaths[index],
            isEnabled:
                index == 0 ||
                _pieceBgPaths[index] != otherPlayerSelectedImagePath,
            onTap: () => _selectPieceImage(
              displaySettings: displaySettings,
              isPlayerOne: isPlayerOne,
              imagePath: _pieceBgPaths[index],
            ),
          ),
        _PieceImageChoiceTile(
          key: Key(
            'piece_image_selection_${isPlayerOne ? 'player1' : 'player2'}_custom',
          ),
          title: S.of(context).custom,
          subtitle: customImagePath == null
              ? S.of(context).chooseYourPicture
              : S.of(context).pieceImage,
          preview: _CustomPiecePreview(customImagePath: customImagePath),
          isSelected:
              customImagePath != null && selectedImagePath == customImagePath,
          onTap: () {
            if (customImagePath == null) {
              _pickImage(
                context,
                isPlayerOne: isPlayerOne,
                displaySettings: displaySettings,
              );
              return;
            }
            _selectPieceImage(
              displaySettings: displaySettings,
              isPlayerOne: isPlayerOne,
              imagePath: customImagePath,
            );
          },
          trailingAction: customImagePath == null
              ? null
              : IconButton(
                  icon: const Icon(Icons.edit_rounded),
                  tooltip: S.of(context).chooseYourPicture,
                  onPressed: () => _pickImage(
                    context,
                    isPlayerOne: isPlayerOne,
                    displaySettings: displaySettings,
                  ),
                ),
        ),
      ],
    );
  }

  String _pieceChoiceTitle(BuildContext context, int index) {
    assert(index >= 0, 'Piece image index must not be negative.');
    if (index == 0) {
      return S.of(context).solidColor;
    }
    return '${S.of(context).pieceImage} $index';
  }

  String _pieceSetChoiceTitle(BuildContext context, _PieceImageSet set) {
    assert(set.index >= 0, 'Piece set index must not be negative.');
    if (set.index == 0) {
      return S.of(context).solidColor;
    }
    return '${S.of(context).pieceSet} ${set.index}';
  }

  void _selectPieceSet({
    required DisplaySettings displaySettings,
    required _PieceImageSet set,
  }) {
    DB().displaySettings = displaySettings.copyWith(
      whitePieceImagePath: set.whiteImagePath,
      blackPieceImagePath: set.blackImagePath,
    );
  }

  void _selectPieceImage({
    required DisplaySettings displaySettings,
    required bool isPlayerOne,
    required String imagePath,
  }) {
    DB().displaySettings = isPlayerOne
        ? displaySettings.copyWith(whitePieceImagePath: imagePath)
        : displaySettings.copyWith(blackPieceImagePath: imagePath);
  }

  Future<void> _pickImage(
    BuildContext context, {
    required bool isPlayerOne,
    required DisplaySettings displaySettings,
  }) async {
    if (_isPicking) {
      return;
    }

    setState(() => _isPicking = true);
    try {
      final NavigatorState navigator = Navigator.of(context);
      final ImagePicker picker = ImagePicker();
      final XFile? pickedFile = await picker.pickImage(
        source: ImageSource.gallery,
      );

      if (pickedFile == null) {
        return;
      }

      final Uint8List imageData = await pickedFile.readAsBytes();
      if (!mounted) {
        return;
      }

      final Uint8List? croppedData = await navigator.push<Uint8List?>(
        MaterialPageRoute<Uint8List?>(
          builder: (BuildContext context) => ImageCropPage(
            key: const Key('custom_piece_image_crop_page'),
            imageData: imageData,
            aspectRatio: 1.0,
            backgroundImageText: S.of(context).pieceImage,
            lineType: ReferenceLineType.circle,
          ),
        ),
      );

      if (croppedData == null) {
        return;
      }

      final Directory? appDir = (!kIsWeb && Platform.isAndroid)
          ? await getExternalStorageDirectory()
          : await getApplicationDocumentsDirectory();
      assert(
        appDir != null,
        'Application document directory must be available.',
      );
      if (appDir == null) {
        throw StateError('Application document directory must be available.');
      }

      final Directory imagesDir = Directory('${appDir.path}/images');
      if (!imagesDir.existsSync()) {
        imagesDir.createSync(recursive: true);
      }

      final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final String filePath = '${imagesDir.path}/$timestamp.png';
      await File(filePath).writeAsBytes(croppedData);

      DB().displaySettings = isPlayerOne
          ? displaySettings.copyWith(
              customWhitePieceImagePath: filePath,
              whitePieceImagePath: filePath,
            )
          : displaySettings.copyWith(
              customBlackPieceImagePath: filePath,
              blackPieceImagePath: filePath,
            );
    } on PlatformException catch (e) {
      if (e.code == 'already_active') {
        logger.e('Another image picking operation is already in progress.');
      } else {
        rethrow;
      }
    } finally {
      if (mounted) {
        setState(() => _isPicking = false);
      } else {
        _isPicking = false;
      }
    }
  }
}

class _PieceImageSetChoiceTile extends StatelessWidget {
  const _PieceImageSetChoiceTile({
    super.key,
    required this.title,
    required this.whiteImagePath,
    required this.blackImagePath,
    required this.isSelected,
    required this.onTap,
  });

  final String title;
  final String whiteImagePath;
  final String blackImagePath;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return ListTile(
      selected: isSelected,
      title: Text(title),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: _PieceImageSetPreview(
          whiteImagePath: whiteImagePath,
          blackImagePath: blackImagePath,
        ),
      ),
      trailing: isSelected
          ? Icon(Icons.check, color: colorScheme.primary)
          : null,
      onTap: onTap,
    );
  }
}

class _PieceImageSetPreview extends StatelessWidget {
  const _PieceImageSetPreview({
    required this.whiteImagePath,
    required this.blackImagePath,
  });

  final String whiteImagePath;
  final String blackImagePath;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 264),
      child: SizedBox(
        height: 56,
        child: Stack(
          children: <Widget>[
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: colorScheme.outlineVariant),
                  ),
                  child: Row(
                    children: <Widget>[
                      for (int index = 0; index < 6; index++)
                        Expanded(
                          child: ColoredBox(
                            color: index.isEven
                                ? colorScheme.surfaceContainerHigh
                                : colorScheme.surfaceContainerLow,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: Align(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    _PieceImageSetPiecePreview(
                      imagePath: whiteImagePath,
                      isPlayerOne: true,
                    ),
                    const SizedBox(width: 18),
                    _PieceImageSetPiecePreview(
                      imagePath: blackImagePath,
                      isPlayerOne: false,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PieceImageSetPiecePreview extends StatelessWidget {
  const _PieceImageSetPiecePreview({
    required this.imagePath,
    required this.isPlayerOne,
  });

  final String imagePath;
  final bool isPlayerOne;

  @override
  Widget build(BuildContext context) {
    if (imagePath.isNotEmpty) {
      return SizedBox.square(
        dimension: 42,
        child: Image.asset(imagePath, fit: BoxFit.contain),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: isPlayerOne
            ? DB().colorSettings.whitePieceColor
            : DB().colorSettings.blackPieceColor,
        shape: BoxShape.circle,
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      child: const SizedBox.square(dimension: 40),
    );
  }
}

class _PieceImageChoiceTile extends StatelessWidget {
  const _PieceImageChoiceTile({
    super.key,
    required this.title,
    required this.preview,
    required this.isSelected,
    required this.onTap,
    this.subtitle,
    this.isEnabled = true,
    this.trailingAction,
  });

  final String title;
  final String? subtitle;
  final Widget preview;
  final bool isSelected;
  final bool isEnabled;
  final VoidCallback onTap;
  final Widget? trailingAction;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final Widget? trailing = trailingAction == null
        ? (isSelected ? Icon(Icons.check, color: colorScheme.primary) : null)
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              trailingAction!,
              if (isSelected) Icon(Icons.check, color: colorScheme.primary),
            ],
          );

    return ListTile(
      enabled: isEnabled,
      selected: isSelected,
      leading: preview,
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: trailing,
      onTap: isEnabled ? onTap : null,
    );
  }
}

class _PieceImagePreview extends StatelessWidget {
  const _PieceImagePreview({required this.asset, required this.isPlayerOne});

  final String asset;
  final bool isPlayerOne;

  @override
  Widget build(BuildContext context) {
    if (asset.isEmpty) {
      return _PureColorPiecePreview(isPlayerOne: isPlayerOne);
    }
    return SizedBox.square(
      dimension: 48,
      child: Image.asset(asset, fit: BoxFit.contain),
    );
  }
}

class _PureColorPiecePreview extends StatelessWidget {
  const _PureColorPiecePreview({required this.isPlayerOne});

  final bool isPlayerOne;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: isPlayerOne
            ? DB().colorSettings.whitePieceColor
            : DB().colorSettings.blackPieceColor,
        shape: BoxShape.circle,
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: const SizedBox.square(
        key: Key('piece_image_selection_solid_color_preview'),
        dimension: 48,
      ),
    );
  }
}

class _CustomPiecePreview extends StatelessWidget {
  const _CustomPiecePreview({required this.customImagePath});

  final String? customImagePath;

  @override
  Widget build(BuildContext context) {
    final String? imagePath = customImagePath;
    if (imagePath != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox.square(
          dimension: 48,
          child: Image.file(File(imagePath), fit: BoxFit.contain),
        ),
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: SizedBox.square(
        dimension: 48,
        child: Icon(
          Icons.add_photo_alternate_outlined,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
