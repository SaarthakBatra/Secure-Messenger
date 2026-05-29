import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// Since we cannot easily import absolute paths in this isolated snippet context without a proper package name setup,
// we will simulate the imports or use relative paths if applicable. For tests within `tests/mobile/scaffold/`,
// they'd usually import from `package:mobile/app/router/app_router.dart` and `package:mobile/main.dart`.
// We'll define the test logic assuming those imports are available, or test against isolated ProviderContainers.

// In a real project, these would be:
// import 'package:mobile/app/router/app_router.dart';
// import 'package:mobile/main.dart';
// For the sake of this test script running in isolation or via orchestrated script, we mock the app.

// Mocking the router logic directly for test validation as required by the test-spec:
import '../../../modules/mobile/lib/app/router/app_router.dart';
import '../../../modules/mobile/lib/main.dart';

void main() {
  group('Router Scaffold Tests', () {
    testWidgets('Normal Workflow: App boots and router initializes without errors', (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPrefsOnboardingProvider.overrideWith((ref) => true),
          ],
          child: const MultiLingoApp(),
        ),
      );
      
      expect(find.byType(MaterialApp), findsOneWidget);
    });

    testWidgets('Edge Case 1 (First Launch): Routes to /onboarding if has_completed_onboarding is null/false', (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPrefsOnboardingProvider.overrideWith((ref) => false),
          ],
          child: const MultiLingoApp(),
        ),
      );
      
      await tester.pumpAndSettle();
      
      // Should find the Onboarding text
      expect(find.text('Onboarding'), findsOneWidget);
    });

    testWidgets('Edge Case 2 (Subsequent Launch): Routes to /home if has_completed_onboarding is true', (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPrefsOnboardingProvider.overrideWith((ref) => true),
          ],
          child: const MultiLingoApp(),
        ),
      );
      
      await tester.pumpAndSettle();
      
      // Should find the Home text
      expect(find.text('Home'), findsOneWidget);
    });

    testWidgets('Edge Case 3 (Vault Guarding): Redirects to /home if vault is accessed without active session', (WidgetTester tester) async {
      final container = ProviderContainer(
        overrides: [
          sharedPrefsOnboardingProvider.overrideWith((ref) => true),
        ],
      );
      
      final router = container.read(appRouterProvider);
      
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            routerConfig: router,
          ),
        ),
      );
      
      await tester.pumpAndSettle();
      
      // Navigate to vault
      router.go('/vault');
      await tester.pumpAndSettle();
      
      // Because vaultSessionProvider is false, the redirect should bounce it back to /home
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Vault Home'), findsNothing);
    });
  });
}
