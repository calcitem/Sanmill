// image_to_fen_app.dart

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;

import '../../shared/services/logger.dart';
import 'board_detection.dart';
import 'fen_generator.dart';
import 'image_processing_config.dart';
import 'piece_detection.dart';

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

class ImageToFenAppState extends State<ImageToFenApp> {
  Uint8List? _processedImage;
  Uint8List? grayImage;
  Uint8List? enhancedImage;
  Uint8List? threshImage;
  Uint8List? warpedImage;

  String _fenString = '';

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
      final double inverseGamma = 1.0 / ImageProcessingConfig.gammaConfig.gamma;
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
      final cv.Mat blurred = cv.gaussianBlur(
        enhanced,
        ImageProcessingConfig.parameters.gaussianKernelSize,
        0,
      );
      logger.i('高斯模糊完成，Blurred Mat 尺寸: ${blurred.rows}x${blurred.cols}');

      // 自适应阈值
      logger.i('应用自适应阈值');
      final cv.Mat thresh = cv.adaptiveThreshold(
        blurred,
        255,
        cv.ADAPTIVE_THRESH_GAUSSIAN_C,
        cv.THRESH_BINARY_INV,
        ImageProcessingConfig.adaptiveThresholdConfig.blockSize,
        ImageProcessingConfig.adaptiveThresholdConfig.c,
      );
      logger.i('自适应阈值完成，Thresh Mat 尺寸: ${thresh.rows}x${thresh.cols}');

      // 应用闭运算以连接断裂的边缘
      logger.i('应用闭运算以连接断裂的边缘');
      final cv.Mat kernel = cv.getStructuringElement(
        cv.MORPH_RECT,
        ImageProcessingConfig.parameters.morphologyKernelSize,
      );
      final cv.Mat closed = cv.morphologyEx(
        thresh,
        cv.MORPH_CLOSE,
        kernel,
      );
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

      // 查找轮廓
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
        if (area < ImageProcessingConfig.contourConfig.areaThreshold) {
          logger.i(
              '轮廓[$idx] 面积小于阈值 ${ImageProcessingConfig.contourConfig.areaThreshold}，跳过');
          continue;
        }

        final double peri = cv.arcLength(contour, true);
        logger.i('轮廓[$idx] 的周长: $peri');

        final cv.VecPoint approx = cv.approxPolyDP(
          contour,
          ImageProcessingConfig.contourConfig.epsilonMultiplier * peri,
          true,
        ); // 使用可调epsilon
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

          if (aspectRatio >
                  ImageProcessingConfig.contourConfig.aspectRatioMin &&
              aspectRatio <
                  ImageProcessingConfig.contourConfig.aspectRatioMax) {
            logger.i(
                '轮廓[$idx] 的长宽比在可接受范围内 (${ImageProcessingConfig.contourConfig.aspectRatioMin} - ${ImageProcessingConfig.contourConfig.aspectRatioMax})');
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
                '轮廓[$idx] 的长宽比不在可接受范围内 (${ImageProcessingConfig.contourConfig.aspectRatioMin} - ${ImageProcessingConfig.contourConfig.aspectRatioMax})');
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
          cv.Scalar(
            ImageProcessingConfig.parameters.drawContoursColor.$1.toDouble(),
            ImageProcessingConfig.parameters.drawContoursColor.$2.toDouble(),
            ImageProcessingConfig.parameters.drawContoursColor.$3.toDouble(),
          ), // 使用配置中的颜色
          thickness: ImageProcessingConfig.parameters.drawContoursThickness,
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
        final cv.Mat warped = warpPerspective(mat, boardContour);
        logger.i('透视变换完成，Warped Mat 尺寸: ${warped.rows}x${warped.cols}');

        // 应用边缘检测和霍夫线变换
        logger.i('应用边缘检测和霍夫线变换');
        final cv.Mat warpedWithLines = applyEdgeDetectionAndHoughLines(warped);
        logger.i(
            '边缘检测和霍夫线变换完成，WarpedWithLines Mat 尺寸: ${warpedWithLines.rows}x${warpedWithLines.cols}');

        // 调试：显示透视变换后的图像
        logger.i('编码透视变换后的图像');
        warpedImage = cv.imencode('.png', warpedWithLines).$2;
        logger.i('透视变换后图像编码完成，大小: ${warpedImage!.length} 字节');

        // Detect piece positions
        logger.i('检测棋子位置');
        final List<String> positions = detectPieces(warped);
        logger.i('检测到的棋子位置数量: ${positions.length}');
        for (int i = 0; i < positions.length; i++) {
          logger.i('棋子[$i] 位置: ${positions[i]}');
        }

        // 在图像上绘制识别结果
        logger.i('在图像上绘制识别结果');
        final cv.Mat warpedWithAnnotations = warped.clone();
        annotatePieces(warpedWithAnnotations, positions);
        logger.i('绘制识别结果完成');

        // Generate FEN string
        logger.i('生成 FEN 字符串');
        final String fen = generateFEN(positions);
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

  @override
  Widget build(BuildContext context) {
    final UIConfig uiConfig = ImageProcessingConfig.uiConfig;

    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: Text(uiConfig.appBarTitle)),
        body: Center(
          child: SingleChildScrollView(
            child: Column(
              children: <Widget>[
                // 图像处理按钮
                ElevatedButton(
                  onPressed: _processImage,
                  child: Text(uiConfig.selectAndProcessImageButton),
                ),

                // 显示处理后的图像和FEN字符串
                if (_processedImage != null) ...<Widget>[
                  Image.memory(_processedImage!),
                  const SizedBox(height: 20),
                  Text('${uiConfig.fenStringLabel}$_fenString'),
                ],
                if (_fenString.isNotEmpty &&
                    _processedImage == null) ...<Widget>[
                  const SizedBox(height: 20),
                  Text(_fenString),
                ],

                // 显示调试图像（可选）
                if (grayImage != null) ...<Widget>[
                  Text(uiConfig.debugImageLabels['grayImage']!),
                  Image.memory(grayImage!),
                ],
                if (enhancedImage != null) ...<Widget>[
                  Text(uiConfig.debugImageLabels['enhancedImage']!),
                  Image.memory(enhancedImage!),
                ],
                if (threshImage != null) ...<Widget>[
                  Text(uiConfig.debugImageLabels['threshImage']!),
                  Image.memory(threshImage!),
                ],
                if (warpedImage != null) ...<Widget>[
                  Text(uiConfig.debugImageLabels['warpedImage']!),
                  Image.memory(warpedImage!),
                ],

                // 添加阈值设置区域
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: ImageProcessingConfig.uiConfig.sliders
                        .map((SliderConfig sliderConfig) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            // Slider标题
                            Text(
                              '${sliderConfig.labelPrefix}${sliderConfig.labelFormatter(ImageProcessingConfig.getSliderValue(sliderConfig.configKey))}',
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            // Slider本体
                            Slider(
                              value: ImageProcessingConfig.getSliderValue(
                                  sliderConfig.configKey),
                              min: sliderConfig.min,
                              max: sliderConfig.max,
                              divisions: sliderConfig.divisions,
                              label: sliderConfig.labelFormatter(
                                  ImageProcessingConfig.getSliderValue(
                                      sliderConfig.configKey)),
                              onChanged: (double value) {
                                setState(() {
                                  ImageProcessingConfig.updateConfig(
                                      sliderConfig.configKey, value);
                                });
                              },
                            ),
                            // Slider描述
                            Text(
                              sliderConfig.description,
                              style: TextStyle(color: Colors.grey[700]),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
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
