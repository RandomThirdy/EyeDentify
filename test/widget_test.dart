// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:camera/camera.dart';
import 'package:eye_dentify/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    // Create mock cameras for testing
    final mockCameras = [
      CameraDescription(
        name: 'mock_camera',
        lensDirection: CameraLensDirection.back,
        sensorOrientation: 0,
      ),
    ];

    // Build our app and trigger a frame.
    await tester.pumpWidget(MyApp(cameras: mockCameras));

    // Verify that the app title is displayed
    expect(find.text('EyeDentify - Accessibility App'), findsOneWidget);
    
    // Verify that the main title is displayed
    expect(find.text('EyeDentify'), findsOneWidget);
    
    // Verify that the subtitle is displayed
    expect(find.text('Your voice-controlled assistant'), findsOneWidget);
  });
}
