import 'package:opencv_dart/opencv_dart.dart' as cv;

import '../shared/services/environment_config.dart';
import '../shared/services/logger.dart';

List<String> detectPieces(cv.Mat warped) {
  final List<String> positions = List<String>.filled(24, 'X');

  final List<cv.Point2f> gridPoints = getDynamicGridPoints(warped);

  if (EnvironmentConfig.devMode) {
    for (final cv.Point2f point in gridPoints) {
      cv.circle(
        warped,
        cv.Point(point.x.toInt(), point.y.toInt()),
        5,
        cv.Scalar(255),
        thickness: -1,
      );
    }
  }

  final List<int> whiteCounts = <int>[];
  final List<int> blackCounts = <int>[];
  final List<double> whiteMeans = <double>[];
  final List<double> blackMeans = <double>[];

  final cv.Mat kernel = cv.getStructuringElement(cv.MORPH_ELLIPSE, (3, 3));

  for (int i = 0; i < gridPoints.length; i++) {
    final cv.Point2f point = gridPoints[i];

    final cv.Mat roi = cv.getRectSubPix(warped, (100, 100), point);

    if (roi.isEmpty) {
      logger.w('警告: ROI 提取失败，点索引 $i 可能位于图像边缘。');
      whiteCounts.add(0);
      blackCounts.add(0);
      whiteMeans.add(0.0);
      blackMeans.add(0.0);
      roi.dispose();
      continue;
    }

    // 使用自适应阈值进行分割
    final cv.Mat gray = cv.cvtColor(roi, cv.COLOR_BGR2GRAY);

    // 应用 Otsu 阈值
    final (double otsuThreshold, cv.Mat _) = cv.threshold(
      gray,
      0,
      255,
      cv.THRESH_BINARY + cv.THRESH_OTSU,
    );

    // 应用二进制阈值
    final (double _, cv.Mat binary) = cv.threshold(
      gray,
      otsuThreshold,
      255,
      cv.THRESH_BINARY,
    );

    final int whiteCount = cv.countNonZero(binary);
    final int blackCount = roi.cols * roi.rows - whiteCount;

    // 计算平均亮度
    final (cv.Scalar meanWhite, cv.Scalar stddevWhite) =
        cv.meanStdDev(roi, mask: binary);
    final double whiteMean = meanWhite.val2; // 假设使用第三通道（R通道）

    final (cv.Scalar meanBlack, cv.Scalar stddevBlack) =
        cv.meanStdDev(roi, mask: cv.bitwiseNOT(binary));
    final double blackMean = meanBlack.val2;

    whiteCounts.add(whiteCount);
    blackCounts.add(blackCount);
    whiteMeans.add(whiteMean);
    blackMeans.add(blackMean);

    // Dispose only cv.Mat objects
    gray.dispose();
    binary.dispose();
    roi.dispose();
    // No need to dispose cv.Scalar objects
  }

  // 组合特征向量
  final List<List<double>> features = <List<double>>[];
  for (int i = 0; i < whiteCounts.length; i++) {
    features.add(<double>[
      whiteCounts[i].toDouble(),
      blackCounts[i].toDouble(),
      whiteMeans[i],
      blackMeans[i],
    ]);
  }

  // 标准化特征数据
  final List<List<double>> normalizedFeatures = normalizeFeatures(features);

  // 将 normalizedFeatures 转换为 Mat
  final cv.Mat dataMat = cv.Mat.zeros(
    normalizedFeatures.length,
    normalizedFeatures[0].length,
    const cv.MatType(cv.MatType.CV_32F),
  );
  for (int i = 0; i < dataMat.rows; i++) {
    for (int j = 0; j < dataMat.cols; j++) {
      dataMat.set(i, j, normalizedFeatures[i][j]);
    }
  }

  // 准备 bestLabels
  final cv.Mat bestLabels = cv.Mat.zeros(
    dataMat.rows,
    1,
    const cv.MatType(cv.MatType.CV_32S),
  );

  // 定义终止条件
  const (int, int, double) criteria =
      (cv.TERM_EPS + cv.TERM_MAX_ITER, 100, 1e-4);

  // 应用 K-Means 聚类
  final (double compactness, cv.Mat resultLabels, cv.Mat resultCenters) =
      cv.kmeans(
    dataMat,
    3, // K
    bestLabels,
    criteria,
    10, // attempts
    cv.KMEANS_PP_CENTERS,
  );

  // 将 resultLabels 和 resultCenters 转换为 Dart 列表
  final List<int> labels = matToIntList(resultLabels);
  final List<List<double>> centersList = matToList(resultCenters);

  // 计算每个聚类中心的特征值之和，以确定其对应的棋子状态
  final List<double> centerSums = centersList
      .map((List<double> c) => c.reduce((double a, double b) => a + b))
      .toList();
  final List<int> sortedIndices = argsort(centerSums);

  // 将聚类中心按照特征值之和从大到小排序，依次对应白棋、黑棋、空位
  final List<String> pieceTypes = <String>['W', 'B', 'X'];
  final Map<int, String> clusterToPiece = <int, String>{};
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

  // 释放资源
  kernel.dispose();
  dataMat.dispose();
  bestLabels.dispose();
  resultLabels.dispose();
  resultCenters.dispose();

  return positions;
}

// Helper functions to extract data from cv.Mat
List<List<double>> matToList(cv.Mat mat) {
  final int rows = mat.rows;
  final int cols = mat.cols;
  final List<List<double>> result = <List<double>>[];

  for (int i = 0; i < rows; i++) {
    final List<double> row = <double>[];
    for (int j = 0; j < cols; j++) {
      // Since mat is of type CV_32F, we use at<double>
      final double value = mat.at<double>(i, j);
      row.add(value);
    }
    result.add(row);
  }

  return result;
}

List<int> matToIntList(cv.Mat mat) {
  final int rows = mat.rows;
  final List<int> result = <int>[];

  for (int i = 0; i < rows; i++) {
    // Since labels are of type CV_32S, we use at<int>
    final int value = mat.at<int>(i, 0);
    result.add(value);
  }

  return result;
}

// Implement argsort function
List<int> argsort(List<double> array) {
  final List<int> indices = List<int>.generate(array.length, (int i) => i);
  indices.sort((int a, int b) => array[a].compareTo(array[b]));
  return indices;
}

void annotatePieces(cv.Mat image, List<String> positions) {
  final List<cv.Point2f> gridPoints = getDynamicGridPoints(image);

  for (int i = 0; i < positions.length; i++) {
    final cv.Point2f point = gridPoints[i];
    final String label = positions[i];

    // 设置文本位置，调整偏移量使其在蓝点正上方
    final cv.Point textOrg = cv.Point(
      (point.x - 10).toInt(), // 适当调整x偏移量
      (point.y + 5).toInt(), // 适当调整y偏移量
    );

    // 先用黑色绘制较粗的文字作为轮廓
    cv.putText(
      image,
      label,
      textOrg,
      cv.FONT_HERSHEY_SIMPLEX,
      1.0, // 调整字体大小
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
      1.0, // 调整字体大小
      cv.Scalar(0, 255, 255), // 黄色 (B, G, R)
      lineType: cv.LINE_AA,
    );
  }
}

// 标准化特征数据
List<List<double>> normalizeFeatures(List<List<double>> features) {
  // 计算每个特征的最小值和最大值
  final int numFeatures = features[0].length;
  final List<double> minVals =
      List<double>.filled(numFeatures, double.infinity);
  final List<double> maxVals =
      List<double>.filled(numFeatures, -double.infinity);

  for (final List<double> feature in features) {
    for (int i = 0; i < numFeatures; i++) {
      if (feature[i] < minVals[i]) {
        minVals[i] = feature[i];
      }
      if (feature[i] > maxVals[i]) {
        maxVals[i] = feature[i];
      }
    }
  }

  // 标准化到 [0, 1]
  final List<List<double>> normalized = <List<double>>[];
  for (final List<double> feature in features) {
    final List<double> normFeature = <double>[];
    for (int i = 0; i < numFeatures; i++) {
      if (maxVals[i] - minVals[i] == 0) {
        normFeature.add(0.0);
      } else {
        normFeature.add((feature[i] - minVals[i]) / (maxVals[i] - minVals[i]));
      }
    }
    normalized.add(normFeature);
  }

  return normalized;
}

// Helper class to represent a tuple
class Tuple3<T1, T2, T3> {
  Tuple3(this.item1, this.item2, this.item3);
  final T1 item1;
  final T2 item2;
  final T3 item3;
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
