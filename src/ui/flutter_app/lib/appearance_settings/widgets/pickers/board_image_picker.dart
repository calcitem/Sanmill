// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// board_image_picker.dart

part of 'package:sanmill/appearance_settings/widgets/appearance_settings_page.dart';

// List of built-in (internal) board image asset paths
final List<String> _boardPaths = <String>[
  Assets.images.backgroundImage1.path,
  Assets.images.backgroundImage2.path,
  Assets.images.backgroundImage3.path,
  Assets.images.backgroundImage4.path,
  Assets.images.backgroundImage5.path,
  Assets.images.backgroundImage6.path,
  Assets.images.backgroundImage7.path,
  Assets.images.backgroundImage8.path,
  Assets.images.backgroundImage9.path,
  Assets.images.backgroundImage10.path,
];

/// A stateful widget that allows users to pick a board image.
/// Users can choose from built-in images or select a custom image from their device.
class _BoardImagePicker extends StatefulWidget {
  const _BoardImagePicker();

  @override
  _BoardImagePickerState createState() => _BoardImagePickerState();
}

class _BoardImagePickerState extends State<_BoardImagePicker> {
  /// This flag prevents concurrent image picking operations. It is set to `true`
  /// when an image pick starts and reset to `false` when the operation completes.
  bool _isPicking = false;

  @override
  Widget build(BuildContext context) {
    final String boardImageText = S.of(context).boardImage;

    return Semantics(
      label: boardImageText,
      child: ValueListenableBuilder<Box<DisplaySettings>>(
        valueListenable: DB().listenDisplaySettings,
        builder: (BuildContext context, Box<DisplaySettings> box, _) {
          final DisplaySettings displaySettings = box.get(
            DB.displaySettingsKey,
            defaultValue: const DisplaySettings(),
          )!;

          return GridView.builder(
            key: const Key('board_image_gridview'),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            // Total items: built-in images + 1 for the default solid color + 1 for custom image
            itemCount: _boardPaths.length + 2,
            itemBuilder: (BuildContext context, int index) {
              if (index < _boardPaths.length + 1) {
                // Index 0: Default solid color
                // Index 1 to _boardPaths.length: Built-in images
                final String asset = index == 0 ? '' : _boardPaths[index - 1];
                final bool isSelected = displaySettings.boardImagePath == asset;

                return _BoardImageItem(
                  key: Key('board_image_item_$index'),
                  asset: asset,
                  isSelect: isSelected,
                  onTap: () =>
                      _handleSelectImage(asset, displaySettings.boardImagePath),
                );
              } else {
                // Last item: Custom Image Picker
                return _CustomBoardImageItem(
                  key: const Key('custom_board_image_item'),
                  isSelected:
                      displaySettings.boardImagePath ==
                      displaySettings.customBoardImagePath,
                  customImagePath: displaySettings.customBoardImagePath,
                  onSelect: () => _handleSelectImage(
                    displaySettings.customBoardImagePath,
                    displaySettings.boardImagePath,
                  ),
                  onPickImage: () => _pickImage(
                    context,
                    boardImageText: boardImageText,
                    displaySettings: displaySettings,
                  ),
                );
              }
            },
          );
        },
      ),
    );
  }

  /// Handles the image picking and cropping process using the crop_your_image plugin.
  Future<void> _pickImage(
    BuildContext context, {
    required String boardImageText,
    required DisplaySettings displaySettings,
  }) async {
    // If an image pick is already in progress, exit immediately
    if (_isPicking) {
      // Optionally, show a message or toast here to indicate a pick is already in progress.
      return;
    }

    _isPicking = true;
    try {
      final NavigatorState navigator = Navigator.of(context);

      final ImagePicker picker = ImagePicker();
      final XFile? pickedFile = await picker.pickImage(
        source: ImageSource.gallery,
      );

      if (pickedFile != null) {
        final Uint8List imageData = await pickedFile.readAsBytes();

        if (!mounted) {
          return;
        }

        // Navigate to the cropping page
        final Uint8List? croppedData = await navigator.push<Uint8List?>(
          MaterialPageRoute<Uint8List?>(
            builder: (BuildContext context) => ImageCropPage(
              imageData: imageData,
              aspectRatio: 1, // Fixed aspect ratio for board images
              backgroundImageText: boardImageText,
              lineType: ReferenceLineType.boardLines,
            ),
          ),
        );

        if (croppedData != null) {
          // Determine the appropriate directory based on the platform
          //final Directory appDir = await getApplicationDocumentsDirectory();
          final Directory? appDir = (!kIsWeb && Platform.isAndroid)
              ? await getExternalStorageDirectory()
              : await getApplicationDocumentsDirectory();

          if (appDir != null) {
            final String imagesDirPath = '${appDir.path}/images';
            final Directory imagesDir = Directory(imagesDirPath);

            if (!imagesDir.existsSync()) {
              imagesDir.createSync(recursive: true);
            }

            // Generate a unique filename using the current timestamp
            final String timestamp = DateTime.now().millisecondsSinceEpoch
                .toString();
            final String filePath = '$imagesDirPath/$timestamp.png';

            // Save the cropped image to the designated directory
            final File imageFile = File(filePath);
            await imageFile.writeAsBytes(croppedData);

            // Capture the previous boardImagePath before updating
            final String previousPath = displaySettings.boardImagePath;

            // Update displaySettings with the new custom image path
            DB().displaySettings = displaySettings.copyWith(
              customBoardImagePath: filePath,
              boardImagePath: filePath,
            );

            // Handle the selection and prompt
            await _handleSelectImage(filePath, previousPath);
          }
        }
      }
    } on PlatformException catch (e) {
      // In case the error is 'already_active', handle it gracefully
      if (e.code == 'already_active') {
        // You could show a message to the user that the picker is busy
        logger.e('Another image picking operation is already in progress.');
      } else {
        rethrow;
      }
    } finally {
      _isPicking = false;
    }
  }

  /// Handles the image selection logic, including prompting the user to set toolbars as transparent
  Future<void> _handleSelectImage(String? asset, String previousPath) async {
    final bool isSettingNewImage = asset != null && asset.isNotEmpty;

    // Check if no image was previously set, and a new image is now being selected
    if (previousPath.isEmpty && isSettingNewImage) {
      final bool shouldMakeTransparent = await _promptMakeToolbarsTransparent(
        context,
        DB().displaySettings,
      );
      if (shouldMakeTransparent) {
        _makeToolbarsTransparent();
      }
    }

    // Update boardImagePath
    DB().displaySettings = DB().displaySettings.copyWith(
      boardImagePath: asset ?? '',
    );
  }

  /// Displays a dialog prompting the user to set toolbars as transparent
  Future<bool> _promptMakeToolbarsTransparent(
    BuildContext context,
    DisplaySettings displaySettings,
  ) async {
    final bool isNavigationToolbarOpaque =
        DB().colorSettings.navigationToolbarBackgroundColor.a != 0x00;
    final bool isMainToolbarOpaque =
        DB().colorSettings.mainToolbarBackgroundColor.a != 0x00;
    final bool isAnalysisToolbarOpaque =
        DB().colorSettings.analysisToolbarBackgroundColor.a != 0x00;

    if (isNavigationToolbarOpaque ||
        isMainToolbarOpaque ||
        isAnalysisToolbarOpaque) {
      final bool? result = await showDialog<bool>(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            key: const Key('make_toolbars_transparent_alert_dialog'),
            title: Text(S.of(context).color),
            content: Text(S.of(context).promptMakeToolbarTransparent),
            actions: <Widget>[
              TextButton(
                key: const Key('make_toolbars_no_button'),
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(
                  S.of(context).no,
                  style: TextStyle(
                    fontSize: AppTheme.textScaler.scale(
                      AppTheme.defaultFontSize,
                    ),
                  ),
                ),
              ),
              TextButton(
                key: const Key('make_toolbars_yes_button'),
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(
                  S.of(context).yes,
                  style: TextStyle(
                    fontSize: AppTheme.textScaler.scale(
                      AppTheme.defaultFontSize,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      );

      if (result ?? false) {
        // Make toolbars transparent
        _makeToolbarsTransparent();
        return true;
      }
    }

    return false;
  }

  /// Sets all toolbars to be transparent
  void _makeToolbarsTransparent() {
    final ColorSettings colorSettings = DB().colorSettings;
    DB().colorSettings = colorSettings.copyWith(
      mainToolbarBackgroundColor: colorSettings.mainToolbarBackgroundColor
          .withAlpha(0x00),
      navigationToolbarBackgroundColor: colorSettings
          .navigationToolbarBackgroundColor
          .withAlpha(0x00),
      analysisToolbarBackgroundColor: colorSettings
          .analysisToolbarBackgroundColor
          .withAlpha(0x00),
    );
  }
}

/// A widget representing a single built-in board image or the default solid color.
class _BoardImageItem extends StatelessWidget {
  const _BoardImageItem({
    required this.asset,
    this.isSelect = false,
    required this.onTap,
    super.key,
  });

  final String asset;
  final bool isSelect;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: Key('board_image_gesture_$asset'),
      onTap: onTap, // Calls the callback passed by the parent widget
      child: Stack(
        children: <Widget>[
          Container(
            key: Key('board_image_container_$asset'),
            decoration: BoxDecoration(
              color: asset.isEmpty
                  ? DB().colorSettings.boardBackgroundColor
                  : null, // If asset is empty, use solid color background
              image: asset.isEmpty
                  ? null
                  : DecorationImage(
                      image: getBoardImageProvider(
                        DisplaySettings(boardImagePath: asset),
                      )!,
                      fit: BoxFit.cover,
                    ),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          Positioned(
            key: Key('board_image_icon_positioned_$asset'),
            right: 8,
            top: 8,
            child: Icon(
              isSelect ? Icons.check_circle : Icons.check_circle_outline,
              color: Colors.white,
              key: Key('board_image_icon_$asset'),
            ),
          ),
        ],
      ),
    );
  }
}

/// A widget representing the custom board image picker.
/// - When no custom image is selected, it shows a large add icon in the center.
/// - If a custom image is selected, it displays the image with an edit icon at the center and a check icon at the top-right if selected.
class _CustomBoardImageItem extends StatelessWidget {
  const _CustomBoardImageItem({
    required this.isSelected,
    required this.customImagePath,
    required this.onSelect,
    required this.onPickImage,
    super.key,
  });

  final bool isSelected;
  final String? customImagePath;
  final VoidCallback onSelect;
  final VoidCallback onPickImage;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: const Key('custom_board_image_gesture'),
      // Tap to select the image if customImagePath is available, otherwise prompt to pick an image
      onTap: () {
        if (customImagePath != null) {
          onSelect();
        } else {
          onPickImage();
        }
      },
      child: Stack(
        children: <Widget>[
          // Background container displaying either an image or a placeholder color
          Container(
            key: const Key('custom_board_image_container'),
            decoration: BoxDecoration(
              color: customImagePath == null
                  ? Colors
                        .grey // Displays grey if no custom image is selected
                  : null,
              image: customImagePath != null
                  ? DecorationImage(
                      image: FileImage(File(customImagePath!)),
                      fit: BoxFit.cover,
                    )
                  : null,
              borderRadius: BorderRadius.circular(8),
            ),
            // Shows an add icon when no custom image is selected
            child: customImagePath == null
                ? const Center(
                    child: Icon(
                      Icons.add,
                      size: 32,
                      color: Colors.white,
                      key: Key('custom_board_image_add_icon'),
                    ),
                  )
                : null,
          ),
          // Shows an edit icon if a custom image is selected
          if (customImagePath != null)
            Center(
              child: IconButton(
                key: const Key('custom_board_image_edit_button'),
                icon: const Icon(Icons.edit, color: Colors.white, size: 32),
                onPressed: onPickImage,
                tooltip: S.of(context).chooseYourPicture,
              ),
            ),
          // Displays a checkmark icon in the top-right corner if selected
          Positioned(
            key: const Key('custom_board_image_check_positioned'),
            right: 8,
            top: 8,
            child: Icon(
              isSelected ? Icons.check_circle : Icons.check_circle_outline,
              color: Colors.white,
              key: const Key('custom_board_image_check_icon'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Returns an ImageProvider based on the current boardImagePath.
/// - If the path is empty, returns null to indicate a solid color should be used.
/// - If the path points to an existing file, returns a FileImage.
/// - Otherwise, treats the path as an asset and returns an AssetImage.
ImageProvider? getBoardImageProvider(DisplaySettings displaySettings) {
  final String path = displaySettings.boardImagePath;
  if (path.isEmpty) {
    // Default to solid color if no image is selected
    return null;
  } else if (File(path).existsSync()) {
    // If the path points to a file, use FileImage
    return FileImage(File(path));
  } else {
    // Otherwise, assume it's an asset path and use AssetImage
    return AssetImage(path);
  }
}
