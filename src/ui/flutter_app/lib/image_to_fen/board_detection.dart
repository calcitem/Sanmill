// board_detection.dart

import 'dart:math' as math;
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'image_processing_config.dart';
import 'image_to_fen_page.dart';

class Line {
  Line(this.startPoint, this.endPoint);
  final cv.Point startPoint;
  final cv.Point endPoint;
}

List<Line> filterLines(cv.Mat lines) {
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

    if ((angle - 0).abs() <
            ImageProcessingConfig.houghTransformConfig.angleTolerance ||
        (angle - math.pi).abs() <
            ImageProcessingConfig.houghTransformConfig.angleTolerance) {
      horizontalLines.add(line);
    } else if ((angle - math.pi / 2).abs() <
        ImageProcessingConfig.houghTransformConfig.angleTolerance) {
      verticalLines.add(line);
    }
  }

  return <Line>[
    ...removeDuplicateLines(horizontalLines,
        ImageProcessingConfig.houghTransformConfig.distanceThreshold),
    ...removeDuplicateLines(verticalLines,
        ImageProcessingConfig.houghTransformConfig.distanceThreshold),
  ];
}

List<Line> removeDuplicateLines(List<Line> lines, int threshold) {
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

List<cv.Point> orderPoints(cv.VecPoint approx) {
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
  pointsWithAngles
      .sort((PointWithAngle a, PointWithAngle b) => a.angle.compareTo(b.angle));

  // Extract sorted points
  final List<cv.Point> sortedPoints =
      pointsWithAngles.map((PointWithAngle e) => e.point).toList();

  return sortedPoints;
}

cv.Mat warpPerspective(cv.Mat mat, cv.VecPoint contour) {
  // 获取排序后的四个顶点
  final List<cv.Point> orderedPoints = orderPoints(contour);

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
cv.Mat applyEdgeDetectionAndHoughLines(cv.Mat warped) {
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
    ImageProcessingConfig.houghTransformConfig.threshold, // 可调霍夫阈值
    minLineLength:
        ImageProcessingConfig.houghTransformConfig.minLineLength, // 可调最小线长
    maxLineGap:
        ImageProcessingConfig.houghTransformConfig.maxLineGap, // 可调最大线间隙
  );

  final List<Line> filteredLines = filterLines(lines);

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

// 提取检测到的线条
List<Line> extractDetectedLines(cv.Mat warpedWithLines) {
  final List<Line> lines = <Line>[];

  // 假设在 warpPerspective 后，applyEdgeDetectionAndHoughLines 已经绘制了线条
  // 这里可以进一步处理以提取线条信息
  // 例如，可以再次使用 HoughLinesP 或其他方法提取线条
  // 这里简化为返回空列表
  // 具体实现取决于实际需求

  // 实现具体的线条提取逻辑

  return lines;
}

// 计算棋盘边缘
// 计算棋盘边缘
cv.Rect? computeBoardEdges(List<Line> lines) {
  if (lines.isEmpty) {
    return null;
  }

  int minX = -0x80000000;
  int minY = -0x80000000;
  int maxX = 0x7FFFFFFF;
  int maxY = 0x7FFFFFFF;

  for (final Line line in lines) {
    minX = math.min(minX, math.min(line.startPoint.x, line.endPoint.x));
    minY = math.min(minY, math.min(line.startPoint.y, line.endPoint.y));
    maxX = math.max(maxX, math.max(line.startPoint.x, line.endPoint.x));
    maxY = math.max(maxY, math.max(line.startPoint.y, line.endPoint.y));
  }

  // 使用正确的构造函数并传递 double 类型参数
  return cv.Rect(
    minX,
    minY,
    maxX - minX,
    maxY - minY,
  );
}

// 确定棋盘尺寸
String determineBoardSize(List<Line> lines) {
  // 假设九子棋棋盘有固定数量的水平和垂直线
  // 根据实际检测到的线条数量来判断

  int horizontal = 0;
  int vertical = 0;

  for (final Line line in lines) {
    final double angle = math.atan2(
            (line.endPoint.y - line.startPoint.y).toDouble(),
            (line.endPoint.x - line.startPoint.x).toDouble()) *
        180 /
        math.pi;
    if (angle.abs() < 10 || (angle.abs() > 170)) {
      horizontal++;
    } else if ((angle.abs() - 90).abs() < 10) {
      vertical++;
    }
  }

  // 根据九子棋的标准，通常有8条水平线和8条垂直线
  if (horizontal >= 8 && vertical >= 8) {
    return '标准九子棋棋盘';
  } else {
    return '非标准棋盘，检测到 $horizontal 条水平线和 $vertical 条垂直线';
  }
}
