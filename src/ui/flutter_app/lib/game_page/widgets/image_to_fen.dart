import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;

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

class Line {
  Line(this.startPoint, this.endPoint);
  final cv.Point startPoint;
  final cv.Point endPoint;
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
      final cv.Mat mat = cv.imdecode(correctedImageData, cv.IMREAD_COLOR);

      // 转换为灰度图像
      final cv.Mat gray = cv.cvtColor(mat, cv.COLOR_BGR2GRAY);

      // 不支持 CLAHE，故使用伽马校正
      // 将灰度图像转换为数组格式
      final List<num> grayPixels = gray.data;

      // 定义伽马值
      const double gamma = 1.5;
      const double inverseGamma = 1.0 / gamma;

      // 生成查找表来加快伽马变换的速度
      final List<num> gammaLUT = List<num>.generate(256, (int i) {
        return (math.pow(i / 255.0, inverseGamma) * 255).toInt();
      });

      // 应用伽马校正
      for (int i = 0; i < grayPixels.length; i++) {
        grayPixels[i] = gammaLUT[grayPixels[i].toInt()];
      }

      // 将数组转换回 `cv.Mat` 格式
      final cv.Mat enhanced =
          cv.Mat.fromList(gray.rows, gray.cols, gray.type, grayPixels);

      // 使用高斯模糊
      final cv.Mat blurred = cv.gaussianBlur(enhanced, (5, 5), 0);

      // 自适应阈值
      final cv.Mat thresh = cv.adaptiveThreshold(
        blurred,
        255,
        cv.ADAPTIVE_THRESH_GAUSSIAN_C,
        cv.THRESH_BINARY_INV,
        15, // 增大块大小
        3, // 调整常数C
      );

      // 应用闭运算以连接断裂的边缘
      final cv.Mat kernel = cv.getStructuringElement(cv.MORPH_RECT, (5, 5));
      final cv.Mat closed = cv.morphologyEx(thresh, cv.MORPH_CLOSE, kernel);

      // 调试：显示灰度图像、增强图像和阈值图像
      grayImage = cv.imencode('.png', gray).$2;
      enhancedImage = cv.imencode('.png', enhanced).$2;
      threshImage = cv.imencode('.png', closed).$2;

      // Find contours
      final (cv.Contours, cv.Mat) contoursResult = cv.findContours(
        closed,
        cv.RETR_EXTERNAL,
        cv.CHAIN_APPROX_SIMPLE,
      );

      final cv.Contours contours = contoursResult.$1;
      final cv.Mat hierarchy = contoursResult.$2;

      logger.i('检测到的轮廓数量：${contours.length}'); // 调试信息

      // 筛选可能的棋盘轮廓
      cv.VecPoint? boardContour;
      double maxArea = 0;
      for (final cv.VecPoint contour in contours) {
        final double area = cv.contourArea(contour);
        // 根据面积过滤
        if (area < 10000) {
          continue;
        }
        final double peri = cv.arcLength(contour, true);
        final cv.VecPoint approx =
            cv.approxPolyDP(contour, 0.04 * peri, true); // 增大epsilon

        // 计算轮廓的圆度
        // ignore: prefer_final_locals
        double circularity = 4 * math.pi * area / (peri * peri);

        // 找到四边形且圆度合理
        if (approx.length == 4 && circularity > 0.7) {
          // 检查长宽比
          final cv.Rect rect = cv.boundingRect(approx);
          final double aspectRatio = rect.width / rect.height;
          if (aspectRatio > 0.8 && aspectRatio < 1.2) {
            if (area > maxArea) {
              maxArea = area;
              boardContour = approx;
            }
          }
        }
      }

      if (boardContour != null) {
        // 在原图像上绘制棋盘轮廓
        final cv.Mat matWithContour = mat.clone();

        // 将 VecPoint 转换为 List<Point>
        final List<cv.Point> boardContourPoints = boardContour.toList();

        // 将 List<List<Point>> 转换为 Contours (VecVecPoint)
        final cv.Contours boardContours =
            cv.VecVecPoint.fromList(<List<cv.Point>>[boardContourPoints]);

        cv.drawContours(
          matWithContour,
          boardContours,
          -1,
          cv.Scalar(0, 255), // 使用绿色绘制轮廓
          thickness: 2,
        );

        // 调试：显示带有轮廓的图像
        grayImage = cv.imencode('.png', matWithContour).$2;

        // 释放临时 Contours
        boardContours.dispose();

        // 透视变换对齐棋盘
        final cv.Mat warped = _warpPerspective(mat, boardContour);

        // 应用边缘检测和霍夫线变换
        final cv.Mat warpedWithLines = _applyEdgeDetectionAndHoughLines(warped);

        // 调试：显示透视变换后的图像
        warpedImage = cv.imencode('.png', warpedWithLines).$2;

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
        warped.dispose();
        warpedWithLines.dispose();
      } else {
        setState(() {
          _fenString = "未检测到 Nine Men's Morris 棋盘";
        });
      }

      // 释放内存
      mat.dispose();
      gray.dispose();
      enhanced.dispose();
      blurred.dispose();
      thresh.dispose();
      closed.dispose();
      kernel.dispose();
      hierarchy.dispose();
      // No need to dispose contours if they are lists
    }
  }

  List<Line> _filterLines(cv.Mat lines) {
    const double angleTolerance = 0.1; // Angle tolerance
    const int distanceThreshold = 10; // Distance threshold

    final List<Line> horizontalLines = <Line>[];
    final List<Line> verticalLines = <Line>[];

    // Iterate over the lines
    for (int i = 0; i < lines.rows; i++) {
      final cv.Point startPoint = cv.Point(lines.at(i, 0), lines.at(i, 1));
      final cv.Point endPoint = cv.Point(lines.at(i, 2), lines.at(i, 3));
      final Line line = Line(startPoint, endPoint);

      final double angle = math
          .atan2(
            (line.endPoint.y - line.startPoint.y).toDouble(),
            (line.endPoint.x - line.startPoint.x).toDouble(),
          )
          .abs();

      if ((angle - 0).abs() < angleTolerance ||
          (angle - math.pi).abs() < angleTolerance) {
        horizontalLines.add(line);
      } else if ((angle - math.pi / 2).abs() < angleTolerance) {
        verticalLines.add(line);
      }
    }

    return <Line>[
      ..._removeDuplicateLines(horizontalLines, distanceThreshold),
      ..._removeDuplicateLines(verticalLines, distanceThreshold),
    ];
  }

// 移除重复的或接近的直线
  List<Line> _removeDuplicateLines(List<Line> lines, int threshold) {
    lines.sort((Line a, Line b) => a.startPoint.y.compareTo(b.startPoint.y));

    final List<Line> filteredLines = <Line>[];
    for (final Line line in lines) {
      bool isDuplicate = false;
      for (final Line filteredLine in filteredLines) {
        // 计算两个点之间的欧氏距离
        final double startPointDistance = math.sqrt(
          math.pow(line.startPoint.x - filteredLine.startPoint.x, 2) +
              math.pow(line.startPoint.y - filteredLine.startPoint.y, 2),
        );

        final double endPointDistance = math.sqrt(
          math.pow(line.endPoint.x - filteredLine.endPoint.x, 2) +
              math.pow(line.endPoint.y - filteredLine.endPoint.y, 2),
        );

        // 判断是否在距离阈值内
        if (startPointDistance < threshold && endPointDistance < threshold) {
          isDuplicate = true;
          break;
        }
      }
      if (!isDuplicate) {
        filteredLines.add(line);
      }
    }

    return filteredLines;
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
    // 获取排序后的四个顶点
    final List<cv.Point> orderedPoints = _orderPoints(contour);

    final cv.VecPoint srcPoints = cv.VecPoint.fromList(orderedPoints);

    // 计算宽度和高度
    final double widthA = math.sqrt(
        math.pow(orderedPoints[2].x - orderedPoints[3].x, 2) +
            math.pow(orderedPoints[2].y - orderedPoints[3].y, 2));
    final double widthB = math.sqrt(
        math.pow(orderedPoints[1].x - orderedPoints[0].x, 2) +
            math.pow(orderedPoints[1].y - orderedPoints[0].y, 2));
    final double maxWidth = math.max(widthA, widthB);

    final double heightA = math.sqrt(
        math.pow(orderedPoints[1].x - orderedPoints[2].x, 2) +
            math.pow(orderedPoints[1].y - orderedPoints[2].y, 2));
    final double heightB = math.sqrt(
        math.pow(orderedPoints[0].x - orderedPoints[3].x, 2) +
            math.pow(orderedPoints[0].y - orderedPoints[3].y, 2));
    final double maxHeight = math.max(heightA, heightB);

    // Destination points
    final cv.VecPoint dstPoints = cv.VecPoint.fromList(<cv.Point>[
      cv.Point(0, 0),
      cv.Point(maxWidth.toInt() - 1, 0),
      cv.Point(maxWidth.toInt() - 1, maxHeight.toInt() - 1),
      cv.Point(0, maxHeight.toInt() - 1),
    ]);

    // Compute the perspective transform matrix
    final cv.Mat M = cv.getPerspectiveTransform(srcPoints, dstPoints);

    // Apply perspective transform
    final cv.Mat warped =
        cv.warpPerspective(mat, M, (maxWidth.toInt(), maxHeight.toInt()));

    // Release memory
    M.dispose();
    srcPoints.dispose();
    dstPoints.dispose();

    return warped;
  }

  // 边缘检测和霍夫线变换函数
  cv.Mat _applyEdgeDetectionAndHoughLines(cv.Mat warped) {
    // 转换为灰度图像
    final cv.Mat warpedGray = cv.cvtColor(warped, cv.COLOR_BGR2GRAY);

    // 应用高斯模糊
    final cv.Mat blurred = cv.gaussianBlur(warpedGray, (5, 5), 0);

    // 应用边缘检测（Canny）
    final cv.Mat edges = cv.canny(blurred, 50, 150);

    // 应用霍夫线变换
    final cv.Mat lines = cv.HoughLinesP(
      edges,
      1,
      math.pi / 180,
      100,
      minLineLength: 100,
      maxLineGap: 10,
    );

    final List<Line> filteredLines = _filterLines(lines);

    // Draw detected lines on the image
    final cv.Mat warpedWithLines = warped.clone();
    for (final Line line in filteredLines) {
      cv.line(
        warpedWithLines,
        line.startPoint,
        line.endPoint,
        cv.Scalar(0, 0, 255),
        thickness: 2,
      );
    }

    // 释放内存
    warpedGray.dispose();
    blurred.dispose();
    edges.dispose();
    lines.dispose();

    return warpedWithLines;
  }

// Piece detection function
  List<String> _detectPieces(cv.Mat warped) {
    final List<String> positions = List<String>.filled(24, 'e');

    // 动态计算网格点
    final List<cv.Point2f> gridPoints = _getDynamicGridPoints(warped);

    // 调试：在图像上绘制网格点
    if (EnvironmentConfig.devMode) {
      for (final cv.Point2f point in gridPoints) {
        cv.circle(
          warped,
          cv.Point(point.x.toInt(), point.y.toInt()),
          5,
          cv.Scalar(255), // 使用蓝色标记网格点
          thickness: -1,
        );
      }
    }

    // 定义相对阈值（例如，ROI总像素的指定比例）
    const double whiteThresholdRatio = 0.5;
    const double blackThresholdRatio = 0.5;

    for (int i = 0; i < gridPoints.length; i++) {
      final cv.Point2f point = gridPoints[i];

      // 提取感兴趣区域 (ROI)
      final cv.Mat roi = cv.getRectSubPix(
        warped,
        (30, 30),
        point,
      );

      // 转换为 HSV 颜色空间
      final cv.Mat hsv = cv.cvtColor(roi, cv.COLOR_BGR2HSV);

      // 应用形态学操作以减少噪声
      final cv.Mat kernel = cv.getStructuringElement(cv.MORPH_ELLIPSE, (3, 3));

      // 进行开运算
      final cv.Mat opened = cv.morphologyEx(
        hsv,
        cv.MORPH_OPEN,
        kernel,
      );

      // 进行闭运算
      final cv.Mat closed = cv.morphologyEx(
        opened,
        cv.MORPH_CLOSE,
        kernel,
      );

      // 释放中间变量
      opened.dispose();
      closed.dispose();
      kernel.dispose();

      // 定义白色和黑色的阈值
      final cv.Mat lowerWhite = cv.Mat.zeros(hsv.rows, hsv.cols, hsv.type);
      lowerWhite.setTo(cv.Scalar(0, 0, 200));

      final cv.Mat upperWhite = cv.Mat.zeros(hsv.rows, hsv.cols, hsv.type);
      upperWhite.setTo(cv.Scalar(180, 50, 255));

      final cv.Mat whiteMask = cv.inRange(hsv, lowerWhite, upperWhite);

      final cv.Mat lowerBlack = cv.Mat.zeros(hsv.rows, hsv.cols, hsv.type);
      lowerBlack.setTo(cv.Scalar());

      final cv.Mat upperBlack = cv.Mat.zeros(hsv.rows, hsv.cols, hsv.type);
      upperBlack.setTo(cv.Scalar(180, 255, 50));

      final cv.Mat blackMask = cv.inRange(hsv, lowerBlack, upperBlack);

      // 计算 ROI 总像素数
      final int totalPixels = roi.rows * roi.cols;

      // 计算非零像素数量
      final int whiteCount = cv.countNonZero(whiteMask);
      final int blackCount = cv.countNonZero(blackMask);

      // 计算阈值
      final int whiteThreshold = (totalPixels * whiteThresholdRatio).toInt();
      final int blackThreshold = (totalPixels * blackThresholdRatio).toInt();

      // 根据相对阈值确定棋子颜色
      if (whiteCount > whiteThreshold) {
        positions[i] = 'w';
      } else if (blackCount > blackThreshold) {
        positions[i] = 'b';
      } else {
        positions[i] = 'e';
      }

      // 释放内存
      roi.dispose();
      hsv.dispose();
      whiteMask.dispose();
      blackMask.dispose();
    }

    return positions;
  }

  // 动态获取棋盘上的24个网格点
  List<cv.Point2f> _getDynamicGridPoints(cv.Mat warped) {
    final double width = warped.cols.toDouble();
    final double height = warped.rows.toDouble();

    // 基于原始500x500图像的比例
    // 外层方框比例
    const double outerLeftXRatio = 35.0 / 500.0;
    const double outerCenterXRatio = 250.0 / 500.0;
    const double outerRightXRatio = 465.0 / 500.0;

    const double outerTopYRatio = 40.0 / 500.0;
    const double outerCenterYRatio = 250.0 / 500.0;
    const double outerBottomYRatio = 465.0 / 500.0;

    // 中层方框比例
    const double middleLeftXRatio = 105.0 / 500.0;
    const double middleCenterXRatio = 250.0 / 500.0;
    const double middleRightXRatio = 395.0 / 500.0;

    const double middleTopYRatio = 110.0 / 500.0;
    const double middleCenterYRatio = 250.0 / 500.0;
    const double middleBottomYRatio = 395.0 / 500.0;

    // 内层方框比例
    const double innerLeftXRatio = 175.0 / 500.0;
    const double innerCenterXRatio = 250.0 / 500.0;
    const double innerRightXRatio = 325.0 / 500.0;

    const double innerTopYRatio = 180.0 / 500.0;
    const double innerCenterYRatio = 250.0 / 500.0;
    const double innerBottomYRatio = 325.0 / 500.0;

    final List<cv.Point2f> points = <cv.Point2f>[
      // 外层方框角和中点
      cv.Point2f(outerLeftXRatio * width, outerTopYRatio * height), // 0: 左上角
      cv.Point2f(outerCenterXRatio * width, outerTopYRatio * height), // 1: 上中点
      cv.Point2f(outerRightXRatio * width, outerTopYRatio * height), // 2: 右上角
      cv.Point2f(outerLeftXRatio * width, outerCenterYRatio * height), // 3: 左中点
      cv.Point2f(
          outerRightXRatio * width, outerCenterYRatio * height), // 4: 右中点
      cv.Point2f(outerLeftXRatio * width, outerBottomYRatio * height), // 5: 左下角
      cv.Point2f(
          outerCenterXRatio * width, outerBottomYRatio * height), // 6: 下中点
      cv.Point2f(
          outerRightXRatio * width, outerBottomYRatio * height), // 7: 右下角

      // 中层方框角和中点
      cv.Point2f(middleLeftXRatio * width, middleTopYRatio * height), // 8: 左上角
      cv.Point2f(
          middleCenterXRatio * width, middleTopYRatio * height), // 9: 上中点
      cv.Point2f(
          middleRightXRatio * width, middleTopYRatio * height), // 10: 右上角
      cv.Point2f(
          middleLeftXRatio * width, middleCenterYRatio * height), // 11: 左中点
      cv.Point2f(
          middleRightXRatio * width, middleCenterYRatio * height), // 12: 右中点
      cv.Point2f(
          middleLeftXRatio * width, middleBottomYRatio * height), // 13: 左下角
      cv.Point2f(
          middleCenterXRatio * width, middleBottomYRatio * height), // 14: 下中点
      cv.Point2f(
          middleRightXRatio * width, middleBottomYRatio * height), // 15: 右下角

      // 内层方框角和中点
      cv.Point2f(innerLeftXRatio * width, innerTopYRatio * height), // 16: 左上角
      cv.Point2f(innerCenterXRatio * width, innerTopYRatio * height), // 17: 上中点
      cv.Point2f(innerRightXRatio * width, innerTopYRatio * height), // 18: 右上角
      cv.Point2f(
          innerLeftXRatio * width, innerCenterYRatio * height), // 19: 左中点
      cv.Point2f(
          innerRightXRatio * width, innerCenterYRatio * height), // 20: 右中点
      cv.Point2f(
          innerLeftXRatio * width, innerBottomYRatio * height), // 21: 左下角
      cv.Point2f(
          innerCenterXRatio * width, innerBottomYRatio * height), // 22: 下中点
      cv.Point2f(
          innerRightXRatio * width, innerBottomYRatio * height), // 23: 右下角
    ];

    return points;
  }

  // 在图像上绘制识别结果
  void _annotatePieces(cv.Mat image, List<String> positions) {
    final List<cv.Point2f> gridPoints = _getDynamicGridPoints(image);

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
