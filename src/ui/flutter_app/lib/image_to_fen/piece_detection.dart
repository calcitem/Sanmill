import 'dart:math' as math;

import 'package:opencv_dart/opencv_dart.dart' as cv;

import '../shared/services/environment_config.dart';
import '../shared/services/logger.dart';

List<String> detectPieces(cv.Mat warped) {
  final List<String> positions = List<String>.filled(24, 'X');

  // 动态计算网格点
  final List<cv.Point2f> gridPoints = getDynamicGridPoints(warped);

  // 调试：在图像上绘制网格点
  if (EnvironmentConfig.devMode) {
    for (final cv.Point2f point in gridPoints) {
      cv.circle(
        warped,
        cv.Point(point.x.toInt(), point.y.toInt()),
        5,
        cv.Scalar(255), // 使用蓝色标记网格点 (B, G, R)
        thickness: -1,
      );
    }
  }

  // 存储所有点的 whiteCount 和 blackCount
  final List<int> whiteCounts = <int>[];
  final List<int> blackCounts = <int>[];

  // 提前定义一些常用 Mat 对象以减少重复创建
  final cv.Mat kernel = cv.getStructuringElement(cv.MORPH_ELLIPSE, (3, 3));

  // 第一次遍历：计算所有点的 whiteCount 和 blackCount
  for (int i = 0; i < gridPoints.length; i++) {
    final cv.Point2f point = gridPoints[i];

    // 提取感兴趣区域 (ROI)
    final cv.Mat roi = cv.getRectSubPix(warped, (100, 100), point);

    // 检查 ROI 是否为空
    if (roi.isEmpty) {
      logger.w('警告: ROI 提取失败，点索引 $i 可能位于图像边缘。');
      whiteCounts.add(0);
      blackCounts.add(0);
      roi.dispose();
      continue;
    }

    // 转换为 HSV 颜色空间
    final cv.Mat hsv = cv.cvtColor(roi, cv.COLOR_BGR2HSV);

    // 应用形态学操作以减少噪声
    final cv.Mat opened = cv.morphologyEx(hsv, cv.MORPH_OPEN, kernel);
    final cv.Mat closed = cv.morphologyEx(opened, cv.MORPH_CLOSE, kernel);

    // 定义白色的阈值
    final cv.Mat lowerWhite = cv.Mat.zeros(hsv.rows, hsv.cols, hsv.type);
    lowerWhite.setTo(cv.Scalar(0, 0, 200));

    final cv.Mat upperWhite = cv.Mat.zeros(hsv.rows, hsv.cols, hsv.type);
    upperWhite.setTo(cv.Scalar(180, 50, 255));

    final cv.Mat whiteMask = cv.inRange(closed, lowerWhite, upperWhite);

    // 定义黑色的阈值，排除白色区域
    final cv.Mat lowerBlack = cv.Mat.zeros(hsv.rows, hsv.cols, hsv.type);
    lowerBlack.setTo(cv.Scalar()); // 确保所有 HSV 通道都设置

    final cv.Mat upperBlack = cv.Mat.zeros(hsv.rows, hsv.cols, hsv.type);
    upperBlack.setTo(cv.Scalar(180, 255, 50));

    final cv.Mat blackMask = cv.inRange(closed, lowerBlack, upperBlack);

    // 排除白色区域
    final cv.Mat invertedWhiteMask = cv.bitwiseNOT(whiteMask);
    final cv.Mat maskedBlack = cv.bitwiseAND(blackMask, invertedWhiteMask);
    //blackMask = maskedBlack;

    // 计算非零像素数量
    final int whiteCount = cv.countNonZero(whiteMask);
    final int blackCount = cv.countNonZero(maskedBlack);

    whiteCounts.add(whiteCount);
    blackCounts.add(blackCount);

    // 释放中间变量
    roi.dispose();
    hsv.dispose();
    opened.dispose();
    closed.dispose();
    whiteMask.dispose();
    blackMask.dispose();
    lowerWhite.dispose();
    upperWhite.dispose();
    lowerBlack.dispose();
    upperBlack.dispose();
    invertedWhiteMask.dispose();
    maskedBlack.dispose();
  }

  // 将 whiteCount 和 blackCount 组合成特征向量
  final List<List<double>> features = <List<double>>[];
  for (int i = 0; i < whiteCounts.length; i++) {
    features
        .add(<double>[whiteCounts[i].toDouble(), blackCounts[i].toDouble()]);
  }

  // 标准化特征数据
  final List<double> whiteCountsNorm = normalizeList(whiteCounts);
  final List<double> blackCountsNorm = normalizeList(blackCounts);
  final List<List<double>> normalizedFeatures = <List<double>>[];
  for (int i = 0; i < whiteCountsNorm.length; i++) {
    normalizedFeatures.add(<double>[whiteCountsNorm[i], blackCountsNorm[i]]);
  }

  // 应用 K-Means 聚类，将点分为三类
  const int K = 3; // 聚类数量（白棋、黑棋、空位）
  const int attempts = 10;
  final (List<int> labels, List<List<double>> centers) = kmeans(
    normalizedFeatures,
    K,
    attempts,
  );

  // 映射聚类结果到棋子状态
  // 首先确定每个聚类中心对应的棋子状态
  final Map<int, String> clusterToPiece = <int, String>{};
  final List<String> pieceTypes = <String>['W', 'B', 'X'];

  // 计算每个聚类中心的特征值之和，以确定其对应的棋子状态
  final List<double> centerSums =
      centers.map((List<double> c) => c[0] + c[1]).toList();
  final List<int> sortedIndices = argsort(centerSums);

  // 将聚类中心按照特征值之和从大到小排序，依次对应白棋、黑棋、空位
  for (int i = 0; i < sortedIndices.length; i++) {
    clusterToPiece[sortedIndices[i]] = pieceTypes[i];
  }

  // 根据聚类结果设置 positions
  for (int i = 0; i < labels.length; i++) {
    final int label = labels[i];
    positions[i] = clusterToPiece[label]!;

    // 添加调试信息
    if (EnvironmentConfig.devMode) {
      positions[i] += ' ${whiteCounts[i]}/${blackCounts[i]}';
    }
  }

  // 释放 kernel
  kernel.dispose();

  return positions;
}

void annotatePieces(cv.Mat image, List<String> positions) {
  final List<cv.Point2f> gridPoints = getDynamicGridPoints(image);

  for (int i = 0; i < positions.length; i++) {
    final cv.Point2f point = gridPoints[i];
    final String label = positions[i];

    // 设置文本位置，调整偏移量使其在蓝点正上方
    final cv.Point textOrg = cv.Point(
      point.x.toInt() - 10, // 适当调整x偏移量
      point.y.toInt() + 5, // 适当调整y偏移量
    );

    // 先用黑色绘制较粗的文字作为轮廓
    cv.putText(
      image,
      label,
      textOrg,
      cv.FONT_HERSHEY_SIMPLEX,
      3,
      cv.Scalar(), // 黑色 (B, G, R)
      thickness: 3, // 较大的厚度
      lineType: cv.LINE_AA,
    );

    // 再用黄色绘制较细的文字填充
    cv.putText(
      image,
      label,
      textOrg,
      cv.FONT_HERSHEY_SIMPLEX,
      3,
      cv.Scalar(0, 255, 255), // 黄色 (B, G, R)
      thickness: 2, // 较小的厚度
      lineType: cv.LINE_AA,
    );
  }
}

// 简单的 K-Means 聚类实现
// 返回值：(labels, centers)
(List<int>, List<List<double>>) kmeans(
  List<List<double>> data,
  int K,
  int attempts,
) {
  const int maxIterations = 100;
  const double epsilon = 1e-4;

  List<List<double>> bestCenters = <List<double>>[];
  List<int> bestLabels = <int>[];
  double bestCompactness = double.maxFinite;

  for (int attempt = 0; attempt < attempts; attempt++) {
    // 随机初始化聚类中心
    final List<List<double>> centers = <List<double>>[];
    final List<int> initialIndices = getRandomIndices(data.length, K);
    for (final int idx in initialIndices) {
      centers.add(List.from(data[idx]));
    }

    final List<int> labels = List.filled(data.length, -1);
    double compactness = 0.0;

    for (int iter = 0; iter < maxIterations; iter++) {
      bool centersChanged = false;

      // 1. 分配每个点到最近的聚类中心
      for (int i = 0; i < data.length; i++) {
        double minDist = double.maxFinite;
        int minLabel = -1;
        for (int j = 0; j < K; j++) {
          final double dist = euclideanDistance(data[i], centers[j]);
          if (dist < minDist) {
            minDist = dist;
            minLabel = j;
          }
        }
        if (labels[i] != minLabel) {
          labels[i] = minLabel;
          centersChanged = true;
        }
      }

      // 2. 更新聚类中心
      final List<List<double>> newCenters =
          List.generate(K, (_) => <double>[0.0, 0.0]);
      final List<int> counts = List.filled(K, 0);

      for (int i = 0; i < data.length; i++) {
        final int label = labels[i];
        newCenters[label][0] += data[i][0];
        newCenters[label][1] += data[i][1];
        counts[label] += 1;
      }

      for (int j = 0; j < K; j++) {
        if (counts[j] != 0) {
          newCenters[j][0] /= counts[j];
          newCenters[j][1] /= counts[j];
        } else {
          // 如果某个聚类没有分配到任何点，重新随机初始化
          final int idx = getRandomIndices(data.length, 1)[0];
          newCenters[j] = List.from(data[idx]);
        }
      }

      // 计算中心移动距离
      double centerShift = 0.0;
      for (int j = 0; j < K; j++) {
        centerShift += euclideanDistance(centers[j], newCenters[j]);
      }

      // 更新中心
      centers.setAll(0, newCenters);

      if (!centersChanged || centerShift <= epsilon) {
        break;
      }
    }

    // 计算紧密度（Compactness）
    compactness = 0.0;
    for (int i = 0; i < data.length; i++) {
      final int label = labels[i];
      compactness += euclideanDistance(data[i], centers[label]);
    }

    // 更新最佳结果
    if (compactness < bestCompactness) {
      bestCompactness = compactness;
      bestCenters = List.from(centers);
      bestLabels = List.from(labels);
    }
  }

  return (bestLabels, bestCenters);
}

// 计算欧氏距离
double euclideanDistance(List<double> a, List<double> b) {
  double sum = 0.0;
  for (int i = 0; i < a.length; i++) {
    final double diff = a[i] - b[i];
    sum += diff * diff;
  }
  return math.sqrt(sum); // 使用 Math.sqrt 得到实际距离
}

// 标准化列表
List<double> normalizeList(List<int> data) {
  final int maxVal = data.reduce((int a, int b) => a > b ? a : b);
  if (maxVal == 0) {
    return List.filled(data.length, 0.0);
  }
  return data.map((int val) => val / maxVal).toList();
}

// 获取随机索引列表
List<int> getRandomIndices(int range, int count) {
  final List<int> indices = List.generate(range, (int index) => index);
  indices.shuffle();
  return indices.sublist(0, count);
}

// 对列表进行排序并返回排序后的索引列表
List<int> argsort(List<double> list) {
  final List<int> indices = List.generate(list.length, (int index) => index);
  indices.sort((int a, int b) => list[b].compareTo(list[a])); // 从大到小排序
  return indices;
}

List<cv.Point2f> getDynamicGridPoints(cv.Mat warped) {
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
    cv.Point2f(outerRightXRatio * width, outerCenterYRatio * height), // 4: 右中点
    cv.Point2f(outerLeftXRatio * width, outerBottomYRatio * height), // 5: 左下角
    cv.Point2f(outerCenterXRatio * width, outerBottomYRatio * height), // 6: 下中点
    cv.Point2f(outerRightXRatio * width, outerBottomYRatio * height), // 7: 右下角

    // 中层方框角和中点
    cv.Point2f(middleLeftXRatio * width, middleTopYRatio * height), // 8: 左上角
    cv.Point2f(middleCenterXRatio * width, middleTopYRatio * height), // 9: 上中点
    cv.Point2f(middleRightXRatio * width, middleTopYRatio * height), // 10: 右上角
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
    cv.Point2f(innerLeftXRatio * width, innerCenterYRatio * height), // 19: 左中点
    cv.Point2f(innerRightXRatio * width, innerCenterYRatio * height), // 20: 右中点
    cv.Point2f(innerLeftXRatio * width, innerBottomYRatio * height), // 21: 左下角
    cv.Point2f(
        innerCenterXRatio * width, innerBottomYRatio * height), // 22: 下中点
    cv.Point2f(innerRightXRatio * width, innerBottomYRatio * height), // 23: 右下角
  ];

  return points;
}
