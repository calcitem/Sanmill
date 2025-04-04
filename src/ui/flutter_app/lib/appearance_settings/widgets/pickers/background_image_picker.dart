// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// background_image_picker.dart

part of 'package:sanmill/appearance_settings/widgets/appearance_settings_page.dart';

// List of built-in (internal) background image asset paths
final List<String> _bgPaths = <String>[
  Assets.images.backgroundImage1.path,
  Assets.images.backgroundImage2.path,
  Assets.images.backgroundImage3.path,
  Assets.images.backgroundImage4.path,
  Assets.images.backgroundImage5.path,
  Assets.images.backgroundImage6.path,
  Assets.images.backgroundImage7.path,
  Assets.images.backgroundImage8.path,
];

/// A stateful widget that allows users to pick a background image.
/// Users can choose from built-in images or select a custom image from their device.
class _BackgroundImagePicker extends StatefulWidget {
  const _BackgroundImagePicker();

  @override
  _BackgroundImagePickerState createState() => _BackgroundImagePickerState();
}

class _BackgroundImagePickerState extends State<_BackgroundImagePicker> {
  /// This flag prevents concurrent image picking operations. It is set to `true`
  /// when an image pick starts and reset to `false` when the operation completes.
  bool _isPicking = false;

  @override
  Widget build(BuildContext context) {
    final String backgroundImageText = S.of(context).backgroundImage;

    // Get device aspect ratio
    final double aspectRatio =
        MediaQuery.of(context).size.width / MediaQuery.of(context).size.height;

    return Semantics(
      label: backgroundImageText,
      child: ValueListenableBuilder<Box<DisplaySettings>>(
        valueListenable: DB().listenDisplaySettings,
        builder: (BuildContext context, Box<DisplaySettings> box, _) {
          final DisplaySettings displaySettings = box.get(
            DB.displaySettingsKey,
            defaultValue: const DisplaySettings(),
          )!;

          return GridView.builder(
            key: const Key('background_image_gridview'),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              childAspectRatio: aspectRatio,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            // Total items: built-in images + 1 for the default solid color + 1 for custom image
            itemCount: _bgPaths.length + 2,
            itemBuilder: (BuildContext context, int index) {
              if (index < _bgPaths.length + 1) {
                // Index 0: Default solid color
                // Index 1 to _bgPaths.length: Built-in images
                final String asset = index == 0 ? '' : _bgPaths[index - 1];
                return _BackgroundImageItem(
                  key: Key('background_image_item_$index'),
                  asset: asset,
                  isSelect: displaySettings.backgroundImagePath == asset,
                  onChanged: () {
                    // Update only the backgroundImagePath to the selected built-in image or default,
                    // keeping customBackgroundImagePath unchanged
                    DB().displaySettings = displaySettings.copyWith(
                      backgroundImagePath: asset,
                    );
                  },
                );
              } else {
                // Last item: Custom Image Picker
                return _CustomBackgroundImageItem(
                  key: const Key('custom_background_image_item'),
                  isSelected: displaySettings.backgroundImagePath ==
                      displaySettings.customBackgroundImagePath,
                  customImagePath: displaySettings.customBackgroundImagePath,
                  onSelect: () {
                    // Set backgroundImagePath to the custom image path
                    DB().displaySettings = displaySettings.copyWith(
                      backgroundImagePath:
                          displaySettings.customBackgroundImagePath ??
                              '', // TODO: '' is right?
                    );
                  },
                  onPickImage: () => _pickImage(
                    context,
                    aspectRatio: aspectRatio,
                    backgroundImageText: backgroundImageText,
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

  /// Handles the image picking and cropping process.
  Future<void> _pickImage(
    BuildContext context, {
    required double aspectRatio,
    required String backgroundImageText,
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
              aspectRatio: aspectRatio,
              backgroundImageText: backgroundImageText,
              lineType: ReferenceLineType.none,
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
            final String timestamp =
                DateTime.now().millisecondsSinceEpoch.toString();
            final String filePath = '$imagesDirPath/$timestamp.png';

            // Save the cropped image to the designated directory
            final File imageFile = File(filePath);
            await imageFile.writeAsBytes(croppedData);

            // Update displaySettings with the new custom image path
            DB().displaySettings = displaySettings.copyWith(
              customBackgroundImagePath: filePath,
              backgroundImagePath: filePath,
            );
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
}

/// A widget representing a single built-in background image or the default solid color.
class _BackgroundImageItem extends StatelessWidget {
  const _BackgroundImageItem({
    required this.asset,
    this.isSelect = false,
    this.onChanged,
    super.key,
  });

  final String asset;
  final bool isSelect;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: Key('background_image_gesture_$asset'),
      onTap: () {
        if (!isSelect) {
          onChanged?.call();
        }
      },
      child: Stack(
        children: <Widget>[
          Container(
            key: Key('background_image_container_$asset'),
            decoration: BoxDecoration(
              color: asset.isEmpty
                  ? DB().colorSettings.darkBackgroundColor
                  : null, // Use solid color if asset is empty
              image: asset.isEmpty
                  ? null
                  : DecorationImage(
                      image: getBackgroundImageProvider(DisplaySettings(
                        backgroundImagePath: asset,
                      ))!,
                      fit: BoxFit.cover,
                    ),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          Positioned(
            key: Key('background_image_icon_positioned_$asset'),
            right: 8,
            top: 8,
            child: Icon(
              isSelect ? Icons.check_circle : Icons.check_circle_outline,
              color: Colors.white,
              key: Key('background_image_icon_$asset'),
            ),
          ),
        ],
      ),
    );
  }
}

/// A widget representing the custom background image picker.
/// - When no custom image is selected, it shows a large add icon in the center.
/// - If a custom image is selected, it displays the image with an edit icon at the center and a check icon at the top-right if selected.
class _CustomBackgroundImageItem extends StatelessWidget {
  const _CustomBackgroundImageItem({
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
      key: const Key('custom_background_gesture'),
      // Tap to select the image if customImagePath is available, otherwise prompt to pick an image
      onTap: customImagePath != null ? onSelect : onPickImage,
      child: Stack(
        children: <Widget>[
          // Background container with image or placeholder color
          Container(
            key: const Key('custom_background_container'),
            decoration: BoxDecoration(
              color: customImagePath == null
                  ? Colors.grey // Grey color if no custom image is selected
                  : null,
              image: customImagePath != null
                  ? DecorationImage(
                      image: FileImage(File(customImagePath!)),
                      fit: BoxFit.cover,
                    )
                  : null,
              borderRadius: BorderRadius.circular(8),
            ),
            // Centered add icon when no custom image is selected
            child: customImagePath == null
                ? const Center(
                    child: Icon(
                      Icons.add,
                      size: 32,
                      color: Colors.white,
                      key: Key('custom_background_add_icon'),
                    ),
                  )
                : null,
          ),
          // Centered edit icon when custom image is present
          if (customImagePath != null)
            Center(
              child: IconButton(
                key: const Key('custom_background_edit_button'),
                icon: const Icon(
                  Icons.edit,
                  color: Colors.white,
                  size: 32,
                ),
                onPressed: onPickImage,
                tooltip: S.of(context).chooseYourPicture,
              ),
            ),
          // Checkmark icon at the top-right corner when selected
          Positioned(
            key: const Key('custom_background_check_positioned'),
            right: 8,
            top: 8,
            child: Icon(
              isSelected ? Icons.check_circle : Icons.check_circle_outline,
              color: Colors.white,
              key: const Key('custom_background_check_icon'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Returns an ImageProvider based on the current backgroundImagePath.
/// - If the path is empty, returns null to indicate a solid color should be used.
/// - If the path points to an existing file, returns a FileImage.
/// - Otherwise, treats the path as an asset and returns an AssetImage.
ImageProvider? getBackgroundImageProvider(DisplaySettings displaySettings) {
  final String path = displaySettings.backgroundImagePath;
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
