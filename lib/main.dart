import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:camera/camera.dart';
import 'theme.dart';
import 'pages/camera_page.dart';
import 'services/openai_service.dart'; 
import 'package:tflite_flutter/tflite_flutter.dart';


late Interpreter interpreter;

void loadModel() async {
  interpreter = await Interpreter.fromAsset('models/model.tflite');
  print('Model loaded!');
}
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cameras = await availableCameras();
  runApp(MyApp(cameras: cameras));
}

class MyApp extends StatelessWidget {
  final List<CameraDescription> cameras;

  const MyApp({super.key, required this.cameras});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EyeDentify - Accessibility App',
      theme: AppTheme.lightTheme,
      home: LandingPage(cameras: cameras),
    );
  }
}

class LandingPage extends StatefulWidget {
  final List<CameraDescription> cameras;
  
  const LandingPage({super.key, required this.cameras});

  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<Offset> _slideAnimation;
  bool _showMessage = false;
  String _message = '';
  final FlutterTts _flutterTts = FlutterTts();
  final SpeechToText _speechToText = SpeechToText();
  bool _isListening = false;
  String _lastWords = '';
  final OpenAIService _openAIService = OpenAIService(); // Initialize OpenAI service
  bool _isProcessing = false; // Flag to track if we're processing a command

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _initializeSpeech();
    _announceInstructions();
  }

  Future<void> _initializeSpeech() async {
    await _speechToText.initialize();
    await _flutterTts.setLanguage("en-US");
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);
  }

  void _announceInstructions() async {
    HapticFeedback.mediumImpact();
    await _flutterTts.speak(
      "Welcome to EyeDentify, your voice-controlled assistant. "
      "To use the system, swipe right to activate voice commands. "
      "You can say what you need, and I'll help you detect objects, "
      "read text, get your location, or check the time. "
      "You can also ask more natural questions like 'What's in front of me?' "
      "or 'Help me understand this document.' "
      "Swipe left at any time to return to this home screen. "
      "The system will provide voice feedback for all actions. "
      "Swipe right now to begin."
    );
    _showNotification("Welcome to EyeDentify. Swipe right to begin.");
  }

  @override
  void dispose() {
    _animationController.dispose();
    _flutterTts.stop();
    super.dispose();
  }

  void _setupAnimations() {
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    
    _slideAnimation = Tween<Offset>(
      begin: const Offset(-1.0, 0.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    ));
  }

  Future<void> _startListening() async {
    if (!_speechToText.isAvailable) {
      _flutterTts.speak("Speech recognition is not available on this device");
      _showNotification("Speech recognition is not available");
      return;
    }

    try {
      await _speechToText.listen(
        onResult: _onSpeechResult,
        listenFor: const Duration(seconds: 10), // Reduced to avoid timeouts
        pauseFor: const Duration(seconds: 2), // Reduced to be more responsive
        partialResults: true,
        localeId: "en_US",
        onSoundLevelChange: (level) {
          if (level > 0) {
            HapticFeedback.lightImpact();
          }
        },
        cancelOnError: false, // Don't cancel on error to be more robust
        listenMode: ListenMode.confirmation,
      );

      setState(() {
        _isListening = true;
        _lastWords = ''; // Clear previous words
      });

      _flutterTts.speak("I'm listening. What can I help you with?");
      _showNotification("I'm listening. What can I help you with?");
      
      // Set a timeout in case speech recognition doesn't complete naturally
      Future.delayed(const Duration(seconds: 15), () {
        if (_isListening && mounted) {
          _stopListening();
          if (_lastWords.isEmpty) {
            _flutterTts.speak("I didn't hear anything. Please try again.");
            _showNotification("No speech detected. Please try again.");
          }
        }
      });
      
    } catch (e) {
      print('Error starting speech recognition: $e');
      _flutterTts.speak("Failed to start voice recognition. Please try again.");
      _showNotification("Failed to start voice recognition");
    }
  }

  void _stopListening() {
    _speechToText.stop();
    setState(() {
      _isListening = false;
    });
  }

  void _onSpeechResult(result) {
    setState(() {
      _lastWords = result.recognizedWords.toLowerCase();
    });
    
    // Display what the user is saying in real-time
    if (result.recognizedWords.isNotEmpty) {
      _showNotification("I heard: \"${result.recognizedWords}\"");
    }

    if (result.finalResult) {
      print("Final speech result: ${result.recognizedWords}");
      
      // Make sure we received something before processing
      if (result.recognizedWords.isNotEmpty) {
        _processCommand(_lastWords);
      } else {
        _flutterTts.speak("I didn't hear anything. Please try again.");
        _showNotification("No speech detected. Please try again.");
      }
      
      setState(() {
        _isListening = false;
      });
    }
  }

  Future<void> _processCommand(String command) async {
    // Don't process empty commands or if we're already processing
    if (command.isEmpty || _isProcessing) {
      return;
    }

    print("Processing command: $command");
    
    setState(() {
      _isProcessing = true;
      _showNotification("Processing your request: \"$command\"");
    });

    // Simple command handling for better reliability
    // Check for simple command patterns first before calling OpenAI
    String mode = "default";
    if (command.contains("object") || command.contains("detect") || 
        command.contains("what") && command.contains("front") || 
        command.contains("see") && command.contains("around") ||
        command.contains("identify")) {
      mode = "objectDetection";
    } else if (command.contains("text") || command.contains("read") || 
               command.contains("document")) {
      mode = "textReader";
    } else if (command.contains("location") || command.contains("where")) {
      mode = "location";
    } else if (command.contains("time") || command.contains("date") || 
               command.contains("clock")) {
      mode = "timeDate";
    }

    // If we recognized a direct command, handle it immediately
    if (mode != "default") {
      _flutterTts.speak("Processing $mode request.");
      _navigateToCameraWithMode(mode);
      setState(() {
        _isProcessing = false;
      });
      return;
    }

    // For more complex requests, call OpenAI
    try {
      // Process command with OpenAI
      print("Sending to OpenAI: $command");
      final response = await _openAIService.processCommand(command);
      print("OpenAI response: $response");
      
      // Provide feedback
      _flutterTts.speak(response.response);
      _showNotification(response.response);

      // Take action based on OpenAI's recommendation
     
// Replace the switch statement in your _processCommand method with this:
      switch (response.mode) {
        case "objectDetection":
          _navigateToCameraWithMode("objectDetection");
          break;
        case "textReader":
          _navigateToCameraWithMode("textReader");
          break;
        case "location":
          _navigateToCameraWithMode("location");
          break;
        case "timeDate":
          _navigateToCameraWithMode("timeDate");
          break;
        case "help":
          _showHelp();
          break;
        case "unknown":
        default:
          // Already handled with the spoken response
          break;
      }
    } catch (e) {
      print("Error processing command: $e");
      _flutterTts.speak("I'm having trouble processing your request. Please try again.");
      _showNotification("Error processing command");
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  void _showHelp() {
    HapticFeedback.mediumImpact();
    _flutterTts.speak(
      "You can ask me to detect objects around you, read text from images, "
      "tell you your location, or check the time. Just swipe right and speak naturally."
    );
  }

  void _navigateToCameraWithMode(String mode) {
    HapticFeedback.mediumImpact();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CameraPage(
          mode: mode,
          cameras: widget.cameras,
        ),
      ),
    );
  }

  void _showNotification(String message) {
    setState(() {
      _message = message;
      _showMessage = true;
    });
    _animationController.forward();
    
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        _animationController.reverse().then((_) {
          setState(() {
            _showMessage = false;
          });
        });
      }
    });
  }

  void _onSwipe(DragEndDetails details) {
    if (details.primaryVelocity != null) {
      if (details.primaryVelocity! < -500) {
        // Swipe Left - go back
        HapticFeedback.heavyImpact();
        _flutterTts.speak("Returning to previous screen");
        Navigator.pop(context);
      } else if (details.primaryVelocity! > 500) {
        // Swipe Right - start listening for command
        HapticFeedback.mediumImpact();
        _startListening();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragEnd: _onSwipe,
      child: Scaffold(
        body: Stack(
          children: [
            // Soothing gradient background
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Theme.of(context).colorScheme.primary.withOpacity(0.3),
                    Theme.of(context).colorScheme.secondary.withOpacity(0.2),
                    Theme.of(context).scaffoldBackgroundColor,
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
            ),
            
            // Main content
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildPulsingIcon(),
                        
                        const SizedBox(height: 32),
                        _buildTitle(),
                        
                        const SizedBox(height: 24),
                        _buildSubtitle(context),
                        
                        const SizedBox(height: 40),
                        _buildCommandCard(),
                        
                        const SizedBox(height: 40),
                        _buildSwipeInstructions(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            
            // Notification overlay
            if (_showMessage)
              Positioned(
                top: 60,
                left: 0,
                right: 0,
                child: SlideTransition(
                  position: _slideAnimation,
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 24),
                    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _isListening ? Icons.mic : 
                          _isProcessing ? Icons.hourglass_top : Icons.info_outline,
                          color: Theme.of(context).colorScheme.onPrimary,
                          size: 24,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            _message,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // Listening indicator
            if (_isListening)
              Positioned(
                bottom: 40,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 32),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.mic,
                          color: Theme.of(context).colorScheme.onPrimary,
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          "Listening...",
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildTitle() {
    return ShaderMask(
      shaderCallback: (bounds) => LinearGradient(
        colors: [
          Theme.of(context).colorScheme.tertiary,
          Theme.of(context).colorScheme.primary,
        ],
      ).createShader(bounds),
      child: const Text(
        "EyeDentify",
        style: TextStyle(
          fontSize: 42,
          fontWeight: FontWeight.bold,
          color: Colors.white,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildSubtitle(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withOpacity(0.2),
        ),
      ),
      child: Text(
        "Your intelligent Voice Assistant",
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onBackground,
          fontSize: 20,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildPulsingIcon() {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.8, end: 1.0),
      duration: const Duration(seconds: 2),
      curve: Curves.easeInOut,
      builder: (context, value, child) {
        return Container(
          width: 140,
          height: 140,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Theme.of(context).colorScheme.primary,
                Theme.of(context).colorScheme.secondary,
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.2),
                blurRadius: 20,
                spreadRadius: 5,
              ),
            ],
          ),
          child: Transform.scale(
            scale: value,
            child: Icon(
              Icons.visibility,
              size: 70,
              color: Theme.of(context).colorScheme.onPrimary,
            ),
          ),
        );
      },
    );
  }

  Widget _buildCommandCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondary.withOpacity(0.5),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withOpacity(0.2),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            "Ask me anything",
            style: TextStyle(
              color: Theme.of(context).colorScheme.onBackground,
              fontSize: 24,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 24),
          _buildCommandItem(
            "What's in front of me?",
            "Detect objects in real-time",
            
            Icons.camera_alt,
          ),
          _buildCommandItem(
            "Read this document",
            "Read text from images",
            Icons.text_fields,
          ),
          _buildCommandItem(
            "Where am I right now?",
            "Get your current location",
            Icons.location_on,
          ),
          _buildCommandItem(
            "What time is it?",
            "Get current time and date",
            Icons.access_time,
          ),
          const SizedBox(height: 24),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.mic,
                  size: 20,
                  color: Theme.of(context).colorScheme.onBackground,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    "Powered by AI - Just ask in your own words",
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onBackground,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCommandItem(String command, String description, IconData icon) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              size: 24,
              color: Theme.of(context).colorScheme.onBackground,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  command,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onBackground,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onBackground.withOpacity(0.7),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSwipeInstructions() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withOpacity(0.2),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.swipe,
            size: 24,
            color: Theme.of(context).colorScheme.onBackground,
          ),
          const SizedBox(width: 12),
          Text(
            "Swipe right to activate voice commands",
            style: TextStyle(
              color: Theme.of(context).colorScheme.onBackground,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}