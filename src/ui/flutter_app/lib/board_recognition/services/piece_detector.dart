import 'package:opencv_dart/opencv.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;

import '../../shared/services/environment_config.dart';
import '../../shared/services/logger.dart';

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

  final List<double> whiteCounts = <double>[];
  final List<double> blackCounts = <double>[];
  final List<double> meanVs = <double>[];

  for (int i = 0; i < gridPoints.length; i++) {
    final cv.Point2f point = gridPoints[i];
    final cv.Mat roi = cv.getRectSubPix(warped, (100, 100), point);

    if (roi.isEmpty) {
      logger.w('Warning: ROI extraction failed at index $i.');
      whiteCounts.add(0.0);
      blackCounts.add(0.0);
      meanVs.add(0.0);
      roi.dispose();
      continue;
    }

    // Convert ROI to HSV
    final cv.Mat hsv = cv.cvtColor(roi, cv.COLOR_BGR2HSV);

    // Define thresholds for white and black in HSV space
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

    // Count non-zero pixels
    final int whiteCount = cv.countNonZero(whiteMask);
    final int blackCount = cv.countNonZero(blackMask);

    // Split HSV channels and compute mean of V channel
    final VecMat hsvChannels = cv.split(hsv);

    final cv.Scalar meanV = hsvChannels[2].mean();

    whiteCounts.add(whiteCount.toDouble());
    blackCounts.add(blackCount.toDouble());
    meanVs.add(meanV.val1); // Access the first element for the V channel mean

    // Dispose resources

    blackMask.dispose();
    whiteMask.dispose();

    roi.dispose();
    hsv.dispose();
  }

  // Combine features
  final List<List<double>> features = <List<double>>[];
  for (int i = 0; i < whiteCounts.length; i++) {
    features.add(<double>[
      whiteCounts[i],
      blackCounts[i],
      meanVs[i],
    ]);
  }

  // Normalize features
  final List<List<double>> normalizedFeatures = normalizeFeatures(features);

  // Prepare data for K-Means
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

  // Prepare bestLabels
  final cv.Mat bestLabels = cv.Mat.zeros(
    dataMat.rows,
    1,
    const cv.MatType(cv.MatType.CV_32S),
  );

  // Define termination criteria
  const (int, int, double) criteria =
      (cv.TERM_EPS + cv.TERM_MAX_ITER, 100, 1e-4);

  // Apply K-Means clustering
  final (double compactness, cv.Mat resultLabels, cv.Mat resultCenters) =
      cv.kmeans(
    dataMat,
    3,
    bestLabels,
    criteria,
    10,
    cv.KMEANS_PP_CENTERS,
  );

  // Convert resultLabels and resultCenters to Dart lists
  final List<int> labels = matToIntList(resultLabels);
  final List<List<double>> centersList = matToList(resultCenters);

  // Map clusters to piece types
  final List<double> centerSums = centersList
      .map((List<double> c) => c.reduce((double a, double b) => a + b))
      .toList();
  final List<int> sortedIndices = argsort(centerSums);

  final List<String> pieceTypes = <String>['X', 'B', 'W'];
  final Map<int, String> clusterToPiece = <int, String>{};
  for (int i = 0; i < sortedIndices.length; i++) {
    clusterToPiece[sortedIndices[i]] = pieceTypes[i];
  }

  // Assign positions based on clustering
  for (int i = 0; i < labels.length; i++) {
    final int label = labels[i];
    positions[i] = clusterToPiece[label]!;

    // Add debug information
    if (EnvironmentConfig.devMode) {
      positions[i] += ' ${whiteCounts[i].toInt()}/${blackCounts[i].toInt()}';
    }
  }

  // Dispose resources
  bestLabels.dispose();
  dataMat.dispose();

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

    // Set text position, adjust offset to place it right above the blue point
    final cv.Point textOrg = cv.Point(
      (point.x - 10).toInt(), // Adjust x offset
      (point.y + 5).toInt(), // Adjust y offset
    );

    // Draw thicker text outline in black as a border
    cv.putText(
      image,
      label,
      textOrg,
      cv.FONT_HERSHEY_SIMPLEX,
      1.0, // Adjust font size
      cv.Scalar(), // Black (B, G, R)
      thickness: 3, // Thicker border
      lineType: cv.LINE_AA,
    );

    // Draw thinner yellow text as fill
    cv.putText(
      image,
      label,
      textOrg,
      cv.FONT_HERSHEY_SIMPLEX,
      1.0, // Adjust font size
      cv.Scalar(0, 255, 255), // Yellow (B, G, R)
      lineType: cv.LINE_AA,
    );
  }
}

// Normalize feature data
List<List<double>> normalizeFeatures(List<List<double>> features) {
  // Calculate min and max for each feature
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

  // Normalize to [0, 1]
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

  // Based on original 500x500 image proportions
  // Outer box proportions
  const double outerLeftXRatio = 35.0 / 500.0;
  const double outerCenterXRatio = 250.0 / 500.0;
  const double outerRightXRatio = 465.0 / 500.0;

  const double outerTopYRatio = 40.0 / 500.0;
  const double outerCenterYRatio = 250.0 / 500.0;
  const double outerBottomYRatio = 465.0 / 500.0;

  // Middle box proportions
  const double middleLeftXRatio = 105.0 / 500.0;
  const double middleCenterXRatio = 250.0 / 500.0;
  const double middleRightXRatio = 395.0 / 500.0;

  const double middleTopYRatio = 110.0 / 500.0;
  const double middleCenterYRatio = 250.0 / 500.0;
  const double middleBottomYRatio = 395.0 / 500.0;

  // Inner box proportions
  const double innerLeftXRatio = 175.0 / 500.0;
  const double innerCenterXRatio = 250.0 / 500.0;
  const double innerRightXRatio = 325.0 / 500.0;

  const double innerTopYRatio = 180.0 / 500.0;
  const double innerCenterYRatio = 250.0 / 500.0;
  const double innerBottomYRatio = 325.0 / 500.0;

  final List<cv.Point2f> points = <cv.Point2f>[
    // Outer box corners and center points
    cv.Point2f(
        outerLeftXRatio * width, outerTopYRatio * height), // 0: Top left corner
    cv.Point2f(
        outerCenterXRatio * width, outerTopYRatio * height), // 1: Top center
    cv.Point2f(outerRightXRatio * width,
        outerTopYRatio * height), // 2: Top right corner
    cv.Point2f(
        outerLeftXRatio * width, outerCenterYRatio * height), // 3: Left center
    cv.Point2f(outerRightXRatio * width,
        outerCenterYRatio * height), // 4: Right center
    cv.Point2f(outerLeftXRatio * width,
        outerBottomYRatio * height), // 5: Bottom left corner
    cv.Point2f(outerCenterXRatio * width,
        outerBottomYRatio * height), // 6: Bottom center
    cv.Point2f(outerRightXRatio * width,
        outerBottomYRatio * height), // 7: Bottom right corner

    // Middle box corners and center points
    cv.Point2f(middleLeftXRatio * width,
        middleTopYRatio * height), // 8: Top left corner
    cv.Point2f(
        middleCenterXRatio * width, middleTopYRatio * height), // 9: Top center
    cv.Point2f(middleRightXRatio * width,
        middleTopYRatio * height), // 10: Top right corner
    cv.Point2f(middleLeftXRatio * width,
        middleCenterYRatio * height), // 11: Left center
    cv.Point2f(middleRightXRatio * width,
        middleCenterYRatio * height), // 12: Right center
    cv.Point2f(middleLeftXRatio * width,
        middleBottomYRatio * height), // 13: Bottom left corner
    cv.Point2f(middleCenterXRatio * width,
        middleBottomYRatio * height), // 14: Bottom center
    cv.Point2f(middleRightXRatio * width,
        middleBottomYRatio * height), // 15: Bottom right corner

    // Inner box corners and center points
    cv.Point2f(innerLeftXRatio * width,
        innerTopYRatio * height), // 16: Top left corner
    cv.Point2f(
        innerCenterXRatio * width, innerTopYRatio * height), // 17: Top center
    cv.Point2f(innerRightXRatio * width,
        innerTopYRatio * height), // 18: Top right corner
    cv.Point2f(
        innerLeftXRatio * width, innerCenterYRatio * height), // 19: Left center
    cv.Point2f(innerRightXRatio * width,
        innerCenterYRatio * height), // 20: Right center
    cv.Point2f(innerLeftXRatio * width,
        innerBottomYRatio * height), // 21: Bottom left corner
    cv.Point2f(innerCenterXRatio * width,
        innerBottomYRatio * height), // 22: Bottom center
    cv.Point2f(innerRightXRatio * width,
        innerBottomYRatio * height), // 23: Bottom right corner
  ];

  return points;
}
