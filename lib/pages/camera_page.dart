import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../services/tflite_service.dart';

class CameraPage extends StatefulWidget {
  final String mode;
  final List<CameraDescription> cameras;

  const CameraPage({
    super.key,
    required this.mode,
    required this.cameras,
  });

  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> with WidgetsBindingObserver {
  CameraController? _controller;
  bool _isInitialized = false;
  bool _isDetecting = false;
  final TFLiteService _tfliteService = TFLiteService();
  final SpeechToText _speechToText = SpeechToText();
  final FlutterTts _flutterTts = FlutterTts();
  List<Map<String, dynamic>> _detectedObjects = [];
  bool _isContinuousDetection = false;
  DateTime _lastDetectionTime = DateTime.now();
  static const Duration _detectionInterval = Duration(milliseconds: 500);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
    _initializeSpeech();
    _initializeTTS();
    _initializeTFLite();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    _tfliteService.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      _controller?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initializeCamera();
    }
  }

  Future<void> _initializeCamera() async {
    if (widget.cameras.isEmpty) {
      await _flutterTts.speak('No camera found on this device');
      return;
    }

    try {
      _controller = CameraController(
        widget.cameras.first,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await _controller!.initialize();
      
      if (!mounted) return;
      
      setState(() {
        _isInitialized = true;
      });
      
      // Start preview
      await _controller!.setFocusMode(FocusMode.auto);
      await _controller!.setExposureMode(ExposureMode.auto);

      // Start continuous detection if in object detection mode
      if (widget.mode == 'objectDetection') {
        setState(() {
          _isContinuousDetection = true;
        });
        _startContinuousDetection();
      }
    } catch (e) {
      print('Error initializing camera: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to initialize camera: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
        await _flutterTts.speak('Failed to initialize camera. Please check camera permissions.');
      }
    }
  }

  Future<void> _startContinuousDetection() async {
    while (_isContinuousDetection && mounted) {
      try {
        if (!_isDetecting && 
            DateTime.now().difference(_lastDetectionTime) > _detectionInterval) {
          await _detectObjects();
        }
        await Future.delayed(const Duration(milliseconds: 100));
      } catch (e) {
        print('Error in continuous detection: $e');
        // Don't stop the loop on error, just continue
      }
    }
  }

  Future<void> _initializeSpeech() async {
    await _speechToText.initialize();
  }

  Future<void> _initializeTTS() async {
    await _flutterTts.setLanguage('en-US');
  }

  Future<void> _initializeTFLite() async {
    try {
      await _tfliteService.initialize();
    } catch (e) {
      print('Error initializing TFLite: $e');
    }
  }

  Future<void> _startListening() async {
    if (!_speechToText.isAvailable) return;

    await _speechToText.listen(
      onResult: (result) {
        if (result.finalResult) {
          _processVoiceCommand(result.recognizedWords.toLowerCase());
        }
      },
    );
  }

  Future<void> _processVoiceCommand(String command) async {
    if (command.contains('what') && (command.contains('front') || command.contains('see'))) {
      await _flutterTts.speak('I will scan what is in front of you');
      await _detectObjects();
    } else if (command.contains('detect') || command.contains('scan')) {
      await _detectObjects();
    } else if (command.contains('stop') || command.contains('pause')) {
      setState(() {
        _isContinuousDetection = false;
      });
      await _flutterTts.speak('Object detection paused');
    } else if (command.contains('start') || command.contains('resume')) {
      setState(() {
        _isContinuousDetection = true;
      });
      await _flutterTts.speak('Resuming object detection');
      _startContinuousDetection();
    }
  }

  Future<void> _detectObjects() async {
    if (!_isInitialized || _isDetecting) return;

    setState(() {
      _isDetecting = true;
    });

    try {
      if (_controller == null || !_controller!.value.isInitialized) {
        throw Exception('Camera not initialized');
      }

      final image = await _controller!.takePicture();
      if (!mounted) return;

      final results = await _tfliteService.detectObjects(File(image.path));
      
      if (!mounted) return;
      
      setState(() {
        _detectedObjects = results;
        _lastDetectionTime = DateTime.now();
      });

      // Announce results with more natural language
      if (results.isNotEmpty) {
        String message;
        if (results.length == 1) {
          final obj = results.first;
          message = 'I can see a ${obj['class']} with ${(obj['confidence'] * 100).toStringAsFixed(1)}% confidence';
        } else {
          final objects = results.map((obj) => 
            '${obj['class']}'
          ).join(', ');
          message = 'I can see multiple objects: $objects';
        }
        await _flutterTts.speak(message);
      } else {
        await _flutterTts.speak('I cannot detect any objects at the moment');
      }
    } catch (e) {
      print('Error detecting objects: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error detecting objects: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
        await _flutterTts.speak('Sorry, I encountered an error while detecting objects');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isDetecting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    final size = MediaQuery.of(context).size;
    final scale = 1 / (_controller!.value.aspectRatio * size.aspectRatio);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.mode == 'objectDetection' ? 'Object Detection' : 'Camera'),
        actions: [
          IconButton(
            icon: Icon(_isContinuousDetection ? Icons.pause : Icons.play_arrow),
            onPressed: () {
              setState(() {
                _isContinuousDetection = !_isContinuousDetection;
              });
              if (_isContinuousDetection) {
                _startContinuousDetection();
              }
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          // Camera preview
          Center(
            child: Transform.scale(
              scale: scale,
              child: CameraPreview(_controller!),
            ),
          ),
          // Object detection boxes
          if (_detectedObjects.isNotEmpty)
            CustomPaint(
              painter: ObjectDetectorPainter(
                objects: _detectedObjects,
                imageSize: size,
                scale: scale,
              ),
            ),
          // Voice command button
          Positioned(
            bottom: 20,
            right: 20,
            child: FloatingActionButton(
              onPressed: _startListening,
              child: const Icon(Icons.mic),
            ),
          ),
        ],
      ),
    );
  }
}

class ObjectDetectorPainter extends CustomPainter {
  final List<Map<String, dynamic>> objects;
  final Size imageSize;
  final double scale;

  ObjectDetectorPainter({
    required this.objects,
    required this.imageSize,
    required this.scale,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = Colors.red;

    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
    );

    for (var object in objects) {
      final rect = object['rect'] as Rect;
      final scaledRect = Rect.fromLTWH(
        rect.left * scale,
        rect.top * scale,
        rect.width * scale,
        rect.height * scale,
      );

      // Draw rectangle
      canvas.drawRect(scaledRect, paint);

      // Draw label
      final label = '${object['class']} ${(object['confidence'] * 100).toStringAsFixed(1)}%';
      textPainter.text = TextSpan(
        text: label,
        style: const TextStyle(
          color: Colors.red,
          fontSize: 14,
          fontWeight: FontWeight.bold,
        ),
      );

      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(
          scaledRect.left,
          scaledRect.top - textPainter.height,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(ObjectDetectorPainter oldDelegate) {
    return oldDelegate.objects != objects;
  }
}