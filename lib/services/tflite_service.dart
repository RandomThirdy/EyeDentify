import 'dart:io';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;
import 'package:camera/camera.dart';

class TFLiteService {
  static const String modelPath = 'assets/model.tflite';
  static const String labelsPath = 'assets/labels.txt';
  
  bool _isInitialized = false;
  List<String> _labels = [];
  Interpreter? _interpreter;
  List<int>? _inputShape;
  List<int>? _outputShape;
  
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      print('Starting TFLite initialization...');
      
      // Check if assets exist first
      await _checkAssets();
      
      // Load labels first
      await _loadLabels();
      
      // Load model
      await _loadModel();
      
      _isInitialized = true;
      print('TFLite initialization completed successfully');
      
    } catch (e) {
      print('Error initializing TFLite: $e');
      _isInitialized = false;
      rethrow;
    }
  }

  Future<void> _checkAssets() async {
    try {
      // Check if model file exists
      final modelData = await rootBundle.load(modelPath);
      print('Model file found, size: ${modelData.lengthInBytes} bytes');
      
      if (modelData.lengthInBytes == 0) {
        throw Exception('Model file is empty');
      }
      
      // Check if labels file exists
      final labelsData = await rootBundle.loadString(labelsPath);
      print('Labels file found, length: ${labelsData.length} characters');
      
      if (labelsData.isEmpty) {
        print('Warning: Labels file is empty, will use fallback labels');
      }
      
    } catch (e) {
      print('Asset check failed: $e');
      throw Exception('Required assets not found or corrupted: $e');
    }
  }

  Future<void> _loadLabels() async {
    try {
      print('Loading labels from: $labelsPath');
      final labelData = await rootBundle.loadString(labelsPath);
      _labels = labelData
          .split('\n')
          .map((line) => line.trim())
          .where((label) => label.isNotEmpty)
          .toList();
      print('Loaded ${_labels.length} labels');
      
      // Print first few labels for debugging
      if (_labels.isNotEmpty) {
        print('First few labels: ${_labels.take(5).join(', ')}');
      }
    } catch (e) {
      print('Error loading labels: $e');
      print('Using fallback COCO class names');
      _labels = _getCocoClassNames();
    }
  }

  Future<void> _loadModel() async {
    try {
      print('Loading model from: $modelPath');
      
      // Create interpreter options for better performance
      final options = InterpreterOptions();
      
      // Try to load model from assets
      _interpreter = await Interpreter.fromAsset(modelPath, options: options);
      print('Model loaded successfully');
      
      // Get input and output tensor info
      final inputTensors = _interpreter!.getInputTensors();
      final outputTensors = _interpreter!.getOutputTensors();
      
      if (inputTensors.isEmpty || outputTensors.isEmpty) {
        throw Exception('Model has no input or output tensors');
      }
      
      _inputShape = inputTensors[0].shape;
      _outputShape = outputTensors[0].shape;
      
      print('Input shape: $_inputShape');
      print('Output shape: $_outputShape');
      print('Input type: ${inputTensors[0].type}');
      print('Output type: ${outputTensors[0].type}');
      
      // Validate shapes
      if (_inputShape == null || _inputShape!.length != 4) {
        throw Exception('Invalid input shape: $_inputShape. Expected 4D tensor [batch, height, width, channels]');
      }
      
      if (_outputShape == null || _outputShape!.length < 2) {
        throw Exception('Invalid output shape: $_outputShape');
      }
      
      // Print model details
      print('Model expects input: ${_inputShape![1]}x${_inputShape![2]}x${_inputShape![3]}');
      print('Model output shape: $_outputShape');
      
    } catch (e) {
      print('Error loading model: $e');
      print('Make sure the model file exists at: $modelPath and is a valid TFLite model');
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> detectObjects(File imageFile) async {
    if (!_isInitialized) {
      print('TFLite not initialized, attempting to initialize...');
      await initialize();
    }
    
    if (_interpreter == null) {
      throw Exception('TFLite interpreter not available after initialization');
    }

    try {
      print('Starting object detection for: ${imageFile.path}');
      
      // Verify file exists
      if (!await imageFile.exists()) {
        throw Exception('Image file does not exist: ${imageFile.path}');
      }
      
      // Read and decode image
      final imageBytes = await imageFile.readAsBytes();
      print('Image file size: ${imageBytes.length} bytes');
      
      final image = img.decodeImage(imageBytes);
      if (image == null) {
        throw Exception('Failed to decode image');
      }

      print('Original image dimensions: ${image.width}x${image.height}');

      // Get model input requirements
      final inputHeight = _inputShape![1];
      final inputWidth = _inputShape![2];
      final inputChannels = _inputShape![3];
      
      print('Model expects: ${inputWidth}x${inputHeight}x${inputChannels}');

      // Resize image to model's expected size
      final resizedImage = img.copyResize(
        image,
        width: inputWidth,
        height: inputHeight,
        interpolation: img.Interpolation.linear,
      );

      print('Resized image to: ${resizedImage.width}x${resizedImage.height}');

      // Prepare input tensor
      final input = _prepareInputTensor(resizedImage);
      
      // Prepare output buffer
      final outputBuffer = _prepareOutputBuffer();

      print('Running inference...');
      final stopwatch = Stopwatch()..start();
      
      // Run inference
      _interpreter!.run(input, outputBuffer);
      
      stopwatch.stop();
      print('Inference completed in ${stopwatch.elapsedMilliseconds}ms');

      // Process results based on model type
      final results = _processResults(outputBuffer, image.width, image.height);
      
      print('Found ${results.length} objects with confidence > 0.3');
      
      // Print detected objects for debugging
      for (var result in results) {
        print('Detected: ${result['class']} (confidence: ${(result['confidence'] * 100).toStringAsFixed(1)}%)');
      }
      
      return results;
      
    } catch (e) {
      print('Error detecting objects: $e');
      rethrow;
    }
  }

  // New method for real-time detection from camera stream
  Future<List<Map<String, dynamic>>> detectObjectsFromStream(CameraImage cameraImage) async {
    if (!_isInitialized) {
      await initialize();
    }
    
    if (_interpreter == null) {
      throw Exception('TFLite interpreter not available');
    }

    try {
      // Convert CameraImage to input tensor directly
      final input = _prepareCameraImageInput(cameraImage);
      
      // Prepare output buffer
      final outputBuffer = _prepareOutputBuffer();

      // Run inference
      _interpreter!.run(input, outputBuffer);

      // Process results
      final results = _processResults(outputBuffer, cameraImage.width, cameraImage.height);
      
      return results;
      
    } catch (e) {
      print('Error detecting objects from stream: $e');
      rethrow;
    }
  }

  // Prepare input tensor with proper normalization
  List<List<List<List<double>>>> _prepareInputTensor(img.Image image) {
    final height = _inputShape![1];
    final width = _inputShape![2];
    final channels = _inputShape![3];
    
    final input = List.generate(1, (i) => 
      List.generate(height, (y) => 
        List.generate(width, (x) => 
          List.filled(channels, 0.0)
        )
      )
    );

    // Convert image to normalized float values
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final pixel = image.getPixel(x, y);
        
        // Normalize pixel values to [0, 1] range
        // Some models expect [0, 255] range, adjust if needed
        input[0][y][x][0] = pixel.r / 255.0;
        if (channels > 1) input[0][y][x][1] = pixel.g / 255.0;
        if (channels > 2) input[0][y][x][2] = pixel.b / 255.0;
      }
    }

    return input;
  }

  // New method to process CameraImage directly
  List<List<List<List<double>>>> _prepareCameraImageInput(CameraImage cameraImage) {
    final height = _inputShape![1];
    final width = _inputShape![2];
    final channels = _inputShape![3];
    
    final input = List.generate(1, (i) => 
      List.generate(height, (y) => 
        List.generate(width, (x) => 
          List.filled(channels, 0.0)
        )
      )
    );

    // Convert YUV420 to RGB and resize
    final plane = cameraImage.planes[0];
    final imgWidth = cameraImage.width;
    final imgHeight = cameraImage.height;
    
    // Calculate scaling factors
    final scaleX = imgWidth / width;
    final scaleY = imgHeight / height;

    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        // Sample from original image with bilinear interpolation
        final srcX = (x * scaleX).floor().clamp(0, imgWidth - 1);
        final srcY = (y * scaleY).floor().clamp(0, imgHeight - 1);
        
        final pixelIndex = srcY * plane.bytesPerRow + srcX;
        if (pixelIndex < plane.bytes.length) {
          final pixelValue = plane.bytes[pixelIndex] / 255.0;
          
          // For grayscale, replicate across all channels
          input[0][y][x][0] = pixelValue;
          if (channels > 1) input[0][y][x][1] = pixelValue;
          if (channels > 2) input[0][y][x][2] = pixelValue;
        }
      }
    }

    return input;
  }

  // Prepare output buffer based on model output shape
  dynamic _prepareOutputBuffer() {
    if (_outputShape!.length == 3) {
      // Format: [1, num_detections, 6] where 6 = [x, y, w, h, confidence, class]
      final numDetections = _outputShape![1];
      final outputSize = _outputShape![2];
      
      return List.generate(1, (i) => 
        List.generate(numDetections, (j) => 
          List.filled(outputSize, 0.0)
        )
      );
    } else if (_outputShape!.length == 2) {
      // Format: [num_detections, 6]
      final numDetections = _outputShape![0];
      final outputSize = _outputShape![1];
      
      return List.generate(numDetections, (j) => 
        List.filled(outputSize, 0.0)
      );
    } else {
      // Fallback: assume single dimension output
      return List.filled(_outputShape!.reduce((a, b) => a * b), 0.0);
    }
  }

  // Updated method with improved accuracy and NMS
  List<Map<String, dynamic>> _processResults(
    dynamic output, int originalWidth, int originalHeight) {
    
    final results = <Map<String, dynamic>>[];
    const double confidenceThreshold = 0.3; // Lower threshold for better detection
    
    List<List<dynamic>> detections;
    
    // Handle different output formats
    if (output is List<List<List<dynamic>>>) {
      // 3D output: [1, num_detections, data]
      detections = List<List<dynamic>>.from(output[0]);
    } else if (output is List<List<dynamic>>) {
      // 2D output: [num_detections, data]
      detections = List<List<dynamic>>.from(output);
    } else {
      print('Unexpected output format: ${output.runtimeType}');
      return results;
    }
    
    print('Processing ${detections.length} detections');
    
    for (var i = 0; i < detections.length; i++) {
      final detection = detections[i];
      
      if (detection.length < 6) {
        print('Detection $i has insufficient data: ${detection.length} elements');
        continue;
      }
      
      double confidence;
      int classIndex;
      Map<String, double> boundingBox;
      
      // Try different formats
      if (detection.length >= 6) {
        // YOLO format: [x, y, w, h, confidence, class_id, ...]
        // or [x, y, w, h, confidence, class_scores...]
        
        confidence = detection[4].toDouble();
        
        if (confidence < confidenceThreshold) continue;
        
        // Get bounding box
        boundingBox = {
          'centerX': detection[0].toDouble().clamp(0.0, 1.0),
          'centerY': detection[1].toDouble().clamp(0.0, 1.0),
          'width': detection[2].toDouble().clamp(0.0, 1.0),
          'height': detection[3].toDouble().clamp(0.0, 1.0),
        };
        
        // Get class index
        if (detection.length == 6) {
          // Direct class index
          classIndex = detection[5].toInt();
        } else {
          // Class scores starting from index 5
          classIndex = _getClassWithHighestScore(detection.sublist(5));
        }
      } else {
        continue;
      }
      
      final className = _getClassName(classIndex);
      
      results.add({
        'confidence': confidence,
        'class': className,
        'classIndex': classIndex,
        'box': boundingBox,
      });
    }
    
    // Apply Non-Maximum Suppression
    final nmsResults = _applyNMS(results, 0.5);
    
    // Sort by confidence and limit results
    nmsResults.sort((a, b) => b['confidence'].compareTo(a['confidence']));
    return nmsResults.take(5).toList();
  }

  // Apply Non-Maximum Suppression for better accuracy
  List<Map<String, dynamic>> _applyNMS(List<Map<String, dynamic>> detections, double iouThreshold) {
    if (detections.isEmpty) return [];
    
    // Sort by confidence
    detections.sort((a, b) => b['confidence'].compareTo(a['confidence']));
    
    final keep = <Map<String, dynamic>>[];
    final suppress = <bool>[];
    
    for (var i = 0; i < detections.length; i++) {
      suppress.add(false);
    }
    
    for (var i = 0; i < detections.length; i++) {
      if (suppress[i]) continue;
      
      keep.add(detections[i]);
      
      for (var j = i + 1; j < detections.length; j++) {
        if (suppress[j]) continue;
        
        final iou = _calculateIOU(detections[i]['box'], detections[j]['box']);
        if (iou > iouThreshold) {
          suppress[j] = true;
        }
      }
    }
    
    return keep;
  }

  // Calculate Intersection over Union (IOU)
  double _calculateIOU(Map<String, double> box1, Map<String, double> box2) {
    final x1_1 = box1['centerX']! - box1['width']! / 2;
    final y1_1 = box1['centerY']! - box1['height']! / 2;
    final x2_1 = box1['centerX']! + box1['width']! / 2;
    final y2_1 = box1['centerY']! + box1['height']! / 2;
    
    final x1_2 = box2['centerX']! - box2['width']! / 2;
    final y1_2 = box2['centerY']! - box2['height']! / 2;
    final x2_2 = box2['centerX']! + box2['width']! / 2;
    final y2_2 = box2['centerY']! + box2['height']! / 2;
    
    final intersectionX1 = [x1_1, x1_2].reduce((a, b) => a > b ? a : b);
    final intersectionY1 = [y1_1, y1_2].reduce((a, b) => a > b ? a : b);
    final intersectionX2 = [x2_1, x2_2].reduce((a, b) => a < b ? a : b);
    final intersectionY2 = [y2_1, y2_2].reduce((a, b) => a < b ? a : b);
    
    final intersectionArea = (intersectionX2 - intersectionX1).clamp(0.0, double.infinity) * 
                            (intersectionY2 - intersectionY1).clamp(0.0, double.infinity);
    
    final area1 = box1['width']! * box1['height']!;
    final area2 = box2['width']! * box2['height']!;
    final unionArea = area1 + area2 - intersectionArea;
    
    return unionArea > 0 ? intersectionArea / unionArea : 0.0;
  }

  int _getClassWithHighestScore(List<dynamic> classScores) {
    var maxScore = 0.0;
    var maxClass = 0;
    
    for (var i = 0; i < classScores.length; i++) {
      final score = classScores[i].toDouble();
      if (score > maxScore) {
        maxScore = score;
        maxClass = i;
      }
    }
    
    return maxClass;
  }

  String _getClassName(int classIndex) {
    if (classIndex < 0) return 'unknown';
    
    // Use loaded labels if available
    if (_labels.isNotEmpty && classIndex < _labels.length) {
      return _labels[classIndex];
    }
    
    // Fallback to COCO class names
    final cocoClasses = _getCocoClassNames();
    if (classIndex < cocoClasses.length) {
      return cocoClasses[classIndex];
    }
    
    return 'class_$classIndex';
  }

  List<String> _getCocoClassNames() {
    return [
      'person', 'bicycle', 'car', 'motorcycle', 'airplane',
      'bus', 'train', 'truck', 'boat', 'traffic light',
      'fire hydrant', 'stop sign', 'parking meter', 'bench', 'bird',
      'cat', 'dog', 'horse', 'sheep', 'cow',
      'elephant', 'bear', 'zebra', 'giraffe', 'backpack',
      'umbrella', 'handbag', 'tie', 'suitcase', 'frisbee',
      'skis', 'snowboard', 'sports ball', 'kite', 'baseball bat',
      'baseball glove', 'skateboard', 'surfboard', 'tennis racket', 'bottle',
      'wine glass', 'cup', 'fork', 'knife', 'spoon',
      'bowl', 'banana', 'apple', 'sandwich', 'orange',
      'broccoli', 'carrot', 'hot dog', 'pizza', 'donut',
      'cake', 'chair', 'couch', 'potted plant', 'bed',
      'dining table', 'toilet', 'tv', 'laptop', 'mouse',
      'remote', 'keyboard', 'cell phone', 'microwave', 'oven',
      'toaster', 'sink', 'refrigerator', 'book', 'clock',
      'vase', 'scissors', 'teddy bear', 'hair drier', 'toothbrush'
    ];
  }

  // Helper methods
  bool get isInitialized => _isInitialized;
  
  List<String> get labels => List.unmodifiable(_labels);
  
  List<int>? get inputShape => _inputShape;
  
  List<int>? get outputShape => _outputShape;

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _isInitialized = false;
    _labels.clear();
    _inputShape = null;
    _outputShape = null;
    print('TFLite service disposed');
  }
}