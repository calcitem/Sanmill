import 'package:opencv_dart/opencv_dart.dart' as cv;

import '../shared/services/environment_config.dart';
import 'image_processing_config.dart';

List<String> detectPieces(
  cv.Mat warped,
) {
  final List<String> positions = List<String>.filled(24, 'e');

  // 动态计算网格点
  final List<cv.Point2f> gridPoints = getDynamicGridPoints(warped);

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

  for (int i = 0; i < gridPoints.length; i++) {
    final cv.Point2f point = gridPoints[i];

    // 提取感兴趣区域 (ROI)
    final cv.Mat roi = cv.getRectSubPix(
      warped,
      (100, 100),
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
    final int whiteThreshold = (totalPixels *
            ImageProcessingConfig.pieceDetectionConfig.whiteThresholdRatio)
        .toInt();
    final int blackThreshold = (totalPixels *
            ImageProcessingConfig.pieceDetectionConfig.blackThresholdRatio)
        .toInt();

    // 根据相对阈值确定棋子颜色
    if (whiteCount > whiteThreshold) {
      positions[i] = 'w';
    } else if (blackCount > blackThreshold) {
      positions[i] = 'b';
    } else {
      positions[i] = 'e';
    }
    positions[i] += ' $whiteCount/$blackCount';
    if (EnvironmentConfig.devMode) {
      positions[i] += ' $whiteCount/$blackCount';
      //positions[i] += '\n($whiteCount/$whiteThreshold, \n$blackCount/$blackThreshold)';
    }

    // 释放内存
    roi.dispose();
    hsv.dispose();
    whiteMask.dispose();
    blackMask.dispose();
  }

  return positions;
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
