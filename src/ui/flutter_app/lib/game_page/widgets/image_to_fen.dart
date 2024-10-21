import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'package:opencv_dart/opencv_dart.dart';

import '../../shared/services/environment_config.dart';
import '../../shared/services/logger.dart';

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
  Uint8List? _processedImage;

  Uint8List? grayImage;
  Uint8List? enhancedImage;
  Uint8List? threshImage;
  Uint8List? warpedImage;

  String _fenString = '';

  Future<void> _processImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? imgFile = await picker.pickImage(source: ImageSource.gallery);

    if (imgFile != null) {
      // 读取图像数据并修正方向
      final Uint8List imageData = await imgFile.readAsBytes();
      final img.Image image = img.decodeImage(imageData)!;
      final img.Image orientedImage = img.bakeOrientation(image);
      final Uint8List correctedImageData =
          Uint8List.fromList(img.encodeJpg(orientedImage));

      // 将修正后的图像数据解码为 OpenCV Mat
      final cv.Mat mat = cv.imdecode(correctedImageData,
          cv.IMREAD_UNCHANGED); // 使用 IMREAD_UNCHANGED 来保留通道信息

      cv.Mat gray;

      // 检查图像的通道数
      if (mat.channels == 1) {
        // 如果图像已经是灰度图像，直接使用
        gray = mat;
      } else if (mat.channels == 3) {
        // 如果图像是彩色图像，转换为灰度图像
        gray = cv.cvtColor(mat, cv.COLOR_BGR2GRAY);
      } else {
        throw Exception('不支持的图像通道数: ${mat.channels}');
      }

      // Preprocessing: Histogram Equalization and median blur
      final cv.Mat enhanced = cv.equalizeHist(gray);
      final cv.Mat medianBlurred = cv.medianBlur(enhanced, 5);
      final cv.Mat thresh = cv.adaptiveThreshold(
        medianBlurred,
        255,
        cv.ADAPTIVE_THRESH_GAUSSIAN_C,
        cv.THRESH_BINARY_INV,
        11,
        2,
      );

      // 调试：显示灰度图像、增强图像和阈值图像
      grayImage = cv.imencode('.png', gray).$2;
      enhancedImage = cv.imencode('.png', enhanced).$2;
      threshImage = cv.imencode('.png', thresh).$2;

      // Find contours
      final (cv.Contours, cv.Mat) contoursResult = cv.findContours(
        thresh,
        cv.RETR_EXTERNAL,
        cv.CHAIN_APPROX_SIMPLE,
      );

      final cv.Contours contours = contoursResult.$1;
      final cv.Mat hierarchy = contoursResult.$2;

      logger.i('检测到的轮廓数量：${contours.length}'); // 调试信息

      // Find the largest contour, assuming it's the board
      cv.VecPoint? boardContour;
      double maxArea = 0;
      for (final cv.VecPoint contour in contours) {
        final double area = cv.contourArea(contour);
        if (area > maxArea) {
          maxArea = area;
          boardContour = contour;
        }
      }

      if (boardContour != null) {
        // 在原图像上绘制棋盘轮廓
        final cv.Mat matWithContour = mat.clone();
        // 使用现有的 contours 而不是创建新的 cv.Contours 对象
        cv.drawContours(matWithContour, contours, -1, cv.Scalar(0, 255),
            thickness: 2);

        // Perspective transform to align the board
        final cv.Mat warped = _warpPerspective(mat, boardContour);

        // 调试：显示透视变换后的图像
        warpedImage = cv.imencode('.png', warped).$2;

        // Detect piece positions
        final List<String> positions = _detectPieces(warped);

        // 在图像上绘制识别结果
        final cv.Mat warpedWithAnnotations = warped.clone();
        _annotatePieces(warpedWithAnnotations, positions);

        // Generate FEN string
        final String fen = _generateFEN(positions);

        setState(() {
          _processedImage = cv.imencode('.png', warpedWithAnnotations).$2;
          _fenString = fen;
        });

        // 释放临时图像
        matWithContour.dispose();
        warpedWithAnnotations.dispose();
      } else {
        setState(() {
          _fenString = "未检测到 Nine Men's Morris 棋盘";
        });
      }

      // Release memory
      mat.dispose();
      gray.dispose();
      enhanced.dispose();
      medianBlurred.dispose();
      thresh.dispose();
      hierarchy.dispose();
      // No need to dispose contours if they are lists
    }
  }

  // Adjusted _orderPoints to return List<cv.Point>
  List<cv.Point> _orderPoints(cv.VecPoint approx) {
    // Compute centroid
    double cX = 0, cY = 0;
    for (final cv.Point p in approx) {
      cX += p.x;
      cY += p.y;
    }
    cX /= approx.length;
    cY /= approx.length;

    // Compute angles
    final List<PointWithAngle> pointsWithAngles = <PointWithAngle>[];
    for (final cv.Point p in approx) {
      final double angle = math.atan2(p.y - cY, p.x - cX);
      pointsWithAngles.add(PointWithAngle(
        cv.Point(p.x, p.y),
        angle,
      ));
    }

    // Sort points by angle
    pointsWithAngles.sort(
        (PointWithAngle a, PointWithAngle b) => a.angle.compareTo(b.angle));

    // Extract sorted points
    final List<cv.Point> sortedPoints =
        pointsWithAngles.map((PointWithAngle e) => e.point).toList();

    return sortedPoints;
  }

// Adjusted _warpPerspective function
  cv.Mat _warpPerspective(cv.Mat mat, cv.VecPoint contour) {
    final double peri = cv.arcLength(contour, true);
    final cv.VecPoint approx = cv.approxPolyDP(contour, 0.02 * peri, true);

    if (approx.length != 4) {
      return mat;
    }

    final List<cv.Point> orderedPoints = _orderPoints(approx);

    final cv.VecPoint srcPoints = cv.VecPoint.fromList(orderedPoints);

    // Destination points
    final cv.VecPoint dstPoints = cv.VecPoint.fromList(<cv.Point>[
      cv.Point(0, 0),
      cv.Point(500, 0),
      cv.Point(500, 500),
      cv.Point(0, 500),
    ]);

    // Compute the perspective transform matrix
    final cv.Mat M = cv.getPerspectiveTransform(srcPoints, dstPoints);

    // Apply perspective transform
    final cv.Mat warped = cv.warpPerspective(mat, M, (500, 500));

    // Release memory
    M.dispose();
    srcPoints.dispose();
    dstPoints.dispose();

    return warped;
  }

  // Piece detection function
  // Piece detection function
  List<String> _detectPieces(cv.Mat warped) {
    final List<String> positions =
        List<String>.filled(24, 'e'); // 'e' represents empty

    // Get grid points
    final List<cv.Point2f> gridPoints = _getGridPoints();

    // Debug: Draw grid points on the image
    if (EnvironmentConfig.devMode) {
      for (final cv.Point2f point in gridPoints) {
        cv.circle(
          warped,
          cv.Point(point.x.toInt(), point.y.toInt()),
          5,
          cv.Scalar(255, 0, 0), // Use blue color to mark grid points
          thickness: -1,
        );
      }
    }

    for (int i = 0; i < gridPoints.length; i++) {
      final cv.Point2f point = gridPoints[i];

      // Extract region of interest
      final cv.Mat roi = cv.getRectSubPix(
        warped,
        (30, 30),
        point,
      );

      // Convert to grayscale
      final cv.Mat gray = cv.cvtColor(roi, cv.COLOR_BGR2GRAY);

      // Apply binary threshold to detect white pieces
      final cv.Mat threshWhite = cv
          .threshold(
            gray,
            200,
            255,
            cv.THRESH_BINARY,
          )
          .$2;

      // Apply inverse binary threshold to detect black pieces
      final cv.Mat threshBlack = cv
          .threshold(
            gray,
            50,
            255,
            cv.THRESH_BINARY_INV,
          )
          .$2;

      // Count non-zero pixels
      final int whiteCount = cv.countNonZero(threshWhite);
      final int blackCount = cv.countNonZero(threshBlack);

      // Determine piece color based on pixel counts
      if (whiteCount > 100) {
        positions[i] = 'w';
      } else if (blackCount > 100) {
        positions[i] = 'b';
      } else {
        positions[i] = 'e';
      }

      // Release memory
      roi.dispose();
      gray.dispose();
      threshWhite.dispose();
      threshBlack.dispose();
    }

    return positions;
  }

  // 在图像上绘制识别结果
  void _annotatePieces(cv.Mat image, List<String> positions) {
    final List<cv.Point2f> gridPoints = _getGridPoints();

    for (int i = 0; i < positions.length; i++) {
      final cv.Point2f point = gridPoints[i];
      final String label = positions[i];

      // 设置文本位置，调整偏移量使其在蓝点正上方
      final cv.Point textOrg = cv.Point(
        point.x.toInt() - 10, // 适当调整x偏移量
        point.y.toInt() + 5, // 适当调整y偏移量
      );
      cv.putText(
        image,
        label,
        textOrg,
        cv.FONT_HERSHEY_SIMPLEX,
        1,
        cv.Scalar(0, 0, 255), // 使用红色标记棋子
        thickness: 2, // 增加线条厚度，使标记更清晰
        lineType: cv.LINE_AA,
      );
    }
  }

  // Get the 24 grid points on the board
  List<cv.Point2f> _getGridPoints() {
    // Corrected Nine Men's Morris positions based on your adjustments
    return <cv.Point2f>[
      // Outer square corners and midpoints
      cv.Point2f(35.0, 40.0), // 0: Top-left corner
      cv.Point2f(250.0, 40.0), // 1: Top midpoint
      cv.Point2f(465.0, 35.0), // 2: Top-right corner
      cv.Point2f(35.0, 250.0), // 3: Left midpoint
      cv.Point2f(465.0, 250.0), // 4: Right midpoint
      cv.Point2f(35.0, 465.0), // 5: Bottom-left corner
      cv.Point2f(250.0, 465.0), // 6: Bottom midpoint
      cv.Point2f(465.0, 465.0), // 7: Bottom-right corner

      // Middle square corners and midpoints
      cv.Point2f(105.0, 110.0), // 8: Top-left corner
      cv.Point2f(250.0, 110.0), // 9: Top midpoint
      cv.Point2f(395.0, 105.0), // 10: Top-right corner
      cv.Point2f(105.0, 250.0), // 11: Left midpoint
      cv.Point2f(395.0, 250.0), // 12: Right midpoint
      cv.Point2f(105.0, 395.0), // 13: Bottom-left corner
      cv.Point2f(250.0, 395.0), // 14: Bottom midpoint
      cv.Point2f(395.0, 395.0), // 15: Bottom-right corner

      // Inner square corners and midpoints
      cv.Point2f(175.0, 180.0), // 16: Top-left corner
      cv.Point2f(250.0, 180.0), // 17: Top midpoint
      cv.Point2f(325.0, 175.0), // 18: Top-right corner
      cv.Point2f(175.0, 250.0), // 19: Left midpoint
      cv.Point2f(325.0, 250.0), // 20: Right midpoint
      cv.Point2f(175.0, 325.0), // 21: Bottom-left corner
      cv.Point2f(250.0, 325.0), // 22: Bottom midpoint
      cv.Point2f(325.0, 325.0), // 23: Bottom-right corner
    ];
  }

  // Generate FEN string
  String _generateFEN(List<String> positions) {
    // Convert position list to string
    return positions.join();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text("Nine Men's Morris 识别")),
        body: Center(
          child: SingleChildScrollView(
            child: Column(
              children: <Widget>[
                ElevatedButton(
                  onPressed: _processImage,
                  child: const Text('选择并处理图像'),
                ),
                if (_processedImage != null) ...<Widget>[
                  Image.memory(_processedImage!),
                  const SizedBox(height: 20),
                  Text('FEN 串：$_fenString'),
                ],
                if (_fenString.isNotEmpty &&
                    _processedImage == null) ...<Widget>[
                  const SizedBox(height: 20),
                  Text(_fenString),
                ],
                // 显示调试图像（可选）
                if (grayImage != null) Image.memory(grayImage!),
                if (enhancedImage != null) Image.memory(enhancedImage!),
                if (threshImage != null) Image.memory(threshImage!),
                if (warpedImage != null) Image.memory(warpedImage!),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
