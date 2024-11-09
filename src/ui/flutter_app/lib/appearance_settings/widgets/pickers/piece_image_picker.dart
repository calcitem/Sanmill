// This file is part of Sanmill.
// Copyright (C) 2019-2024 The Sanmill developers (see AUTHORS file)
//
// Sanmill is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Sanmill is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

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
];

/// A stateful widget that allows users to pick piece images for both players,
/// including the option to select custom images from the device with cropping.
class _PieceImagePicker extends StatefulWidget {
  const _PieceImagePicker();

  @override
  _PieceImagePickerState createState() => _PieceImagePickerState();
}

class _PieceImagePickerState extends State<_PieceImagePicker> {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: DB().colorSettings.boardBackgroundColor,
      child: Semantics(
        label: S.of(context).pieceImage,
        child: ValueListenableBuilder<Box<DisplaySettings>>(
          valueListenable: DB().listenDisplaySettings,
          builder: (BuildContext context, Box<DisplaySettings> box, _) {
            final DisplaySettings displaySettings = box.get(
              DB.displaySettingsKey,
              defaultValue: const DisplaySettings(),
            )!;

            return Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    // Row for Player 1
                    _buildPlayerRow(
                      context,
                      S.of(context).player1,
                      displaySettings.whitePieceImagePath,
                      displaySettings.customWhitePieceImagePath,
                      (String asset) {
                        DB().displaySettings = displaySettings.copyWith(
                          whitePieceImagePath: asset,
                        );
                      },
                      displaySettings.blackPieceImagePath,
                      isPlayerOne: true,
                      displaySettings: displaySettings,
                    ),
                    const SizedBox(height: 20),
                    // Row for Player 2
                    _buildPlayerRow(
                      context,
                      S.of(context).player2,
                      displaySettings.blackPieceImagePath,
                      displaySettings.customBlackPieceImagePath,
                      (String asset) {
                        DB().displaySettings = displaySettings.copyWith(
                          blackPieceImagePath: asset,
                        );
                      },
                      displaySettings.whitePieceImagePath,
                      isPlayerOne: false,
                      displaySettings: displaySettings,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildPlayerRow(
    BuildContext context,
    String playerLabel,
    String selectedImagePath,
    String? customImagePath,
    void Function(String) onImageSelected,
    String otherPlayerSelectedImagePath, {
    required bool isPlayerOne,
    required DisplaySettings displaySettings,
  }) {
    final ScrollController scrollController = ScrollController();

    // Get aspect ratio for cropping (assuming square for pieces)
    const double aspectRatio = 1.0;

    return GestureDetector(
      onHorizontalDragUpdate: (DragUpdateDetails details) {
        scrollController.jumpTo(
          scrollController.offset - details.delta.dx,
        );
      },
      child: Listener(
        onPointerSignal: (PointerSignalEvent event) {
          if (event is PointerScrollEvent) {
            final double delta = event.scrollDelta.dy;
            scrollController.jumpTo(scrollController.offset + delta);
          }
        },
        child: Row(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 12),
              child: Text(
                playerLabel,
                style: TextStyle(color: DB().colorSettings.boardLineColor),
              ),
            ),
            Expanded(
              child: SizedBox(
                height: 60,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount:
                      _pieceBgPaths.length + 1, // Include custom image item
                  controller: scrollController,
                  itemBuilder: (BuildContext context, int index) {
                    if (index < _pieceBgPaths.length) {
                      final String asset = _pieceBgPaths[index];
                      final bool isSelectable =
                          index == 0 || asset != otherPlayerSelectedImagePath;
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: GestureDetector(
                          onTap: isSelectable
                              ? () => onImageSelected(asset)
                              : null,
                          child: asset.isEmpty
                              ? _buildPureColorPiece(
                                  isSelected: selectedImagePath == asset,
                                  isPlayerOne: isPlayerOne,
                                )
                              : _PieceImageItem(
                                  asset: asset,
                                  isSelect: selectedImagePath == asset,
                                  isSelectable: isSelectable,
                                ),
                        ),
                      );
                    } else {
                      // Custom Image Item
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: _CustomPieceImageItem(
                          isSelected: selectedImagePath == customImagePath,
                          customImagePath: customImagePath,
                          onSelect: () {
                            // Set selectedImagePath to customImagePath
                            onImageSelected(customImagePath ?? '');
                          },
                          onPickImage: () => _pickImage(
                            context,
                            isPlayerOne: isPlayerOne,
                            displaySettings: displaySettings,
                            aspectRatio: aspectRatio,
                          ),
                        ),
                      );
                    }
                  },
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Container(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPureColorPiece({
    required bool isSelected,
    required bool isPlayerOne,
  }) {
    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        color: isPlayerOne
            ? DB().colorSettings.whitePieceColor
            : DB().colorSettings.blackPieceColor,
        shape: BoxShape.circle,
        border: isSelected ? Border.all(color: Colors.green, width: 2) : null,
      ),
      child: isSelected
          ? const Align(
              child: Icon(
                Icons.check_circle,
                color: Colors.green,
              ),
            )
          : null,
    );
  }

  /// Handles the image picking and cropping process for custom piece images.
  Future<void> _pickImage(
    BuildContext context, {
    required bool isPlayerOne,
    required DisplaySettings displaySettings,
    required double aspectRatio,
  }) async {
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
            backgroundImageText: S.of(context).pieceImage,
            lineType: ReferenceLineType.circle,
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
          if (isPlayerOne) {
            DB().displaySettings = displaySettings.copyWith(
              customWhitePieceImagePath: filePath,
              whitePieceImagePath: filePath,
            );
          } else {
            DB().displaySettings = displaySettings.copyWith(
              customBlackPieceImagePath: filePath,
              blackPieceImagePath: filePath,
            );
          }
        }
      }
    }
  }
}

/// A widget representing a single built-in piece image.
class _PieceImageItem extends StatelessWidget {
  const _PieceImageItem({
    required this.asset,
    this.isSelect = false,
    this.isSelectable = true,
  });

  final String asset;
  final bool isSelect;
  final bool isSelectable;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: isSelectable ? 1.0 : 0.5,
      child: Stack(
        children: <Widget>[
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              image: DecorationImage(
                image: AssetImage(asset),
                fit: BoxFit.contain,
              ),
              border:
                  isSelect ? Border.all(color: Colors.green, width: 2) : null,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          if (isSelect)
            const Align(
              child: Icon(
                Icons.check_circle,
                color: Colors.green,
              ),
            ),
        ],
      ),
    );
  }
}

/// A widget representing the custom piece image picker.
/// - When no custom image is selected, it shows a large add icon in the center.
/// - If a custom image is selected, it displays the image with an edit icon at the center and a check icon if selected.
class _CustomPieceImageItem extends StatelessWidget {
  const _CustomPieceImageItem({
    required this.isSelected,
    required this.customImagePath,
    required this.onSelect,
    required this.onPickImage,
  });

  final bool isSelected;
  final String? customImagePath;
  final VoidCallback onSelect;
  final VoidCallback onPickImage;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // Tap to select the image if customImagePath is available, otherwise prompt to pick an image
      onTap: customImagePath != null ? onSelect : onPickImage,
      child: Stack(
        children: <Widget>[
          // Background container with image or placeholder color
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: customImagePath == null
                  ? Colors.grey // Grey color if no custom image is selected
                  : null,
              image: customImagePath != null
                  ? DecorationImage(
                      image: FileImage(File(customImagePath!)),
                      fit: BoxFit.contain,
                    )
                  : null,
              border:
                  isSelected ? Border.all(color: Colors.green, width: 2) : null,
              borderRadius: BorderRadius.circular(8),
            ),
            // Centered add icon when no custom image is selected
            child: customImagePath == null
                ? const Center(
                    child: Icon(
                      Icons.add,
                      size: 32,
                      color: Colors.white,
                    ),
                  )
                : null,
          ),
          // Centered edit icon when custom image is present
          if (customImagePath != null)
            Center(
              child: IconButton(
                icon: const Icon(
                  Icons.edit,
                  color: Colors.white,
                  size: 32,
                ),
                onPressed: onPickImage,
                tooltip: S.of(context).chooseYourPicture,
              ),
            ),
          // Checkmark icon when selected
          if (isSelected)
            const Align(
              child: Icon(
                Icons.check_circle,
                color: Colors.green,
              ),
            ),
        ],
      ),
    );
  }
}
