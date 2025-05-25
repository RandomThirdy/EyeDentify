import 'dart:io';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;

class TFLiteService {
  static const String modelPath = 'assets/model.tflite';
  static const String labelsPath = 'assets/label.txt';
  
  bool _isInitialized = false;
  List<String> _labels = [];
  Interpreter? _interpreter;
  
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Load labels
      final labelData = await rootBundle.loadString(labelsPath);
      _labels = labelData.split('\n');
      
      // Load model
      _interpreter = await Interpreter.fromAsset(modelPath);
      
      _isInitialized = true;
    } catch (e) {
      print('Error initializing TFLite: $e');
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> detectObjects(File imageFile) async {
    if (!_isInitialized || _interpreter == null) {
      throw Exception('TFLite not initialized');
    }

    try {
      // Read and decode image
      final imageBytes = await imageFile.readAsBytes();
      final image = img.decodeImage(imageBytes);
      
      if (image == null) {
        throw Exception('Failed to decode image');
      }

      // Resize image to 416x416
      final resizedImage = img.copyResize(
        image,
        width: 416,
        height: 416,
      );

      // Prepare input buffer as a 4D tensor [1, 416, 416, 3]
      final input = List.generate(1, (i) => 
        List.generate(416, (y) => 
          List.generate(416, (x) => 
            List.filled(3, 0.0)
          )
        )
      );

      // Convert image to normalized float values
      for (var y = 0; y < 416; y++) {
        for (var x = 0; x < 416; x++) {
          final pixel = resizedImage.getPixel(x, y);
          
          // Extract RGB values from the pixel using the updated API
          final r = pixel.r;
          final g = pixel.g;
          final b = pixel.b;
          
          // Normalize pixel values to [0, 1]
          input[0][y][x][0] = r / 255.0;
          input[0][y][x][1] = g / 255.0;
          input[0][y][x][2] = b / 255.0;
        }
      }

      // Prepare output buffer as a 3D tensor [1, 10647, 85]
      final output = List.generate(1, (i) => 
        List.generate(10647, (j) => 
          List.filled(85, 0.0)
        )
      );

      // Run inference
      _interpreter!.run(input, output);

      // Process results
      final results = <Map<String, dynamic>>[];
      final flatOutput = output[0];  // Get the first batch
      
      for (var i = 0; i < 10647; i++) {
        final confidence = flatOutput[i][4];  // Confidence score
        if (confidence > 0.5) {
          results.add({
            'confidence': confidence,
            'class': _getClassWithHighestScore(flatOutput[i]),
            'box': _getBoundingBox(flatOutput[i]),
          });
        }
      }

      return results;
    } catch (e) {
      print('Error detecting objects: $e');
      rethrow;
    }
  }

  String _getClassWithHighestScore(List<double> detection) {
    var maxScore = 0.0;
    var maxClass = 0;
    for (var i = 0; i < 80; i++) {
      final score = detection[5 + i];  // Class scores start at index 5
      if (score > maxScore) {
        maxScore = score;
        maxClass = i;
      }
    }
    return _getClassName(maxClass);
  }

  Map<String, double> _getBoundingBox(List<double> detection) {
    return {
      'x': detection[0],
      'y': detection[1],
      'width': detection[2],
      'height': detection[3],
    };
  }

  String _getClassName(int classIndex) {
    // Add your class names here
    final classNames = [
      'airplane', 'apple', 'backpack', 'banana', 'baseball bat',
      'baseball glove', 'bear', 'bed', 'bench', 'bicycle',
      'bird', 'boat', 'book', 'bottle', 'bowl',
      'broccoli', 'bus', 'cake', 'car', 'carrot',
      'cat', 'cell phone', 'chair', 'clock', 'couch',
      'cow', 'cup', 'dining table', 'dog', 'donut',
      'elephant', 'fire hydrant', 'fork', 'frisbee', 'giraffe',
      'handbag', 'horse', 'hot dog', 'keyboard', 'kite',
      'knife', 'laptop', 'microwave', 'motorcycle', 'mouse',
      'orange', 'oven', 'parking meter', 'person', 'pizza',
      'potted plant', 'refrigerator', 'remote', 'sandwich', 'scissors',
      'sheep', 'sink', 'skateboard', 'skis', 'snowboard',
      'spoon', 'sports ball', 'stop sign', 'suitcase', 'surfboard',
      'teddy bear', 'tennis racket', 'tie', 'toilet', 'toothbrush',
      'traffic light', 'train', 'truck', 'tv', 'umbrella',
      'vase', 'wine glass', 'zebra'
    ];
    return classNames[classIndex];
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _isInitialized = false;
    _labels.clear();
  }
}