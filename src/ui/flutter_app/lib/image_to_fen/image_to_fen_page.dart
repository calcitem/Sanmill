// image_to_fen_app.dart

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;

import '../../shared/services/logger.dart';
import '../shared/services/environment_config.dart';
import 'board_detection.dart';
import 'fen_generator.dart';
import 'image_processing_config.dart';
import 'piece_detection.dart';

class PointWithAngle {
  PointWithAngle(this.point, this.angle);
  final cv.Point point;
  final double angle;
}

class ImageToFenApp extends StatefulWidget {
  const ImageToFenApp({super.key});

  @override
  ImageToFenAppState createState() => ImageToFenAppState();
}

class ImageToFenAppState extends State<ImageToFenApp> {
  Uint8List? _debugImage;
  Uint8List? _processedImage;
  Uint8List? grayImage;
  Uint8List? enhancedImage;
  Uint8List? threshImage;
  Uint8List? warpedImage;
  Uint8List? _detectedLinesImage;

  String _fenString = '';

  // Add variables for board edge and size
  cv.Rect? _boardEdge;
  String _boardSize = 'Not Detected';

  Future<void> _processImage() async {
    logger.i('Starting _processImage function');

    final ImagePicker picker = ImagePicker();
    logger.i('Initialized ImagePicker');

    final XFile? imgFile = await picker.pickImage(source: ImageSource.gallery);
    if (imgFile == null) {
      logger.i('No image selected');
      return;
    }

    logger.i('Selected image path: ${imgFile.path}');
    logger.i('Image size: ${await imgFile.length()} bytes');

    // Read image data and correct orientation
    logger.i('Reading image data');
    final Uint8List imageData = await imgFile.readAsBytes();
    logger.i(
        'Successfully read image data, data length: ${imageData.length} bytes');

    logger.i('Decoding image');
    final img.Image? decodedImage = img.decodeImage(imageData);
    if (decodedImage == null) {
      logger.i('Failed to decode image');
      return;
    }
    logger.i(
        'Image decoded successfully, image dimensions: ${decodedImage.width}x${decodedImage.height}');

    logger.i('Correcting image orientation');
    final img.Image orientedImage = img.bakeOrientation(decodedImage);
    logger.i(
        'Dimensions after orientation correction: ${orientedImage.width}x${orientedImage.height}');

    logger.i('Encoding corrected image to JPEG');
    final Uint8List correctedImageData =
        Uint8List.fromList(img.encodeJpg(orientedImage));
    logger.i(
        'JPEG encoding completed, data length: ${correctedImageData.length} bytes');

    // Decode corrected image data to OpenCV Mat
    logger.i('Decoding corrected image data to OpenCV Mat');
    final cv.Mat mat = cv.imdecode(correctedImageData, cv.IMREAD_COLOR);
    logger.i(
        'OpenCV Mat decoding successful, Mat dimensions: ${mat.rows}x${mat.cols}, type: ${mat.type}');

    // Convert to grayscale
    logger.i('Converting to grayscale');
    final cv.Mat gray = cv.cvtColor(mat, cv.COLOR_BGR2GRAY);
    logger.i(
        'Grayscale conversion completed, Mat dimensions: ${gray.rows}x${gray.cols}, type: ${gray.type}');

    // Use gamma correction instead of CLAHE
    logger.i('Starting gamma correction');
    final List<num> grayPixels = gray.data;
    logger.i('Number of grayscale image pixels: ${grayPixels.length}');

    // Use adjustable gamma value
    final double inverseGamma = 1.0 / ImageProcessingConfig.gammaConfig.gamma;
    logger.i('Using inverse gamma value: $inverseGamma');

    // Generate LUT for faster gamma transformation
    logger.i('Generating gamma LUT (Look-Up Table)');
    final List<num> gammaLUT = List<num>.generate(256, (int i) {
      final num value = (math.pow(i / 255.0, inverseGamma) * 255).toInt();
      if (i % 50 == 0) {
        // Log every 50th value
        logger.i('LUT[$i] = $value');
      }
      return value;
    });
    logger.i('Gamma LUT generation complete');

    // Apply gamma correction
    logger.i('Applying gamma correction to grayscale image');
    for (int i = 0; i < grayPixels.length; i++) {
      final int original = grayPixels[i].toInt();
      grayPixels[i] = gammaLUT[original];
      if (i < 10) {
        // Log first 10 pixel values to avoid excessive logging
        logger.i(
            'Pixel[$i]: Original=$original, Corrected=${gammaLUT[original]}');
      }
      if (i == 10) {
        logger.i('Omitting further pixel logs...');
      }
    }
    logger.i('Gamma correction applied');

    // Convert array back to cv.Mat format
    logger.i('Converting gamma-corrected pixel array back to cv.Mat');
    final cv.Mat enhanced =
        cv.Mat.fromList(gray.rows, gray.cols, gray.type, grayPixels);
    logger.i(
        'Enhanced Mat dimensions: ${enhanced.rows}x${enhanced.cols}, type: ${enhanced.type}');

    // Apply Gaussian blur
    logger.i('Applying Gaussian blur');
    final cv.Mat blurred = cv.gaussianBlur(
        enhanced, ImageProcessingConfig.parameters.gaussianKernelSize, 0);
    logger.i(
        'Gaussian blur applied, Blurred Mat dimensions: ${blurred.rows}x${blurred.cols}');

    // Apply Canny edge detection
    final cv.Mat edges = cv.canny(blurred, 50, 150);
    logger.i(
        'Canny edge detection completed, Edges Mat dimensions: ${edges.rows}x${edges.cols}');

    // Adaptive thresholding
    logger.i('Applying adaptive thresholding');
    final cv.Mat thresh = cv.adaptiveThreshold(
      edges,
      255,
      cv.ADAPTIVE_THRESH_GAUSSIAN_C,
      cv.THRESH_BINARY_INV,
      ImageProcessingConfig.adaptiveThresholdConfig.blockSize,
      ImageProcessingConfig.adaptiveThresholdConfig.c,
    );
    logger.i(
        'Adaptive thresholding completed, Thresh Mat dimensions: ${thresh.rows}x${thresh.cols}');

    // Apply morphological closing to connect broken edges
    logger.i('Applying morphological closing to connect broken edges');
    final cv.Mat kernel = cv.getStructuringElement(
        cv.MORPH_RECT, ImageProcessingConfig.parameters.morphologyKernelSize);
    final cv.Mat closed = cv.morphologyEx(thresh, cv.MORPH_CLOSE, kernel);
    logger.i(
        'Morphological closing completed, Closed Mat dimensions: ${closed.rows}x${closed.cols}');

    // Debug: Display grayscale image, enhanced image, and thresholded image
    logger.i('Encoding grayscale image');
    grayImage = cv.imencode('.png', gray).$2;
    logger.i(
        'Grayscale image encoding completed, size: ${grayImage!.length} bytes');

    logger.i('Encoding enhanced image');
    enhancedImage = cv.imencode('.png', enhanced).$2;
    logger.i(
        'Enhanced image encoding completed, size: ${enhancedImage!.length} bytes');

    logger.i('Encoding thresholded image');
    threshImage = cv.imencode('.png', closed).$2;
    logger.i(
        'Thresholded image encoding completed, size: ${threshImage!.length} bytes');

    // Find contours
    logger.i('Finding contours');
    final (cv.Contours, cv.Mat) contoursResult =
        cv.findContours(closed, cv.RETR_EXTERNAL, cv.CHAIN_APPROX_SIMPLE);
    final cv.Contours contours = contoursResult.$1;
    final cv.Mat hierarchy = contoursResult.$2;
    logger.i('Contours found, number of detected contours: ${contours.length}');

    // Create a copy to draw contours that meet criteria
    final cv.Mat matWithContours = mat.clone();

    ////////////////////////////////////////////////////////////////////////////
    // Draw contours on the image, using blue
    if (EnvironmentConfig.devMode) {
      logger.i('Drawing contours on the image');
      cv.drawContours(
        matWithContours,
        contours,
        -1,
        cv.Scalar(255), // Blue in BGR
        thickness: 2,
      );
      logger.i('Contour drawing completed');

      // Encode image with contours
      logger.i('Encoding image with contours');
      _debugImage = cv.imencode('.png', matWithContours).$2;
      logger
          .i('Image with contours encoded, size: ${_debugImage!.length} bytes');
    }
    ////////////////////////////////////////////////////////////////////////////

    // Filter possible board contours
    logger.i('Filtering possible board contours');
    cv.VecPoint? boardContour;
    double maxArea = 0;
    for (int idx = 0; idx < contours.length; idx++) {
      final cv.VecPoint contour = contours[idx];
      final double area = cv.contourArea(contour);
      logger.i('Contour[$idx] area: $area');

      // Filter based on area
      if (area < ImageProcessingConfig.contourConfig.areaThreshold) {
        logger.i(
            'Contour[$idx] area below threshold ${ImageProcessingConfig.contourConfig.areaThreshold}, skipping');
        continue;
      }

      final double peri = cv.arcLength(contour, true);
      logger.i('Contour[$idx] perimeter: $peri');

      final cv.VecPoint approx = cv.approxPolyDP(
        contour,
        ImageProcessingConfig.contourConfig.epsilonMultiplier * peri,
        true,
      ); // Use adjustable epsilon
      logger.i(
          'Contour[$idx] approximated polygon vertices count: ${approx.length}');

      // Calculate contour circularity
      final double circularity = 4 * math.pi * area / (peri * peri);
      logger.i('Contour[$idx] circularity: $circularity');

      // Draw contours that meet criteria
      if (approx.length == 4 && circularity > 0.4) {
        cv.drawContours(
          matWithContours,
          cv.VecVecPoint.fromList(<List<cv.Point>>[approx.toList()]),
          -1,
          cv.Scalar(255), // Blue
          thickness: 2,
        );
        logger.i('Drawing contour[$idx]: area=$area, circularity=$circularity');
        _debugImage = cv.imencode('.png', matWithContours).$2;
      }

      // If quadrilateral and circularity is reasonable
      if (approx.length == 4 && circularity > 0.4) {
        logger.i('Contour[$idx] is quadrilateral and circularity > 0.4');
        // Check aspect ratio
        final cv.Rect rect = cv.boundingRect(approx);
        final double aspectRatio = rect.width / rect.height;
        logger.i('Contour[$idx] aspect ratio: $aspectRatio');

        if (aspectRatio > ImageProcessingConfig.contourConfig.aspectRatioMin &&
            aspectRatio < ImageProcessingConfig.contourConfig.aspectRatioMax) {
          logger.i(
              'Contour[$idx] aspect ratio within acceptable range (${ImageProcessingConfig.contourConfig.aspectRatioMin} - ${ImageProcessingConfig.contourConfig.aspectRatioMax})');
          // Use adjustable aspect ratio
          if (area > maxArea) {
            logger.i(
                'Contour[$idx] area larger than current max area ($maxArea), updating boardContour');
            maxArea = area;
            boardContour = approx;
          } else {
            logger.i(
                'Contour[$idx] area not larger than current max area ($maxArea), skipping');
          }
        } else {
          logger.i(
              'Contour[$idx] aspect ratio outside acceptable range (${ImageProcessingConfig.contourConfig.aspectRatioMin} - ${ImageProcessingConfig.contourConfig.aspectRatioMax})');
        }
      } else {
        logger.i(
            'Contour[$idx] not quadrilateral or circularity insufficient, skipping');
      }
    }

    if (boardContour != null) {
      logger.i('Board contour found, area: $maxArea');
      // Draw board contour on the original image
      final cv.Mat matWithContour = mat.clone();
      logger.i('Cloning original Mat to draw contour');

      // Convert VecPoint to List<Point>
      final List<cv.Point> boardContourPoints = boardContour.toList();
      logger.i('Board contour points count: ${boardContourPoints.length}');

      // Convert List<List<Point>> to Contours (VecVecPoint)
      final cv.Contours boardContours =
          cv.VecVecPoint.fromList(<List<cv.Point>>[boardContourPoints]);
      logger.i('Converted board contour to cv.Contours');

      logger.i('Drawing board contour on the image');
      cv.drawContours(
        matWithContour,
        boardContours,
        -1,
        cv.Scalar(
          ImageProcessingConfig.parameters.drawContoursColor.$1.toDouble(),
          ImageProcessingConfig.parameters.drawContoursColor.$2.toDouble(),
          ImageProcessingConfig.parameters.drawContoursColor.$3.toDouble(),
        ), // Using configured color
        thickness: ImageProcessingConfig.parameters.drawContoursThickness,
      );
      logger.i('Contour drawing completed');

      // Debug: Display image with contour
      logger.i('Encoding image with contour');
      grayImage = cv.imencode('.png', matWithContour).$2;
      logger.i(
          'Image with contour encoding completed, size: ${grayImage!.length} bytes');

      // Release temporary Contours
      logger.i('Releasing temporary Contours');
      boardContours.dispose();

      // Apply perspective transform to align the board
      logger.i('Applying perspective transform to align board');
      final cv.Mat warped = warpPerspective(mat, boardContour);
      logger.i(
          'Perspective transformation completed, Warped Mat dimensions: ${warped.rows}x${warped.cols}');

      // Apply edge detection and Hough line transform
      logger.i('Applying edge detection and Hough line transform');
      final (cv.Mat warpedWithLines, List<Line> detectedLines) =
          applyEdgeDetectionAndHoughLines(warped);
      logger.i(
          'Edge detection and Hough line transform completed, WarpedWithLines Mat dimensions: ${warpedWithLines.rows}x${warpedWithLines.cols}');

      logger.i('Extracting detected lines');
      logger.i('Total number of detected lines: ${detectedLines.length}');

      // Debug: Display warped image after perspective transformation
      logger.i('Encoding warped image after perspective transformation');
      warpedImage = cv.imencode('.png', warpedWithLines).$2;
      logger.i(
          'Warped image encoding completed, size: ${warpedImage!.length} bytes');

      // Draw detected lines
      // Clone the warpedWithLines image to draw detected lines
      final cv.Mat linesImage = warpedWithLines.clone();
      logger.i('Cloning warpedWithLines to draw detected lines');

      // Draw each detected line on the linesImage
      for (final Line line in detectedLines) {
        cv.line(
          linesImage,
          line.startPoint,
          line.endPoint,
          cv.Scalar(255), // Blue color in BGR
          thickness: 5,
        );
      }
      logger.i('All detected lines drawn on linesImage');

      // Encode the linesImage to PNG
      logger.i('Encoding image with detected lines');
      _detectedLinesImage = cv.imencode('.png', linesImage).$2;
      logger.i(
          'Image with detected lines encoded, size: ${_detectedLinesImage!.length} bytes');

      // Dispose of the temporary linesImage
      linesImage.dispose();

      // Calculate board edges
      logger.i('Calculating board edges and size');
      final List<Line> filteredLines = detectedLines;
      _boardEdge = computeBoardEdges(filteredLines);
      if (_boardEdge != null) {
        logger.i(
            'Board edge calculation complete: x=${_boardEdge!.x}, y=${_boardEdge!.y}, width=${_boardEdge!.width}, height=${_boardEdge!.height}');
      } else {
        logger.i('Failed to calculate board edge');
      }

      // Determine board size
      _boardSize = determineBoardSize(filteredLines);
      logger.i('Board size determined: $_boardSize');

      // Detect piece positions
      logger.i('Detecting piece positions');
      final List<String> positions = detectPieces(warped);
      logger.i('Number of detected piece positions: ${positions.length}');
      for (int i = 0; i < positions.length; i++) {
        logger.i('Piece[$i] position: ${positions[i]}');
      }

      // Draw detection results on the image
      logger.i('Drawing detection results on the image');
      final cv.Mat warpedWithAnnotations = warped.clone();
      annotatePieces(warpedWithAnnotations, positions);
      logger.i('Detection results drawn');

      // Generate FEN string
      logger.i('Generating FEN string');
      final String fen = generateFEN(positions);
      logger.i('Generated FEN string: $fen');

      setState(() {
        logger.i('Updating UI state');
        _processedImage = cv.imencode('.png', warpedWithAnnotations).$2;
        _fenString = fen;
        logger.i('UI state update complete');
      });

      // Release temporary images
      logger.i('Releasing temporary image resources');
      matWithContour.dispose();
      warpedWithAnnotations.dispose();
      warped.dispose();
      warpedWithLines.dispose();
    } else {
      logger.i("Nine Men's Morris Board not detected");
      setState(() {
        _debugImage = cv.imencode('.png', matWithContours).$2;
        _fenString = "Nine Men's Morris board not detected";
      });
    }

    // Release memory
    logger.i('Releasing all OpenCV Mat resources');
    mat.dispose();
    gray.dispose();
    enhanced.dispose();
    blurred.dispose();
    thresh.dispose();
    closed.dispose();
    kernel.dispose();
    hierarchy.dispose();
    logger.i('All resources released');
    // No need to dispose contours if they are lists

    logger.i('_processImage function completed');
  }

  @override
  Widget build(BuildContext context) {
    final UIConfig uiConfig = ImageProcessingConfig.uiConfig;

    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: Text(uiConfig.appBarTitle)),
        body: Center(
          child: SingleChildScrollView(
            child: Column(
              children: <Widget>[
                // Display board edge and size
                if (_boardEdge != null) ...<Widget>[
                  const SizedBox(height: 20),
                  Text(
                      'Board Edge: ${_boardEdge!.x}, ${_boardEdge!.y}, ${_boardEdge!.width}, ${_boardEdge!.height}'),
                ],
                if (_boardSize.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 10),
                  Text('Board Size: $_boardSize'),
                ],

                // Display processed image and FEN string
                if (_processedImage != null) ...<Widget>[
                  Image.memory(_processedImage!),
                  const SizedBox(height: 20),
                  Text('${uiConfig.fenStringLabel}$_fenString'),
                ],
                if (_fenString.isNotEmpty &&
                    _processedImage == null) ...<Widget>[
                  const SizedBox(height: 20),
                  Text(_fenString),
                ],

                // Image processing button
                ElevatedButton(
                  onPressed: _processImage,
                  child: Text(uiConfig.selectAndProcessImageButton),
                ),

                // Display debug images (optional)
                if (_debugImage != null) ...<Widget>[
                  const SizedBox(height: 20),
                  const Text('Debug Image:'),
                  Image.memory(_debugImage!),
                ],
                if (_detectedLinesImage != null) ...<Widget>[
                  const SizedBox(height: 20),
                  const Text('Detected Lines:'),
                  Image.memory(_detectedLinesImage!),
                ],
                if (grayImage != null) ...<Widget>[
                  Text(uiConfig.debugImageLabels['grayImage']!),
                  Image.memory(grayImage!),
                ],
                if (enhancedImage != null) ...<Widget>[
                  Text(uiConfig.debugImageLabels['enhancedImage']!),
                  Image.memory(enhancedImage!),
                ],
                if (threshImage != null) ...<Widget>[
                  Text(uiConfig.debugImageLabels['threshImage']!),
                  Image.memory(threshImage!),
                ],
                if (warpedImage != null) ...<Widget>[
                  Text(uiConfig.debugImageLabels['warpedImage']!),
                  Image.memory(warpedImage!),
                ],

                // Add slider configuration area
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: ImageProcessingConfig.uiConfig.sliders
                        .map((SliderConfig sliderConfig) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            // Slider title
                            Text(
                              '${sliderConfig.labelPrefix}${sliderConfig.labelFormatter(ImageProcessingConfig.getSliderValue(sliderConfig.configKey))}',
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            // Slider itself
                            Slider(
                              value: ImageProcessingConfig.getSliderValue(
                                  sliderConfig.configKey),
                              min: sliderConfig.min,
                              max: sliderConfig.max,
                              divisions: sliderConfig.divisions,
                              label: sliderConfig.labelFormatter(
                                  ImageProcessingConfig.getSliderValue(
                                      sliderConfig.configKey)),
                              onChanged: (double value) {
                                setState(() {
                                  ImageProcessingConfig.updateConfig(
                                      sliderConfig.configKey, value);
                                });
                              },
                            ),
                            // Slider description
                            Text(
                              sliderConfig.description,
                              style: TextStyle(color: Colors.grey[700]),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
