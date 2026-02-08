// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:asset_qr/main.dart';
import 'package:asset_qr/pages/auth/url_input_screen.dart';

void main() {
  testWidgets('App should show URL input screen when not logged in', (WidgetTester tester) async {
    // Mock SharedPreferences for testing
    SharedPreferences.setMockInitialValues({});
    
    // Build our app and trigger a frame
    await tester.pumpWidget(const MyApp(isLoggedIn: false));
    await tester.pumpAndSettle();

    // Verify that we're showing the URL input screen
    expect(find.byType(UrlInputScreen), findsOneWidget);
  });

  testWidgets('App should show main screen when logged in', (WidgetTester tester) async {
    // Mock SharedPreferences with logged in state
    SharedPreferences.setMockInitialValues({
      'is_logged_in': true,
    });
    
    // Build our app and trigger a frame
    await tester.pumpWidget(const MyApp(isLoggedIn: true));
    await tester.pumpAndSettle();

    // Verify that we're showing the main screen
    expect(find.byType(MainScreen), findsOneWidget);
  });
}
