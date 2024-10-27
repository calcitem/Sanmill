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
      // Calculate Euclidean distance between two points
      final double startPointDistance = math.sqrt(
        math.pow(line.startPoint.x - filteredLine.startPoint.x, 2) +
            math.pow(line.startPoint.y - filteredLine.startPoint.y, 2),
      );

      final double endPointDistance = math.sqrt(
        math.pow(line.endPoint.x - filteredLine.endPoint.x, 2) +
            math.pow(line.endPoint.y - filteredLine.endPoint.y, 2),
      );

      // Check if within distance threshold
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
  // Get the ordered four vertices
  final List<cv.Point> orderedPoints = orderPoints(contour);

  final cv.VecPoint srcPoints = cv.VecPoint.fromList(orderedPoints);

  // Calculate width and height
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

// Edge detection and Hough line transform function
(cv.Mat warpedWithLines, List<Line> filteredLines)
    applyEdgeDetectionAndHoughLines(cv.Mat warped) {
  // Convert to grayscale image
  final cv.Mat warpedGray = cv.cvtColor(warped, cv.COLOR_BGR2GRAY);

  // Apply Gaussian blur
  final cv.Mat blurred = cv.gaussianBlur(warpedGray, (11, 11), 0);

  // Apply edge detection (Canny)
  // `threshold2` (high threshold) detects strong edges, then links to weak edges (based on `threshold1`).
  // This hysteresis thresholding avoids false edges in noise or blurred areas.
  // Increase `threshold2` to reduce noise; decrease for more edges.
  final cv.Mat edges = cv.canny(blurred, 1, 1); // 10, 80?

  // Apply Hough Line Transform with adjustable parameters
  final cv.Mat lines = cv.HoughLinesP(
    edges,
    1,
    math.pi / 180,
    ImageProcessingConfig
        .houghTransformConfig.threshold, // Adjustable Hough threshold
    minLineLength: ImageProcessingConfig
        .houghTransformConfig.minLineLength, // Adjustable min line length
    maxLineGap: ImageProcessingConfig
        .houghTransformConfig.maxLineGap, // Adjustable max line gap
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

  // Release memory
  warpedGray.dispose();
  blurred.dispose();
  edges.dispose();
  lines.dispose();

  return (warpedWithLines, filteredLines);
}

// Compute board edges
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

  // Use appropriate constructor and pass double values
  return cv.Rect(
    minX,
    minY,
    maxX - minX,
    maxY - minY,
  );
}

// Determine board size
String determineBoardSize(List<Line> lines) {
  // Assume Mill board has fixed number of horizontal and vertical lines
  // Detect the number of lines actually detected

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

  // According to Mill standard, there are usually 8 horizontal and 8 vertical lines
  if (horizontal >= 8 && vertical >= 8) {
    return 'Mill board';
  } else {
    return 'Mill board not recognized, detected $horizontal horizontal lines and $vertical vertical lines';
  }
}
