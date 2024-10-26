import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;

import '../../shared/services/environment_config.dart';

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

  final double _gamma = 1.5;
  final int _adaptiveThresholdBlockSize = 9;
  final double _adaptiveThresholdC = 5;
  final double _contourAreaThreshold = 300; // 轮廓面积阈值
  final double _epsilonMultiplier = 0.04;
  final double _aspectRatioMin = 0.8;
  final double _aspectRatioMax = 1.2;
  final int _whiteGrayThreshold = 180;
  final int _blackGrayThreshold = 80;

  final double _angleTolerance = 0.1; // 用于线条过滤的角度公差
  final int _distanceThreshold = 30; // 用于检测相似线条的距离阈值

  List<Line> _filterLines(cv.Mat lines) {
    final double angleTolerance = _angleTolerance;
    final int distanceThreshold = _distanceThreshold;

    final List<Line> horizontalLines = <Line>[];
    final List<Line> verticalLines = <Line>[];

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

  List<Line> _removeDuplicateLines(List<Line> lines, int threshold) {
    lines.sort((Line a, Line b) => a.startPoint.y.compareTo(b.startPoint.y));

    final List<Line> filteredLines = <Line>[];
    for (final Line line in lines) {
      bool isDuplicate = false;
      for (final Line filteredLine in filteredLines) {
        final double startPointDistance = math.sqrt(
          math.pow(line.startPoint.x - filteredLine.startPoint.x, 2) +
              math.pow(line.startPoint.y - filteredLine.startPoint.y, 2),
        );

        final double endPointDistance = math.sqrt(
          math.pow(line.endPoint.x - filteredLine.endPoint.x, 2) +
              math.pow(line.endPoint.y - filteredLine.endPoint.y, 2),
        );

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

  List<cv.Point> _orderPoints(cv.VecPoint approx) {
    double cX = 0, cY = 0;
    for (final cv.Point p in approx) {
      cX += p.x;
      cY += p.y;
    }
    cX /= approx.length;
    cY /= approx.length;

    final List<PointWithAngle> pointsWithAngles = <PointWithAngle>[];
    for (final cv.Point p in approx) {
      final double angle = math.atan2(p.y - cY, p.x - cX);
      pointsWithAngles.add(PointWithAngle(
        cv.Point(p.x, p.y),
        angle,
      ));
    }

    pointsWithAngles.sort(
        (PointWithAngle a, PointWithAngle b) => a.angle.compareTo(b.angle));

    final List<cv.Point> sortedPoints =
        pointsWithAngles.map((PointWithAngle e) => e.point).toList();

    return sortedPoints;
  }

  cv.Mat _warpPerspective(cv.Mat mat, cv.VecPoint contour) {
    final List<cv.Point> orderedPoints = _orderPoints(contour);

    final cv.VecPoint srcPoints = cv.VecPoint.fromList(orderedPoints);

    // Destination points: 固定为500x500的图像
    final cv.VecPoint dstPoints = cv.VecPoint.fromList(<cv.Point>[
      cv.Point(0, 0),
      cv.Point(499, 0),
      cv.Point(499, 499),
      cv.Point(0, 499),
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

  // 获取棋盘上的24个网格点
  List<cv.Point2f> _getGridPoints() {
    final List<cv.Point2f> points = <cv.Point2f>[
      cv.Point2f(35.0, 40.0), // 0: 左上角
      cv.Point2f(250.0, 40.0), // 1: 上中点
      cv.Point2f(465.0, 40.0), // 2: 右上角
      cv.Point2f(35.0, 250.0), // 3: 左中点
      cv.Point2f(465.0, 250.0), // 4: 右中点
      cv.Point2f(35.0, 465.0), // 5: 左下角
      cv.Point2f(250.0, 465.0), // 6: 下中点
      cv.Point2f(465.0, 465.0), // 7: 右下角
      cv.Point2f(105.0, 110.0), // 8: 左上角
      cv.Point2f(250.0, 110.0), // 9: 上中点
      cv.Point2f(395.0, 110.0), // 10: 右上角
      cv.Point2f(105.0, 250.0), // 11: 左中点
      cv.Point2f(395.0, 250.0), // 12: 右中点
      cv.Point2f(105.0, 395.0), // 13: 左下角
      cv.Point2f(250.0, 395.0), // 14: 下中点
      cv.Point2f(395.0, 395.0), // 15: 右下角
      cv.Point2f(175.0, 180.0), // 16: 左上角
      cv.Point2f(250.0, 180.0), // 17: 上中点
      cv.Point2f(325.0, 180.0), // 18: 右上角
      cv.Point2f(175.0, 250.0), // 19: 左中点
      cv.Point2f(325.0, 250.0), // 20: 右中点
      cv.Point2f(175.0, 325.0), // 21: 左下角
      cv.Point2f(250.0, 325.0), // 22: 下中点
      cv.Point2f(325.0, 325.0), // 23: 右下角
    ];

    return points;
  }

  String _classifyPiece(cv.Mat mat, cv.Point2f center, double radius) {
    final cv.Mat gray = cv.cvtColor(mat, cv.COLOR_BGR2GRAY);

    final cv.Mat circularRoi = cv.getRectSubPix(
      gray,
      (radius.toInt() * 2, radius.toInt() * 2),
      center,
    );

    int totalGrayValue = 0;
    int totalPixels = 0;
    final Uint8List pixelData = circularRoi.data;
    for (int y = 0; y < circularRoi.rows; y++) {
      for (int x = 0; x < circularRoi.cols; x++) {
        final double distance =
            math.sqrt(math.pow(x - radius, 2) + math.pow(y - radius, 2));
        if (distance <= radius) {
          totalGrayValue += pixelData[y * circularRoi.cols + x];
          totalPixels++;
        }
      }
    }
    final double meanGray = totalGrayValue / totalPixels;

    if (meanGray > _whiteGrayThreshold) {
      return 'w';
    } else if (meanGray < _blackGrayThreshold) {
      return 'b';
    } else {
      return 'e';
    }
  }

  List<String> _detectPiecesUsingContours(cv.Mat thresh, cv.Mat originalMat) {
    // 检测阈值图像中的轮廓
    final (cv.Contours, cv.Mat) contoursResult = cv.findContours(
      thresh,
      cv.RETR_EXTERNAL,
      cv.CHAIN_APPROX_SIMPLE,
    );
    final cv.Contours contours = contoursResult.$1;

    // 在所有检测到的轮廓上绘制线条
    for (int i = 0; i < contours.length; i++) {
      final cv.VecPoint contour = contours[i];
      // 在原始图像上绘制轮廓线
      cv.drawContours(
        originalMat,
        contours,
        i,
        cv.Scalar(0, 0, 255), // 使用红色标记轮廓，方便调试
        thickness: 5,
      );
    }

    // 获取棋盘的24个点位
    final List<cv.Point2f> gridPoints = _getGridPoints();

    // 存储每个点位的棋子状态
    final List<String> positions = List<String>.filled(24, 'e');

    // 遍历每个轮廓，寻找圆形轮廓
    for (int i = 0; i < contours.length; i++) {
      final cv.VecPoint contour = contours[i];
      final double area = cv.contourArea(contour);

      // 筛选符合面积阈值的轮廓
      if (area > _contourAreaThreshold) {
        // 计算轮廓的圆形度
        final double perimeter = cv.arcLength(contour, true);
        final double circularity = 4 * math.pi * area / (perimeter * perimeter);

        // 设置圆形度阈值（例如0.7）
        if (circularity > 0.7) {
          // 计算最小外接圆
          final enclosingCircle = cv.minEnclosingCircle(contour);
          final cv.Point2f center = enclosingCircle.$1; // 或 enclosingCircle[0]
          final double radius = enclosingCircle.$2; // 或 enclosingCircle[1]

          // 绘制圆形轮廓
          cv.circle(
            originalMat,
            cv.Point(center.x.toInt(), center.y.toInt()),
            radius.toInt(),
            cv.Scalar(0, 255, 0),
            thickness: 2,
          );

          // 将该中心与最近的网格点位进行匹配
          double minDistance = double.infinity;
          int closestGridIndex = -1;

          for (int j = 0; j < gridPoints.length; j++) {
            final double distance = math.sqrt(
              math.pow(center.x - gridPoints[j].x, 2) +
                  math.pow(center.y - gridPoints[j].y, 2),
            );

            if (distance < minDistance) {
              minDistance = distance;
              closestGridIndex = j;
            }
          }

          // 如果轮廓中心距离某个网格点位小于阈值，则认为该点位上存在棋子
          if (minDistance < _distanceThreshold && closestGridIndex != -1) {
            // 检查该网格点是否已被占用，避免重复标记
            if (positions[closestGridIndex] == 'e') {
              final String color = _classifyPiece(originalMat, center, radius);
              positions[closestGridIndex] = color;

              // 绘制棋子的位置和颜色（添加轮廓框和文字标记）
              cv.rectangle(
                originalMat,
                cv.Rect(
                  (center.x - radius).toInt(),
                  (center.y - radius).toInt(),
                  (radius * 2).toInt(),
                  (radius * 2).toInt(),
                ),
                color == 'w' ? cv.Scalar(255, 255, 255) : cv.Scalar(0, 0, 0),
                thickness: 2,
              );

              cv.putText(
                originalMat,
                color,
                cv.Point(center.x.toInt() - 10, center.y.toInt() - 10),
                cv.FONT_HERSHEY_SIMPLEX,
                0.6,
                color == 'w' ? cv.Scalar(255, 255, 255) : cv.Scalar(0, 0, 0),
                thickness: 2,
                lineType: cv.LINE_AA,
              );
            }
          }
        }
      }
    }

    // 生成FEN串
    final String fen = _generateFEN(positions);

    // 释放内存
    contours.dispose();
    contoursResult.$2.dispose();

    return positions;
  }

  String _generateFEN(List<String> positions) {
    return positions.join();
  }

  Future<void> _processImage() async {
    final ImagePicker picker = ImagePicker();

    final XFile? imgFile = await picker.pickImage(source: ImageSource.gallery);
    if (imgFile == null) {
      return;
    }

    final Uint8List imageData = await imgFile.readAsBytes();

    final img.Image? decodedImage = img.decodeImage(imageData);
    if (decodedImage == null) {
      return;
    }

    final img.Image orientedImage = img.bakeOrientation(decodedImage);

    final Uint8List correctedImageData =
        Uint8List.fromList(img.encodeJpg(orientedImage));

    final cv.Mat mat = cv.imdecode(correctedImageData, cv.IMREAD_COLOR);

    final cv.Mat gray = cv.cvtColor(mat, cv.COLOR_BGR2GRAY);

    final List<num> grayPixels = gray.data;

    final double inverseGamma = 1.0 / _gamma;

    final List<num> gammaLUT = List<num>.generate(256, (int i) {
      final num value = (math.pow(i / 255.0, inverseGamma) * 255).toInt();
      return value;
    });

    for (int i = 0; i < grayPixels.length; i++) {
      final int original = grayPixels[i].toInt();
      grayPixels[i] = gammaLUT[original];
    }

    final cv.Mat enhanced =
        cv.Mat.fromList(gray.rows, gray.cols, gray.type, grayPixels);

    final cv.Mat blurred = cv.gaussianBlur(enhanced, (5, 5), 0);

    final cv.Mat thresh = cv.adaptiveThreshold(
      blurred,
      255,
      cv.ADAPTIVE_THRESH_GAUSSIAN_C,
      cv.THRESH_BINARY_INV,
      _adaptiveThresholdBlockSize,
      _adaptiveThresholdC,
    );

    // 结构元素过大会导致细节丢失，可以减小内核尺寸以保留更多轮廓细节
    final cv.Mat kernel = cv.getStructuringElement(cv.MORPH_RECT, (5, 5));
    final cv.Mat closed = cv.morphologyEx(thresh, cv.MORPH_CLOSE, kernel);

    grayImage = cv.imencode('.png', gray).$2;

    enhancedImage = cv.imencode('.png', enhanced).$2;

    threshImage = cv.imencode('.png', closed).$2;

    final (cv.Contours, cv.Mat) contoursResult = cv.findContours(
      closed,
      cv.RETR_EXTERNAL,
      cv.CHAIN_APPROX_SIMPLE,
    );
    final cv.Contours contours = contoursResult.$1;
    // final cv.Mat hierarchy = contoursResult.$2; // 删除未使用的变量

    cv.VecPoint? boardContour;
    double maxArea = 0;
    for (int idx = 0; idx < contours.length; idx++) {
      final cv.VecPoint contour = contours[idx];
      final double area = cv.contourArea(contour);

      if (area < _contourAreaThreshold) {
        continue;
      }

      final double peri = cv.arcLength(contour, true);

      final cv.VecPoint approx =
          cv.approxPolyDP(contour, _epsilonMultiplier * peri, true);

      final double circularity = 4 * math.pi * area / (peri * peri);

      if (approx.length == 4 && circularity > 0.6) {
        final cv.Rect rect = cv.boundingRect(approx);
        final double aspectRatio = rect.width / rect.height;

        if (aspectRatio > _aspectRatioMin && aspectRatio < _aspectRatioMax) {
          if (area > maxArea) {
            maxArea = area;
            boardContour = approx;
          }
        }
      }
    }

    if (boardContour != null) {
      final cv.Mat matWithContour = mat.clone();

      final List<cv.Point> boardContourPoints = boardContour.toList();

      final cv.Contours boardContours =
          cv.VecVecPoint.fromList(<List<cv.Point>>[boardContourPoints]);

      cv.drawContours(
        matWithContour,
        boardContours,
        -1,
        cv.Scalar(0, 255),
        thickness: 2,
      );

      grayImage = cv.imencode('.png', matWithContour).$2;

      final cv.Mat warped = _warpPerspective(mat, boardContour);

      if (EnvironmentConfig.devMode) {
        // 在透视变换后的图像上标记24个点位
        final List<cv.Point2f> gridPoints = _getGridPoints();
        for (final cv.Point2f point in gridPoints) {
          cv.circle(
            warped,
            cv.Point(point.x.toInt(), point.y.toInt()),
            5,
            cv.Scalar(0, 255), // 绿色标记点
            thickness: 2,
          );
        }
      }

      final cv.Mat warpedGray = cv.cvtColor(warped, cv.COLOR_BGR2GRAY);

      // 对透视变换后的灰度图像应用阈值处理
      final cv.Mat threshWarped = cv.adaptiveThreshold(
        warpedGray,
        255,
        cv.ADAPTIVE_THRESH_GAUSSIAN_C,
        cv.THRESH_BINARY_INV,
        _adaptiveThresholdBlockSize,
        _adaptiveThresholdC,
      );

      // 使用 contours 方法检测棋子
      final List<String> positions =
          _detectPiecesUsingContours(threshWarped, warped);

      final String fen = _generateFEN(positions);

      setState(() {
        _processedImage = cv.imencode('.png', warped).$2; // 使用标记后的透视变换图像
        _fenString = fen;
      });

      // 释放内存
      warped.dispose();
      boardContours.dispose();

      mat.dispose();
      matWithContour.dispose();
      gray.dispose();
      closed.dispose();

      blurred.dispose();
      thresh.dispose();
      kernel.dispose();
      enhanced.dispose();
    }

    // 释放内存
    contours.dispose();
    contoursResult.$2.dispose();
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
                if (grayImage != null) ...<Widget>[
                  const Text('灰度图像'),
                  Image.memory(grayImage!),
                ],
                if (enhancedImage != null) ...<Widget>[
                  const Text('增强图像'),
                  Image.memory(enhancedImage!),
                ],
                if (threshImage != null) ...<Widget>[
                  const Text('阈值图像'),
                  Image.memory(threshImage!),
                ],
                // 移除透视变换后的图像显示，因为已在_processedImage中显示
                /*
                if (warpedImage != null) ...<Widget>[
                  const Text('透视变换后的图像'),
                  Image.memory(warpedImage!),
                ],
                */
              ],
            ),
          ),
        ),
      ),
    );
  }
}
