import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

class OpenAIService {
  // Important: In production, store this key securely, not hardcoded
  // Consider using environment variables, Flutter secure storage, or a backend service
  

  /// Process a voice command through OpenAI to get intelligent responses
  /// and determine appropriate actions
  Future<OpenAIResponse> processCommand(String command) async {
    try {
      // Define the system message to set the AI's behavior
      const systemMessage = """
        You are an assistant for a voice-controlled accessibility app called EyeDentify.
        Your task is to understand user voice commands and map them to appropriate actions.
        Respond with a JSON object containing:
        1. "mode": One of ["objectDetection", "textReader", "location", "timeDate", "help", "unknown"]
        2. "confidence": A number between 0-1 indicating how confident you are about understanding the command
        3. "response": A natural language response to speak back to the user
        4. "additionalInfo": Any extra parameters or context needed for the action
              """;

      // Create the API request
      final response = await http.post(
        Uri.parse(_apiUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_apiKey',
        },
        body: jsonEncode({
          'model': 'gpt-4', // Using GPT-4 for better understanding
          'messages': [
            {'role': 'system', 'content': systemMessage},
            {'role': 'user', 'content': command}
          ],
          'temperature': 0.3, // Lower temperature for more consistent outputs
          'max_tokens': 200,
          'response_format': {'type': 'json_object'}, // Ensure JSON format
        }),
      );

      if (response.statusCode == 200) {
        // Parse the response
        final Map<String, dynamic> data = jsonDecode(response.body);
        final String content = data['choices'][0]['message']['content'];
        
        // Parse the content JSON
        final Map<String, dynamic> parsedContent = jsonDecode(content);
        
        return OpenAIResponse(
          mode: parsedContent['mode'] ?? 'unknown',
          confidence: parsedContent['confidence'] ?? 0.0,
          response: parsedContent['response'] ?? "I'm not sure what you want me to do.",
          additionalInfo: parsedContent['additionalInfo'] ?? {},
        );
      } else {
        debugPrint('OpenAI API Error: ${response.statusCode} - ${response.body}');
        return OpenAIResponse.error("I couldn't process that request right now.");
      }
    } catch (e) {
      debugPrint('OpenAI Service Error: $e');
      return OpenAIResponse.error("Sorry, I encountered an error processing your request.");
    }
  }
}

/// Class to represent structured responses from OpenAI
class OpenAIResponse {
  final String mode;
  final double confidence;
  final String response;
  final Map<String, dynamic> additionalInfo;
  final bool isError;

  OpenAIResponse({
    required this.mode,
    required this.confidence,
    required this.response,
    required this.additionalInfo,
    this.isError = false,
  });

  /// Factory constructor for error responses
  factory OpenAIResponse.error(String errorMessage) {
    return OpenAIResponse(
      mode: 'unknown',
      confidence: 0.0,
      response: errorMessage,
      additionalInfo: {},
      isError: true,
    );
  }

  /// Check if the confidence level is high enough to proceed
  bool get isConfident => confidence > 0.7;

  @override
  String toString() {
    return 'OpenAIResponse{mode: $mode, confidence: $confidence, response: $response}';
  }
}