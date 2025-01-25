/*
  This file is part of Sanmill.
  Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

  Sanmill is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  Sanmill is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

part of 'package:sanmill/appearance_settings/widgets/appearance_settings_page.dart';

/// Image cropping page using crop_your_image plugin.
class ImageCropPage extends StatefulWidget {
  const ImageCropPage({
    required this.imageData,
    required this.aspectRatio,
    required this.backgroundImageText,
    required this.lineType,
    super.key,
  });
  final Uint8List imageData;
  final double aspectRatio;
  final String backgroundImageText;
  final ReferenceLineType lineType;

  @override
  ImageCropPageState createState() => ImageCropPageState();
}

class ImageCropPageState extends State<ImageCropPage> {
  final CropController _cropController = CropController();
  bool _isCropping = false;
  Rect? _currentCropRect;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.backgroundImageText),
      ),
      body: Stack(
        children: <Widget>[
          // Crop widget
          Crop(
            controller: _cropController,
            image: widget.imageData,
            aspectRatio: widget.aspectRatio,
            initialRectBuilder: InitialRectBuilder.withSizeAndRatio(
              size: 0.8,
              aspectRatio: widget.aspectRatio,
            ),
            onCropped: (CropResult result) {
              if (mounted) {
                setState(() {
                  _isCropping = false;
                });
                if (result is CropSuccess) {
                  Navigator.pop(context, result.croppedImage);
                } else if (result is CropFailure) {
                  // Handle crop failure if necessary
                  logger.e("Crop failed: ${result.cause}");
                  if (result.stackTrace != null) {
                    logger.e("StackTrace: ${result.stackTrace}");
                  }
                }
              }
            },
            maskColor: Colors.black.withOpacity(0.5),
            onMoved:
                (ViewportBasedRect viewportRect, ImageBasedRect imageRect) {
              try {
                setState(() {
                  _currentCropRect = Rect.fromLTWH(
                    viewportRect.left,
                    viewportRect.top,
                    viewportRect.width,
                    viewportRect.height,
                  );
                });
              } catch (e) {
                logger.e("Error in onMoved: $e");
                logger.e(
                    "CropRect values - left: ${viewportRect.left}, top: ${viewportRect.top}, width: ${viewportRect.width}, height: ${viewportRect.height}");
              }
            },
          ),
          // Reference lines overlay
          if (_currentCropRect != null)
            Positioned(
              left: _currentCropRect!.left,
              top: _currentCropRect!.top,
              width: _currentCropRect!.width,
              height: _currentCropRect!.height,
              child: IgnorePointer(
                child: CustomPaint(
                  size: Size(_currentCropRect!.width, _currentCropRect!.height),
                  painter: ReferenceLinesPainter(widget.lineType),
                ),
              ),
            ),
          if (_isCropping)
            const Center(
              child: CircularProgressIndicator(),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.check),
        onPressed: () {
          if (mounted) {
            setState(() {
              _isCropping = true;
              try {
                _cropController.crop();
              } catch (e) {
                logger.e("Error in crop: $e");
                setState(() {
                  _isCropping = false;
                });
              }
            });
          }
        },
      ),
    );
  }
}

/// Enum to represent different types of reference lines
enum ReferenceLineType {
  boardLines,
  circle,
  none,
}

/// CustomPainter to draw reference lines within the cropping area
class ReferenceLinesPainter extends CustomPainter {
  ReferenceLinesPainter(this.lineType);

  /// Specifies the type of reference lines to be drawn
  final ReferenceLineType lineType;

  @override
  void paint(Canvas canvas, Size size) {
    switch (lineType) {
      case ReferenceLineType.boardLines:
        // Draw board lines similar to those on the game board
        BoardPainter.drawReferenceLines(canvas, size);
        break;
      case ReferenceLineType.circle:
        // Draw dashed circular reference lines
        final double radius = size.width / 2;
        final Offset center = Offset(size.width / 2, size.height / 2);

        // Use the BoardPainter to draw a dashed circular path
        BoardPainter.drawDashedCircle(canvas, center, radius);
        break;
      case ReferenceLineType.none:
        // Do nothing (no lines drawn)
        break;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
