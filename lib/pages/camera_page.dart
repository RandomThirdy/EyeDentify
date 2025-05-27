import 'dart:async';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
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
  List<Map<String, dynamic>> _detectedObjects = [];
  
  // Optimized performance variables
  int _frameSkipCounter = 0;
  static const int _frameSkipRate = 1;
  bool _isStreamActive = false;
  
  // Detection queue for smooth processing
  final List<CameraImage> _frameQueue = [];
  bool _isProcessingQueue = false;
  Timer? _detectionTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
    _initializeTFLite();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _detectionTimer?.cancel();
    _controller?.stopImageStream();
    _controller?.dispose();
    _tfliteService.dispose();
    _frameQueue.clear();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      _detectionTimer?.cancel();
      _controller?.stopImageStream();
      _controller?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initializeCamera();
    }
  }

  Future<void> _initializeCamera() async {
    if (widget.cameras.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No camera found on this device'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    try {
      _controller = CameraController(
        widget.cameras.first,
        ResolutionPreset.medium, // Lower resolution for better performance
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

      await _controller!.initialize();
      
      if (!mounted) return;
      
      setState(() {
        _isInitialized = true;
      });

      // Start continuous detection
      await _startContinuousDetection();
      
    } catch (e) {
      print('Error initializing camera: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to initialize camera: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _startContinuousDetection() async {
    if (!_isInitialized || _controller == null || _isStreamActive) return;
    
    print('Starting continuous real-time detection...');
    
    setState(() {
      _frameSkipCounter = 0;
      _isStreamActive = true;
    });

    try {
      // Start image stream
      await _controller!.startImageStream((CameraImage image) {
        _frameSkipCounter++;
        if (_frameSkipCounter % (_frameSkipRate + 1) != 0) {
          return;
        }

        // Add frame to queue for processing
        _addFrameToQueue(image);
      });

      // Start continuous processing timer
      _startProcessingTimer();
      
    } catch (e) {
      print('Error starting image stream: $e');
      setState(() {
        _isStreamActive = false;
      });
    }
  }

  void _addFrameToQueue(CameraImage image) {
    // Keep queue size manageable - only keep latest frames
    if (_frameQueue.length > 2) {
      _frameQueue.removeAt(0);
    }
    _frameQueue.add(image);
  }

  void _startProcessingTimer() {
    // Process frames at regular intervals for smooth detection
    _detectionTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!_isProcessingQueue && _frameQueue.isNotEmpty && mounted) {
        _processNextFrame();
      }
    });
  }

  Future<void> _processNextFrame() async {
    if (_frameQueue.isEmpty || _isProcessingQueue || !mounted) return;
    
    _isProcessingQueue = true;
    
    setState(() {
      _isDetecting = true;
    });
    
    try {
      final image = _frameQueue.removeAt(0);
      
      // Process the camera stream directly with your TFLite model
      final results = await _tfliteService.detectObjectsFromStream(image);
      
      if (!mounted) return;
      
      // Convert results for display overlay
      final displayResults = _convertResultsForDisplay(results);
      
      setState(() {
        _detectedObjects = displayResults;
      });
      
    } catch (e) {
      print('Error processing frame: $e');
    } finally {
      _isProcessingQueue = false;
      if (mounted) {
        setState(() {
          _isDetecting = false;
        });
      }
    }
  }

  List<Map<String, dynamic>> _convertResultsForDisplay(List<Map<String, dynamic>> results) {
    if (!mounted) return [];
    
    final screenSize = MediaQuery.of(context).size;
    
    return results.map((result) {
      final box = result['box'] as Map<String, double>;
      
      // Convert normalized coordinates to screen coordinates
      final left = box['centerX']! * screenSize.width - (box['width']! * screenSize.width / 2);
      final top = box['centerY']! * screenSize.height - (box['height']! * screenSize.height / 2);
      final width = box['width']! * screenSize.width;
      final height = box['height']! * screenSize.height;
      
      return {
        ...result,
        'rect': Rect.fromLTWH(left, top, width, height),
      };
    }).toList();
  }

  Future<void> _initializeTFLite() async {
    try {
      await _tfliteService.initialize();
      print('TFLite service initialized successfully');
    } catch (e) {
      print('Error initializing TFLite: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load AI model: ${e.toString()}'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(
                color: Colors.blue,
                strokeWidth: 3,
              ),
              const SizedBox(height: 20),
              Text(
                'Initializing Camera & AI Model...',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(
          'Continuous Detection',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.black87,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Stack(
        children: [
          // Camera preview - full screen
          Positioned.fill(
            child: CameraPreview(_controller!),
          ),
          
          // Real-time detection overlay - Always visible
          Positioned.fill(
            child: CustomPaint(
              painter: ObjectDetectorPainter(
                objects: _detectedObjects,
              ),
            ),
          ),
          
          // Top status bar with live indicator
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Live detection status
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: _isStreamActive ? Colors.green.withOpacity(0.9) : Colors.red.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 4,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Pulsing live indicator
                      TweenAnimationBuilder<double>(
                        tween: Tween<double>(begin: 0.5, end: 1.0),
                        duration: const Duration(milliseconds: 800),
                        builder: (context, value, child) {
                          return Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.only(right: 8),
                            decoration: BoxDecoration(
                              color: _isStreamActive 
                                ? Colors.white.withOpacity(value)
                                : Colors.white,
                              shape: BoxShape.circle,
                            ),
                          );
                        },
                      ),
                      Text(
                        _isStreamActive ? 'LIVE' : 'OFFLINE',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                
                // Object count with fade animation
                AnimatedOpacity(
                  opacity: _detectedObjects.isNotEmpty ? 1.0 : 0.5,
                  duration: const Duration(milliseconds: 300),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          blurRadius: 4,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Text(
                      '${_detectedObjects.length} objects',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // Performance indicator
          Positioned(
            top: 70,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: _isDetecting ? Colors.orange : Colors.green,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _isDetecting ? 'Processing' : 'Ready',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          // Bottom instruction panel
          Positioned(
            bottom: 32,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.8),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _isStreamActive ? Colors.green : Colors.red,
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.5),
                    blurRadius: 8,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.videocam,
                        color: _isStreamActive ? Colors.green : Colors.red,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Continuous Real-time Detection',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Objects are detected continuously in real-time',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.8),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ObjectDetectorPainter extends CustomPainter {
  final List<Map<String, dynamic>> objects;

  ObjectDetectorPainter({
    required this.objects,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (var object in objects) {
      final rect = object['rect'] as Rect;
      final confidence = object['confidence'] as double;
      final className = object['class'] as String;
      
      // Dynamic color based on confidence with smooth transitions
      final Color boxColor = confidence > 0.7 
          ? Colors.green 
          : confidence > 0.5 
              ? Colors.orange 
              : Colors.red;
      
      // Box paint with animated stroke
      final boxPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = boxColor.withOpacity(0.9);

      // Fill paint with subtle transparency
      final fillPaint = Paint()
        ..style = PaintingStyle.fill
        ..color = boxColor.withOpacity(0.08);

      // Draw filled rectangle
      canvas.drawRect(rect, fillPaint);
      
      // Draw border with rounded corners
      final roundedRect = RRect.fromRectAndRadius(rect, Radius.circular(4));
      canvas.drawRRect(roundedRect, boxPaint);

      // Confidence and class label with better formatting
      final label = '$className ${(confidence * 100).toStringAsFixed(0)}%';
      final textSpan = TextSpan(
        text: label,
        style: TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          shadows: [
            Shadow(
              color: Colors.black.withOpacity(0.9),
              offset: Offset(1, 1),
              blurRadius: 3,
            ),
          ],
        ),
      );
      
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      );
      
      textPainter.layout();
      
      // Label background with better positioning
      final labelRect = Rect.fromLTWH(
        rect.left,
        rect.top - textPainter.height - 6,
        textPainter.width + 10,
        textPainter.height + 4,
      );
     
      final backgroundPaint = Paint()
        ..color = boxColor.withOpacity(0.95)
        ..style = PaintingStyle.fill;

      // Draw rounded label background
      canvas.drawRRect(
        RRect.fromRectAndRadius(labelRect, Radius.circular(3)),
        backgroundPaint,
      );
      
      // Draw text
      textPainter.paint(
        canvas, 
        Offset(rect.left + 5, rect.top - textPainter.height - 2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}