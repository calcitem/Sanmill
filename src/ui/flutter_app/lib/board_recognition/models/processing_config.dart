// image_processing_config.dart

import 'dart:math' as math;

/// Main configuration class, containing all settings related to image processing.
class ProcessingConfig {
  ProcessingConfig._(); // Private constructor to prevent instantiation

  // Static instances of various configurations
  static GammaConfig gammaConfig = GammaConfig(gamma: 1.2);
  static AdaptiveThresholdConfig adaptiveThresholdConfig =
      AdaptiveThresholdConfig(blockSize: 15, c: 3.0);
  static ContourConfig contourConfig = ContourConfig(
    areaThreshold: 10000.0,
    epsilonMultiplier: 0.04,
    aspectRatioMin: 0.8,
    aspectRatioMax: 1.2,
  );
  static HoughTransformConfig houghTransformConfig = HoughTransformConfig(
    threshold: 10,
    minLineLength: 75.0,
    maxLineGap: 1.0,
    angleTolerance: 0.1,
    distanceThreshold: 10,
  );
  static ImageProcessingParameters parameters = ImageProcessingParameters(
    gaussianKernelSize: (5, 5),
    morphologyKernelSize: (5, 5),
    drawContoursColor: (0, 255, 0), // Green
    drawContoursThickness: 2,
  );
  static UIConfig uiConfig = UIConfig._();

  // Mapping configKey to getter functions
  static final Map<String, double Function()> _getters =
      <String, double Function()>{
    'gamma': () => gammaConfig.gamma,
    'blockSize': () => adaptiveThresholdConfig.blockSize.toDouble(),
    'c': () => adaptiveThresholdConfig.c,
    'areaThreshold': () => contourConfig.areaThreshold,
    'epsilonMultiplier': () => contourConfig.epsilonMultiplier,
    'aspectRatioMin': () => contourConfig.aspectRatioMin,
    'aspectRatioMax': () => contourConfig.aspectRatioMax,
    'threshold': () => houghTransformConfig.threshold.toDouble(),
    'minLineLength': () => houghTransformConfig.minLineLength,
    'maxLineGap': () => houghTransformConfig.maxLineGap,
    'angleTolerance': () => houghTransformConfig.angleTolerance,
    'distanceThreshold': () =>
        houghTransformConfig.distanceThreshold.toDouble(),
  };

  // Mapping configKey to setter functions
  static final Map<String, void Function(double)> _setters =
      <String, void Function(double)>{
    'gamma': (double value) => gammaConfig.gamma = value,
    'blockSize': (double value) => adaptiveThresholdConfig.blockSize =
        value.toInt() | 1, // Ensure odd number
    'c': (double value) => adaptiveThresholdConfig.c = value,
    'areaThreshold': (double value) => contourConfig.areaThreshold = value,
    'epsilonMultiplier': (double value) =>
        contourConfig.epsilonMultiplier = value,
    'aspectRatioMin': (double value) => contourConfig.aspectRatioMin = value,
    'aspectRatioMax': (double value) => contourConfig.aspectRatioMax = value,
    'threshold': (double value) =>
        houghTransformConfig.threshold = value.toInt(),
    'minLineLength': (double value) =>
        houghTransformConfig.minLineLength = value,
    'maxLineGap': (double value) => houghTransformConfig.maxLineGap = value,
    'angleTolerance': (double value) =>
        houghTransformConfig.angleTolerance = value,
    'distanceThreshold': (double value) =>
        houghTransformConfig.distanceThreshold = value.toInt(),
  };

  /// Get the current slider value based on configKey
  static double getSliderValue(String configKey) {
    return _getters[configKey]?.call() ?? 0.0;
  }

  /// Update the corresponding configuration parameter based on configKey
  static void updateConfig(String configKey, double value) {
    final void Function(double)? setter = _setters[configKey];
    if (setter != null) {
      setter(value);
    }
  }
}

// Various configuration classes
class GammaConfig {
  GammaConfig({required this.gamma});
  double gamma;
}

class AdaptiveThresholdConfig {
  AdaptiveThresholdConfig({required this.blockSize, required this.c});
  int blockSize;
  double c;
}

class ContourConfig {
  ContourConfig({
    required this.areaThreshold,
    required this.epsilonMultiplier,
    required this.aspectRatioMin,
    required this.aspectRatioMax,
  });

  double areaThreshold;
  double epsilonMultiplier;
  double aspectRatioMin;
  double aspectRatioMax;
}

class HoughTransformConfig {
  HoughTransformConfig({
    required this.threshold,
    required this.minLineLength,
    required this.maxLineGap,
    required this.angleTolerance,
    required this.distanceThreshold,
  });

  int threshold;
  double minLineLength;
  double maxLineGap;
  double angleTolerance;
  int distanceThreshold;
}

class PieceDetectionConfig {
  PieceDetectionConfig({
    required this.whiteThresholdRatio,
    required this.blackThresholdRatio,
  });

  double whiteThresholdRatio;
  double blackThresholdRatio;
}

class ImageProcessingParameters {
  ImageProcessingParameters({
    required this.gaussianKernelSize,
    required this.morphologyKernelSize,
    required this.drawContoursColor,
    required this.drawContoursThickness,
  });

  final (int, int) gaussianKernelSize;
  final (int, int) morphologyKernelSize;
  final (int, int, int) drawContoursColor; // RGB
  final int drawContoursThickness;
}

// UI-related configuration class
class UIConfig {
  UIConfig._(); // Private constructor to prevent instantiation

  // App title
  final String appBarTitle = "Mill Board Recognition";

  // Button text
  final String selectAndProcessImageButton = "Select and Process Image";

  // FEN string label
  final String fenStringLabel = "FEN String:";

  // Debug image labels
  final Map<String, String> debugImageLabels = <String, String>{
    'grayImage': 'Grayscale Image',
    'enhancedImage': 'Enhanced Image',
    'threshImage': 'Threshold Image',
    'warpedImage': 'Warped Image',
    'matWithContour': 'Image with Contours',
    'warpedWithLines': 'Image after Edge Detection and Hough Line Transform',
    'warpedWithAnnotations': 'Image with Annotations',
  };

  // Slider configuration
  final List<SliderConfig> sliders = <SliderConfig>[
    SliderConfig(
      labelPrefix: 'Gamma Value: ',
      configKey: 'gamma',
      min: 0.5,
      max: 3.0,
      divisions: 25,
      labelFormatter: (double value) => value.toStringAsFixed(2),
      description:
          'Adjust the brightness and contrast of the image. Higher values make the image brighter.',
    ),
    SliderConfig(
      labelPrefix: 'Adaptive Threshold Block Size: ',
      configKey: 'blockSize',
      min: 3.0,
      max: 31.0,
      divisions: 14,
      labelFormatter: (double value) => value.toInt().toString(),
      description:
          'Defines the local region size for thresholding. Larger values help adapt to uneven lighting.',
    ),
    SliderConfig(
      labelPrefix: 'Adaptive Threshold Constant C: ',
      configKey: 'c',
      min: -10.0,
      max: 10.0,
      divisions: 20,
      labelFormatter: (double value) => value.toString(),
      description:
          'Constant subtracted from the block mean. Positive values reduce threshold, negative values do the opposite.',
    ),
    SliderConfig(
      labelPrefix: 'Contour Area Threshold: ',
      configKey: 'areaThreshold',
      min: 1000.0,
      max: 50000.0,
      divisions: 49,
      labelFormatter: (double value) => value.toInt().toString(),
      description:
          'Minimum area for contours. Higher values ignore smaller contours.',
    ),
    SliderConfig(
      labelPrefix: 'Polygon Approximation Precision Multiplier: ',
      configKey: 'epsilonMultiplier',
      min: 0.01,
      max: 0.1,
      divisions: 9,
      labelFormatter: (double value) => value.toStringAsFixed(2),
      description:
          'Defines approximation accuracy; larger values mean coarser approximations.',
    ),
    SliderConfig(
      labelPrefix: 'Aspect Ratio Minimum: ',
      configKey: 'aspectRatioMin',
      min: 0.5,
      max: 1.5,
      divisions: 20,
      labelFormatter: (double value) => value.toStringAsFixed(2),
      description:
          'Minimum aspect ratio for filtering contours, ensuring they approximate a square.',
    ),
    SliderConfig(
      labelPrefix: 'Aspect Ratio Maximum: ',
      configKey: 'aspectRatioMax',
      min: 0.5,
      max: 1.5,
      divisions: 20,
      labelFormatter: (double value) => value.toStringAsFixed(2),
      description:
          'Maximum aspect ratio for filtering contours, ensuring they approximate a square.',
    ),
    SliderConfig(
      labelPrefix: 'Hough Transform Threshold: ',
      configKey: 'threshold',
      min: 0.0,
      max: 200.0,
      divisions: 200,
      labelFormatter: (double value) => value.toInt().toString(),
      description:
          'Minimum number of votes required for line detection. Higher values detect more distinct lines.',
    ),
    SliderConfig(
      labelPrefix: 'Minimum Line Length: ',
      configKey: 'minLineLength',
      min: 0.0,
      max: 300.0,
      divisions: 300,
      labelFormatter: (double value) => value.toString(),
      description:
          'Minimum line length for Hough line transform. Longer lines are prioritized for detection.',
    ),
    SliderConfig(
      labelPrefix: 'Line Gap Threshold: ',
      configKey: 'maxLineGap',
      min: 0.0,
      max: 50.0,
      divisions: 50,
      labelFormatter: (double value) => value.toString(),
      description:
          'Maximum allowed gap between segments to merge them in Hough line transform.',
    ),
    SliderConfig(
      labelPrefix: 'Angle Tolerance: ',
      configKey: 'angleTolerance',
      min: 0.0,
      max: math.pi / 4, // 0 to 45 degrees
      divisions: 45,
      labelFormatter: (double value) => value.toStringAsFixed(2),
      description:
          'Angle tolerance (radians) when filtering lines, used to distinguish horizontal and vertical lines.',
    ),
    SliderConfig(
      labelPrefix: 'Distance Threshold: ',
      configKey: 'distanceThreshold',
      min: 5.0,
      max: 50.0,
      divisions: 45,
      labelFormatter: (double value) => value.toInt().toString(),
      description:
          'Distance threshold for filtering lines, used to remove near-duplicate segments.',
    ),
  ];
}

/// Slider configuration class
class SliderConfig {
  SliderConfig({
    required this.labelPrefix,
    required this.configKey,
    required this.min,
    required this.max,
    required this.divisions,
    required this.labelFormatter,
    required this.description,
  });

  final String labelPrefix;
  final String configKey; // Identifies the corresponding configuration item
  final double min;
  final double max;
  final int divisions;
  final String Function(double) labelFormatter;
  final String description;
}
