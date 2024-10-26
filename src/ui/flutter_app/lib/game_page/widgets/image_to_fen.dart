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

  // 定义关键阈值的状态变量
  double _gamma = 1.5; // 伽马值
  int _adaptiveThresholdBlockSize = 15; // 自适应阈值块大小
  double _adaptiveThresholdC = 3; // 自适应阈值常数C
  double _contourAreaThreshold = 10000; // 轮廓面积阈值
  double _epsilonMultiplier = 0.04; // 逼近多边形精度乘数
  double _aspectRatioMin = 0.8; // 长宽比最小值
  double _aspectRatioMax = 1.2; // 长宽比最大值
  int _houghThreshold = 100; // 霍夫线变换阈值
  double _minLineLength = 100; // 最小线长
  double _maxLineGap = 10; // 线段间隙阈值
  double _angleTolerance = 0.1; // 线角容差
  int _distanceThreshold = 10; // 线距离阈值
  double _whiteThresholdRatio = 0.5; // 白色阈值比率
  double _blackThresholdRatio = 0.5; // 黑色阈值比率

  Future<void> _processImage() async {
    logger.i('开始 _processImage 函数');

    final ImagePicker picker = ImagePicker();
    logger.i('初始化 ImagePicker');

    final XFile? imgFile = await picker.pickImage(source: ImageSource.gallery);
    if (imgFile == null) {
      logger.i('未选择任何图像');
      return;
    }

    logger.i('选择的图像路径: ${imgFile.path}');
    logger.i('图像大小: ${await imgFile.length()} 字节');

    try {
      // 读取图像数据并修正方向
      logger.i('读取图像数据');
      final Uint8List imageData = await imgFile.readAsBytes();
      logger.i('成功读取图像数据，数据长度: ${imageData.length} 字节');

      logger.i('解码图像');
      final img.Image? decodedImage = img.decodeImage(imageData);
      if (decodedImage == null) {
        logger.i('图像解码失败');
        return;
      }
      logger.i('图像解码成功，图像尺寸: ${decodedImage.width}x${decodedImage.height}');

      logger.i('修正图像方向');
      final img.Image orientedImage = img.bakeOrientation(decodedImage);
      logger.i('方向修正后的图像尺寸: ${orientedImage.width}x${orientedImage.height}');

      logger.i('编码修正后的图像为 JPEG');
      final Uint8List correctedImageData =
          Uint8List.fromList(img.encodeJpg(orientedImage));
      logger.i('JPEG 编码完成，数据长度: ${correctedImageData.length} 字节');

      // 将修正后的图像数据解码为 OpenCV Mat
      logger.i('将修正后的图像数据解码为 OpenCV Mat');
      final cv.Mat mat = cv.imdecode(correctedImageData, cv.IMREAD_COLOR);
      logger.i(
          'OpenCV Mat 解码成功，Mat 尺寸: ${mat.rows}x${mat.cols}, 类型: ${mat.type}');

      // 转换为灰度图像
      logger.i('转换为灰度图像');
      final cv.Mat gray = cv.cvtColor(mat, cv.COLOR_BGR2GRAY);
      logger.i('灰度转换完成，Mat 尺寸: ${gray.rows}x${gray.cols}, 类型: ${gray.type}');

      // 不支持 CLAHE，故使用伽马校正
      logger.i('开始伽马校正');
      final List<num> grayPixels = gray.data;
      logger.i('灰度图像像素数量: ${grayPixels.length}');

      // 使用可调的伽马值
      final double inverseGamma = 1.0 / _gamma;
      logger.i('使用的逆伽马值: $inverseGamma');

      // 生成查找表来加快伽马变换的速度
      logger.i('生成伽马查找表 (LUT)');
      final List<num> gammaLUT = List<num>.generate(256, (int i) {
        final num value = (math.pow(i / 255.0, inverseGamma) * 255).toInt();
        if (i % 50 == 0) {
          // 每50个值记录一次
          logger.i('LUT[$i] = $value');
        }
        return value;
      });
      logger.i('伽马查找表生成完成');

      // 应用伽马校正
      logger.i('应用伽马校正到灰度图像');
      for (int i = 0; i < grayPixels.length; i++) {
        final int original = grayPixels[i].toInt();
        grayPixels[i] = gammaLUT[original];
        if (i < 10) {
          // 仅记录前10个像素值以避免日志过多
          logger.i('像素[$i]: 原始=$original, 校正后=${gammaLUT[original]}');
        }
        if (i == 10) {
          logger.i('省略中间像素日志...');
        }
      }
      logger.i('伽马校正应用完成');

      // 将数组转换回 `cv.Mat` 格式
      logger.i('将伽马校正后的像素数组转换回 cv.Mat');
      final cv.Mat enhanced =
          cv.Mat.fromList(gray.rows, gray.cols, gray.type, grayPixels);
      logger.i(
          '增强后的 Mat 尺寸: ${enhanced.rows}x${enhanced.cols}, 类型: ${enhanced.type}');

      // 使用高斯模糊
      logger.i('应用高斯模糊');
      final cv.Mat blurred = cv.gaussianBlur(enhanced, (5, 5), 0);
      logger.i('高斯模糊完成，Blurred Mat 尺寸: ${blurred.rows}x${blurred.cols}');

      // 自适应阈值
      logger.i('应用自适应阈值');
      final cv.Mat thresh = cv.adaptiveThreshold(
        blurred,
        255,
        cv.ADAPTIVE_THRESH_GAUSSIAN_C,
        cv.THRESH_BINARY_INV,
        _adaptiveThresholdBlockSize, // 可调块大小
        _adaptiveThresholdC, // 可调常数C
      );
      logger.i('自适应阈值完成，Thresh Mat 尺寸: ${thresh.rows}x${thresh.cols}');

      // 应用闭运算以连接断裂的边缘
      logger.i('应用闭运算以连接断裂的边缘');
      final cv.Mat kernel = cv.getStructuringElement(cv.MORPH_RECT, (5, 5));
      final cv.Mat closed = cv.morphologyEx(thresh, cv.MORPH_CLOSE, kernel);
      logger.i('闭运算完成，Closed Mat 尺寸: ${closed.rows}x${closed.cols}');

      // 调试：显示灰度图像、增强图像和阈值图像
      logger.i('编码灰度图像');
      grayImage = cv.imencode('.png', gray).$2;
      logger.i('灰度图像编码完成，大小: ${grayImage!.length} 字节');

      logger.i('编码增强图像');
      enhancedImage = cv.imencode('.png', enhanced).$2;
      logger.i('增强图像编码完成，大小: ${enhancedImage!.length} 字节');

      logger.i('编码阈值图像');
      threshImage = cv.imencode('.png', closed).$2;
      logger.i('阈值图像编码完成，大小: ${threshImage!.length} 字节');

      // Find contours
      logger.i('查找轮廓');
      final (cv.Contours, cv.Mat) contoursResult = cv.findContours(
        closed,
        cv.RETR_EXTERNAL,
        cv.CHAIN_APPROX_SIMPLE,
      );
      final cv.Contours contours = contoursResult.$1;
      final cv.Mat hierarchy = contoursResult.$2;
      logger.i('轮廓查找完成，检测到的轮廓数量: ${contours.length}');

      // 筛选可能的棋盘轮廓
      logger.i('开始筛选可能的棋盘轮廓');
      cv.VecPoint? boardContour;
      double maxArea = 0;
      for (int idx = 0; idx < contours.length; idx++) {
        final cv.VecPoint contour = contours[idx];
        final double area = cv.contourArea(contour);
        logger.i('轮廓[$idx] 的面积: $area');

        // 根据面积过滤
        if (area < _contourAreaThreshold) {
          logger.i('轮廓[$idx] 面积小于阈值 $_contourAreaThreshold，跳过');
          continue;
        }

        final double peri = cv.arcLength(contour, true);
        logger.i('轮廓[$idx] 的周长: $peri');

        final cv.VecPoint approx = cv.approxPolyDP(
            contour, _epsilonMultiplier * peri, true); // 使用可调epsilon
        logger.i('轮廓[$idx] 的近似多边形顶点数量: ${approx.length}');

        // 计算轮廓的圆度
        final double circularity = 4 * math.pi * area / (peri * peri);
        logger.i('轮廓[$idx] 的圆度: $circularity');

        // 找到四边形且圆度合理
        if (approx.length == 4 && circularity > 0.6) {
          logger.i('轮廓[$idx] 是四边形且圆度大于 0.6');
          // 检查长宽比
          final cv.Rect rect = cv.boundingRect(approx);
          final double aspectRatio = rect.width / rect.height;
          logger.i('轮廓[$idx] 的长宽比: $aspectRatio');

          if (aspectRatio > _aspectRatioMin && aspectRatio < _aspectRatioMax) {
            logger.i(
                '轮廓[$idx] 的长宽比在可接受范围内 ($_aspectRatioMin - $_aspectRatioMax)');
            // 使用可调长宽比
            if (area > maxArea) {
              logger.i('轮廓[$idx] 的面积大于当前最大面积 ($maxArea)，更新 boardContour');
              maxArea = area;
              boardContour = approx;
            } else {
              logger.i('轮廓[$idx] 的面积不大于当前最大面积 ($maxArea)，跳过');
            }
          } else {
            logger.i(
                '轮廓[$idx] 的长宽比不在可接受范围内 ($_aspectRatioMin - $_aspectRatioMax)');
          }
        } else {
          logger.i('轮廓[$idx] 不是四边形或圆度不够，跳过');
        }
      }

      if (boardContour != null) {
        logger.i('找到棋盘轮廓，面积: $maxArea');
        // 在原图像上绘制棋盘轮廓
        final cv.Mat matWithContour = mat.clone();
        logger.i('克隆原始 Mat 以绘制轮廓');

        // 将 VecPoint 转换为 List<Point>
        final List<cv.Point> boardContourPoints = boardContour.toList();
        logger.i('棋盘轮廓的点数量: ${boardContourPoints.length}');

        // 将 List<List<Point>> 转换为 Contours (VecVecPoint)
        final cv.Contours boardContours =
            cv.VecVecPoint.fromList(<List<cv.Point>>[boardContourPoints]);
        logger.i('转换棋盘轮廓为 cv.Contours');

        logger.i('在图像上绘制棋盘轮廓');
        cv.drawContours(
          matWithContour,
          boardContours,
          -1,
          cv.Scalar(0, 255), // 使用绿色绘制轮廓
          thickness: 2,
        );
        logger.i('轮廓绘制完成');

        // 调试：显示带有轮廓的图像
        logger.i('编码带有轮廓的图像');
        grayImage = cv.imencode('.png', matWithContour).$2;
        logger.i('带轮廓图像编码完成，大小: ${grayImage!.length} 字节');

        // 释放临时 Contours
        logger.i('释放临时 Contours');
        boardContours.dispose();

        // 透视变换对齐棋盘
        logger.i('应用透视变换以对齐棋盘');
        final cv.Mat warped = _warpPerspective(mat, boardContour);
        logger.i('透视变换完成，Warped Mat 尺寸: ${warped.rows}x${warped.cols}');

        // 应用边缘检测和霍夫线变换
        logger.i('应用边缘检测和霍夫线变换');
        final cv.Mat warpedWithLines = _applyEdgeDetectionAndHoughLines(warped);
        logger.i(
            '边缘检测和霍夫线变换完成，WarpedWithLines Mat 尺寸: ${warpedWithLines.rows}x${warpedWithLines.cols}');

        // 调试：显示透视变换后的图像
        logger.i('编码透视变换后的图像');
        warpedImage = cv.imencode('.png', warpedWithLines).$2;
        logger.i('透视变换后图像编码完成，大小: ${warpedImage!.length} 字节');

        // Detect piece positions
        logger.i('检测棋子位置');
        final List<String> positions = _detectPieces(warped);
        logger.i('检测到的棋子位置数量: ${positions.length}');
        for (int i = 0; i < positions.length; i++) {
          logger.i('棋子[$i] 位置: ${positions[i]}');
        }

        // 在图像上绘制识别结果
        logger.i('在图像上绘制识别结果');
        final cv.Mat warpedWithAnnotations = warped.clone();
        _annotatePieces(warpedWithAnnotations, positions);
        logger.i('绘制识别结果完成');

        // Generate FEN string
        logger.i('生成 FEN 字符串');
        final String fen = _generateFEN(positions);
        logger.i('生成的 FEN 字符串: $fen');

        setState(() {
          logger.i('更新 UI 状态');
          _processedImage = cv.imencode('.png', warpedWithAnnotations).$2;
          _fenString = fen;
          logger.i('UI 状态更新完成');
        });

        // 释放临时图像
        logger.i('释放临时图像资源');
        matWithContour.dispose();
        warpedWithAnnotations.dispose();
        warped.dispose();
        warpedWithLines.dispose();
      } else {
        logger.i("未检测到 Nine Men's Morris Board");
        setState(() {
          _fenString = "未检测到 Nine Men's Morris 棋盘";
        });
      }

      // 释放内存
      logger.i('释放所有 OpenCV Mat 资源');
      mat.dispose();
      gray.dispose();
      enhanced.dispose();
      blurred.dispose();
      thresh.dispose();
      closed.dispose();
      kernel.dispose();
      hierarchy.dispose();
      logger.i('所有资源释放完成');
      // No need to dispose contours if they are lists
    } catch (e) {
      logger.e('处理图像时发生错误: $e', error: e);
    }

    logger.i('_processImage 函数结束');
  }

  List<Line> _filterLines(cv.Mat lines) {
    // 使用可调角度容差和距离阈值
    final double angleTolerance = _angleTolerance; // 角度容差
    final int distanceThreshold = _distanceThreshold; // 距离阈值

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

  // 调整后的 _orderPoints 函数，返回 List<cv.Point>
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

  // 调整后的 _warpPerspective 函数
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

    // 应用霍夫线变换，使用可调参数
    final cv.Mat lines = cv.HoughLinesP(
      edges,
      1,
      math.pi / 180,
      _houghThreshold, // 可调霍夫阈值
      minLineLength: _minLineLength, // 可调最小线长
      maxLineGap: _maxLineGap, // 可调最大线间隙
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
    final double whiteThresholdRatio = _whiteThresholdRatio; // 可调白色阈值比率
    final double blackThresholdRatio = _blackThresholdRatio; // 可调黑色阈值比率

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
                // 图像处理按钮
                ElevatedButton(
                  onPressed: _processImage,
                  child: const Text('选择并处理图像'),
                ),

                // 显示处理后的图像和FEN字符串
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
                if (warpedImage != null) ...<Widget>[
                  const Text('透视变换后的图像'),
                  Image.memory(warpedImage!),
                ],

                // 添加阈值设置区域
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      // 伽马值设置
                      Text(
                        '伽马值 (Gamma): ${_gamma.toStringAsFixed(2)}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Slider(
                        value: _gamma,
                        min: 0.5,
                        max: 3.0,
                        divisions: 25,
                        label: _gamma.toStringAsFixed(2),
                        onChanged: (double value) {
                          setState(() {
                            _gamma = value;
                          });
                        },
                      ),
                      Text(
                        '调整图像的亮度和对比度。较高的值会使图像更亮。',
                        style: TextStyle(color: Colors.grey[700]),
                      ),
                      const SizedBox(height: 16),

                      // 自适应阈值块大小设置
                      Text(
                        '自适应阈值块大小: $_adaptiveThresholdBlockSize',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Slider(
                        value: _adaptiveThresholdBlockSize.toDouble(),
                        min: 3,
                        max: 31,
                        divisions: 14,
                        label: _adaptiveThresholdBlockSize.toString(),
                        onChanged: (double value) {
                          setState(() {
                            // 阻止块大小为偶数
                            _adaptiveThresholdBlockSize =
                                value.toInt() | 1; // 确保为奇数
                          });
                        },
                      ),
                      Text(
                        '影响阈值化时考虑的局部区域大小。较大的块大小可以更好地适应光照不均。',
                        style: TextStyle(color: Colors.grey[700]),
                      ),
                      const SizedBox(height: 16),

                      // 自适应阈值常数C设置
                      Text(
                        '自适应阈值常数 C: $_adaptiveThresholdC',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Slider(
                        value: _adaptiveThresholdC,
                        min: -10,
                        max: 10,
                        divisions: 20,
                        label: _adaptiveThresholdC.toString(),
                        onChanged: (double value) {
                          setState(() {
                            _adaptiveThresholdC = value;
                          });
                        },
                      ),
                      Text(
                        '用于自适应阈值的常数，减去块的平均值。正值会使阈值降低，负值则相反。',
                        style: TextStyle(color: Colors.grey[700]),
                      ),
                      const SizedBox(height: 16),

                      // 轮廓面积阈值设置
                      Text(
                        '轮廓面积阈值: ${_contourAreaThreshold.toInt()}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Slider(
                        value: _contourAreaThreshold,
                        min: 1000,
                        max: 50000,
                        divisions: 49,
                        label: _contourAreaThreshold.toInt().toString(),
                        onChanged: (double value) {
                          setState(() {
                            _contourAreaThreshold = value;
                          });
                        },
                      ),
                      Text(
                        '筛选轮廓时的最小面积。较高的值会忽略较小的轮廓。',
                        style: TextStyle(color: Colors.grey[700]),
                      ),
                      const SizedBox(height: 16),

                      // 逼近多边形精度乘数设置
                      Text(
                        '逼近多边形精度乘数: ${_epsilonMultiplier.toStringAsFixed(2)}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Slider(
                        value: _epsilonMultiplier,
                        min: 0.01,
                        max: 0.1,
                        divisions: 9,
                        label: _epsilonMultiplier.toStringAsFixed(2),
                        onChanged: (double value) {
                          setState(() {
                            _epsilonMultiplier = value;
                          });
                        },
                      ),
                      Text(
                        '多边形逼近的精度，值越大逼近越粗略。',
                        style: TextStyle(color: Colors.grey[700]),
                      ),
                      const SizedBox(height: 16),

                      // 长宽比最小值设置
                      Text(
                        '长宽比最小值: ${_aspectRatioMin.toStringAsFixed(2)}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Slider(
                        value: _aspectRatioMin,
                        min: 0.5,
                        max: 1.5,
                        divisions: 20,
                        label: _aspectRatioMin.toStringAsFixed(2),
                        onChanged: (double value) {
                          setState(() {
                            _aspectRatioMin = value;
                          });
                        },
                      ),
                      Text(
                        '筛选轮廓时的最小长宽比。用于确保轮廓接近正方形。',
                        style: TextStyle(color: Colors.grey[700]),
                      ),
                      const SizedBox(height: 16),

                      // 长宽比最大值设置
                      Text(
                        '长宽比最大值: ${_aspectRatioMax.toStringAsFixed(2)}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Slider(
                        value: _aspectRatioMax,
                        min: 0.5,
                        max: 1.5,
                        divisions: 20,
                        label: _aspectRatioMax.toStringAsFixed(2),
                        onChanged: (double value) {
                          setState(() {
                            _aspectRatioMax = value;
                          });
                        },
                      ),
                      Text(
                        '筛选轮廓时的最大长宽比。用于确保轮廓接近正方形。',
                        style: TextStyle(color: Colors.grey[700]),
                      ),
                      const SizedBox(height: 16),

                      // 霍夫线变换阈值设置
                      Text(
                        '霍夫线变换阈值: $_houghThreshold',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Slider(
                        value: _houghThreshold.toDouble(),
                        min: 50,
                        max: 200,
                        divisions: 150,
                        label: _houghThreshold.toString(),
                        onChanged: (double value) {
                          setState(() {
                            _houghThreshold = value.toInt();
                          });
                        },
                      ),
                      Text(
                        '霍夫线变换中检测直线的最小投票数。较高的值会检测到更明显的直线。',
                        style: TextStyle(color: Colors.grey[700]),
                      ),
                      const SizedBox(height: 16),

                      // 最小线长设置
                      Text(
                        '最小线长: $_minLineLength',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Slider(
                        value: _minLineLength,
                        min: 50,
                        max: 300,
                        divisions: 25,
                        label: _minLineLength.toString(),
                        onChanged: (double value) {
                          setState(() {
                            _minLineLength = value;
                          });
                        },
                      ),
                      Text(
                        '霍夫线变换中检测直线的最小长度。较长的线段会被优先检测。',
                        style: TextStyle(color: Colors.grey[700]),
                      ),
                      const SizedBox(height: 16),

                      // 线段间隙阈值设置
                      Text(
                        '线段间隙阈值: $_maxLineGap',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Slider(
                        value: _maxLineGap,
                        min: 5,
                        max: 50,
                        divisions: 45,
                        label: _maxLineGap.toString(),
                        onChanged: (double value) {
                          setState(() {
                            _maxLineGap = value;
                          });
                        },
                      ),
                      Text(
                        '霍夫线变换中，允许的最大线段间隙。较大的值会将接近的线段合并。',
                        style: TextStyle(color: Colors.grey[700]),
                      ),
                      const SizedBox(height: 16),

                      // 线角容差设置
                      Text(
                        '线角容差: ${_angleTolerance.toStringAsFixed(2)}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Slider(
                        value: _angleTolerance,
                        max: math.pi / 4, // 0 到 45度
                        divisions: 45,
                        label: _angleTolerance.toStringAsFixed(2),
                        onChanged: (double value) {
                          setState(() {
                            _angleTolerance = value;
                          });
                        },
                      ),
                      Text(
                        '筛选直线时的角度容差（弧度）。用于区分水平和垂直线。',
                        style: TextStyle(color: Colors.grey[700]),
                      ),
                      const SizedBox(height: 16),

                      // 线距离阈值设置
                      Text(
                        '线距离阈值: $_distanceThreshold',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Slider(
                        value: _distanceThreshold.toDouble(),
                        min: 5,
                        max: 50,
                        divisions: 45,
                        label: _distanceThreshold.toString(),
                        onChanged: (double value) {
                          setState(() {
                            _distanceThreshold = value.toInt();
                          });
                        },
                      ),
                      Text(
                        '筛选直线时的距离阈值。用于移除接近的重复线段。',
                        style: TextStyle(color: Colors.grey[700]),
                      ),
                      const SizedBox(height: 16),

                      // 白色阈值比率设置
                      Text(
                        '白色阈值比率: ${_whiteThresholdRatio.toStringAsFixed(2)}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Slider(
                        value: _whiteThresholdRatio,
                        divisions: 100,
                        label: _whiteThresholdRatio.toStringAsFixed(2),
                        onChanged: (double value) {
                          setState(() {
                            _whiteThresholdRatio = value;
                          });
                        },
                      ),
                      Text(
                        '检测白色棋子时的像素比例阈值。较高的值需要更多的白色像素以识别为白棋。',
                        style: TextStyle(color: Colors.grey[700]),
                      ),
                      const SizedBox(height: 16),

                      // 黑色阈值比率设置
                      Text(
                        '黑色阈值比率: ${_blackThresholdRatio.toStringAsFixed(2)}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Slider(
                        value: _blackThresholdRatio,
                        divisions: 100,
                        label: _blackThresholdRatio.toStringAsFixed(2),
                        onChanged: (double value) {
                          setState(() {
                            _blackThresholdRatio = value;
                          });
                        },
                      ),
                      Text(
                        '检测黑色棋子时的像素比例阈值。较高的值需要更多的黑色像素以识别为黑棋。',
                        style: TextStyle(color: Colors.grey[700]),
                      ),
                      const SizedBox(height: 16),
                    ],
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
