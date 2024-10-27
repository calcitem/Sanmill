// image_processing_config.dart

import 'dart:math' as math;

/// 主配置类，包含所有图像处理相关的配置。
class ImageProcessingConfig {
  ImageProcessingConfig._(); // 私有构造函数，防止实例化

  // 各种配置的静态实例
  static GammaConfig gammaConfig = GammaConfig(gamma: 1.5);
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
  static PieceDetectionConfig pieceDetectionConfig = PieceDetectionConfig(
    whiteThresholdRatio: 0.5,
    blackThresholdRatio: 0.5,
  );
  static ImageProcessingParameters parameters = ImageProcessingParameters(
    gaussianKernelSize: (5, 5),
    morphologyKernelSize: (5, 5),
    drawContoursColor: (0, 255, 0), // 绿色
    drawContoursThickness: 2,
  );
  static UIConfig uiConfig = UIConfig._();

  // 映射 configKey 到获取函数
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
    'whiteThresholdRatio': () => pieceDetectionConfig.whiteThresholdRatio,
    'blackThresholdRatio': () => pieceDetectionConfig.blackThresholdRatio,
  };

  // 映射 configKey 到设置函数
  static final Map<String, void Function(double)> _setters =
      <String, void Function(double)>{
    'gamma': (double value) => gammaConfig.gamma = value,
    'blockSize': (double value) =>
        adaptiveThresholdConfig.blockSize = value.toInt() | 1, // 确保为奇数
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
    'whiteThresholdRatio': (double value) =>
        pieceDetectionConfig.whiteThresholdRatio = value,
    'blackThresholdRatio': (double value) =>
        pieceDetectionConfig.blackThresholdRatio = value,
  };

  /// 根据configKey获取当前滑块的值
  static double getSliderValue(String configKey) {
    return _getters[configKey]?.call() ?? 0.0;
  }

  /// 根据configKey更新对应的配置参数
  static void updateConfig(String configKey, double value) {
    final void Function(double)? setter = _setters[configKey];
    if (setter != null) {
      setter(value);
    }
  }
}

// 各种配置类
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

// UI相关配置类
class UIConfig {
  UIConfig._(); // 私有构造函数，防止实例化

  // 应用标题
  final String appBarTitle = "Nine Men's Morris 识别";

  // 按钮文本
  final String selectAndProcessImageButton = "选择并处理图像";

  // FEN字符串标签
  final String fenStringLabel = "FEN 串：";

  // 调试图像标签
  final Map<String, String> debugImageLabels = <String, String>{
    'grayImage': '灰度图像',
    'enhancedImage': '增强图像',
    'threshImage': '阈值图像',
    'warpedImage': '透视变换后的图像',
    'matWithContour': '带轮廓的图像',
    'warpedWithLines': '边缘检测和霍夫线变换后的图像',
    'warpedWithAnnotations': '带注释的图像',
  };

  // Slider配置
  final List<SliderConfig> sliders = <SliderConfig>[
    SliderConfig(
      labelPrefix: '伽马值 (Gamma): ',
      configKey: 'gamma',
      min: 0.5,
      max: 3.0,
      divisions: 25,
      labelFormatter: (double value) => value.toStringAsFixed(2),
      description: '调整图像的亮度和对比度。较高的值会使图像更亮。',
    ),
    SliderConfig(
      labelPrefix: '自适应阈值块大小: ',
      configKey: 'blockSize',
      min: 3.0,
      max: 31.0,
      divisions: 14,
      labelFormatter: (double value) => value.toInt().toString(),
      description: '影响阈值化时考虑的局部区域大小。较大的块大小可以更好地适应光照不均。',
    ),
    SliderConfig(
      labelPrefix: '自适应阈值常数 C: ',
      configKey: 'c',
      min: -10.0,
      max: 10.0,
      divisions: 20,
      labelFormatter: (double value) => value.toString(),
      description: '用于自适应阈值的常数，减去块的平均值。正值会使阈值降低，负值则相反。',
    ),
    SliderConfig(
      labelPrefix: '轮廓面积阈值: ',
      configKey: 'areaThreshold',
      min: 1000.0,
      max: 50000.0,
      divisions: 49,
      labelFormatter: (double value) => value.toInt().toString(),
      description: '筛选轮廓时的最小面积。较高的值会忽略较小的轮廓。',
    ),
    SliderConfig(
      labelPrefix: '逼近多边形精度乘数: ',
      configKey: 'epsilonMultiplier',
      min: 0.01,
      max: 0.1,
      divisions: 9,
      labelFormatter: (double value) => value.toStringAsFixed(2),
      description: '多边形逼近的精度，值越大逼近越粗略。',
    ),
    SliderConfig(
      labelPrefix: '长宽比最小值: ',
      configKey: 'aspectRatioMin',
      min: 0.5,
      max: 1.5,
      divisions: 20,
      labelFormatter: (double value) => value.toStringAsFixed(2),
      description: '筛选轮廓时的最小长宽比。用于确保轮廓接近正方形。',
    ),
    SliderConfig(
      labelPrefix: '长宽比最大值: ',
      configKey: 'aspectRatioMax',
      min: 0.5,
      max: 1.5,
      divisions: 20,
      labelFormatter: (double value) => value.toStringAsFixed(2),
      description: '筛选轮廓时的最大长宽比。用于确保轮廓接近正方形。',
    ),
    SliderConfig(
      labelPrefix: '霍夫线变换阈值: ',
      configKey: 'threshold',
      min: 0.0,
      max: 200.0,
      divisions: 200,
      labelFormatter: (double value) => value.toInt().toString(),
      description: '霍夫线变换中检测直线的最小投票数。较高的值会检测到更明显的直线。',
    ),
    SliderConfig(
      labelPrefix: '最小线长: ',
      configKey: 'minLineLength',
      min: 0.0,
      max: 300.0,
      divisions: 300,
      labelFormatter: (double value) => value.toString(),
      description: '霍夫线变换中检测直线的最小长度。较长的线段会被优先检测。',
    ),
    SliderConfig(
      labelPrefix: '线段间隙阈值: ',
      configKey: 'maxLineGap',
      min: 0.0,
      max: 50.0,
      divisions: 50,
      labelFormatter: (double value) => value.toString(),
      description: '霍夫线变换中，允许的最大线段间隙。较大的值会将接近的线段合并。',
    ),
    SliderConfig(
      labelPrefix: '线角容差: ',
      configKey: 'angleTolerance',
      min: 0.0,
      max: math.pi / 4, // 0 到 45度
      divisions: 45,
      labelFormatter: (double value) => value.toStringAsFixed(2),
      description: '筛选直线时的角度容差（弧度）。用于区分水平和垂直线。',
    ),
    SliderConfig(
      labelPrefix: '线距离阈值: ',
      configKey: 'distanceThreshold',
      min: 5.0,
      max: 50.0,
      divisions: 45,
      labelFormatter: (double value) => value.toInt().toString(),
      description: '筛选直线时的距离阈值。用于移除接近的重复线段。',
    ),
    SliderConfig(
      labelPrefix: '白色阈值比率: ',
      configKey: 'whiteThresholdRatio',
      min: 0.0,
      max: 1.0,
      divisions: 100,
      labelFormatter: (double value) => value.toStringAsFixed(2),
      description: '检测白色棋子时的像素比例阈值。较高的值需要更多的白色像素以识别为白棋。',
    ),
    SliderConfig(
      labelPrefix: '黑色阈值比率: ',
      configKey: 'blackThresholdRatio',
      min: 0.0,
      max: 1.0,
      divisions: 100,
      labelFormatter: (double value) => value.toStringAsFixed(2),
      description: '检测黑色棋子时的像素比例阈值。较高的值需要更多的黑色像素以识别为黑棋。',
    ),
  ];
}

/// Slider配置类
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
  final String configKey; // 用于标识对应的配置项
  final double min;
  final double max;
  final int divisions;
  final String Function(double) labelFormatter;
  final String description;
}
