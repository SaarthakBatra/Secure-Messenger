import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../modules/mobile/lib/features/cover/screens/decoy_home_screen.dart';
import '../../../modules/mobile/lib/features/cover/screens/offline_translation_screen.dart';
import '../../../modules/mobile/lib/features/cover/screens/report_issue_form_screen.dart';
import '../../../modules/mobile/lib/features/cover/screens/decoy_settings_screen.dart';
import '../../../modules/mobile/lib/features/cover/providers/issue_report_provider.dart';
import '../../../modules/mobile/lib/features/cover/providers/streak_provider.dart';
import '../../../modules/mobile/lib/features/cover/providers/word_of_day_provider.dart';
import '../../../modules/mobile/lib/features/cover/services/wotd_sync_service.dart';

void main() {
  group('DecoyHomeScreen Widget Tests', () {
    testWidgets('Normal Flow: Home screen renders logo, streak, and WOTD successfully', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: DecoyHomeScreen(),
          ),
        ),
      );

      // Verify the transparent legacy text finder exists
      expect(find.text('Home'), findsOneWidget);

      // Verify the MultiLingo logo branding exists
      expect(find.text('MultiLingo'), findsOneWidget);

      // Verify the Streak badge shows the default streak (0 Days initially since not overridden)
      expect(find.text('0 Days'), findsOneWidget);

      // Verify the Quick Actions and Learning Path render
      expect(find.text('Phrase Translator'), findsOneWidget);
      expect(find.text('My Learning Path'), findsOneWidget);
      expect(find.text('Continue Learning'), findsOneWidget);

      // Pump to let the WOTD FutureProvider load its mock test data
      await tester.pumpAndSettle();

      // Check WOTD loads successfully and displays welcome details
      expect(find.text('welcome'), findsOneWidget);
      expect(find.text('bienvenido'), findsOneWidget);
      expect(find.text('Greeting someone in a polite or friendly way.'), findsOneWidget);
    });

    testWidgets('Edge Case: Stealth Hook triggers callback only after 3-second long press', (WidgetTester tester) async {
      bool callbackFired = false;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            coverLogoLongPressCallbackProvider.overrideWithValue(() {
              callbackFired = true;
            }),
          ],
          child: const MaterialApp(
            home: DecoyHomeScreen(),
          ),
        ),
      );

      expect(callbackFired, isFalse);

      final logoFinder = find.byKey(const Key('stealth_logo_button'));
      expect(logoFinder, findsOneWidget);

      // Simulate tapping down on the logo to initiate the custom long-press timer
      final TestGesture gesture = await tester.startGesture(tester.getCenter(logoFinder));
      await tester.pump();

      // Pump for 2 seconds (2000 milliseconds) - callback should NOT fire yet
      await tester.pump(const Duration(seconds: 2));
      expect(callbackFired, isFalse);

      // Pump for another 1.1 seconds (1100 milliseconds, total 3.1 seconds) - callback should fire!
      await tester.pump(const Duration(milliseconds: 1100));
      expect(callbackFired, isTrue);

      // Release the finger
      await gesture.up();
      await tester.pump();
    });

    testWidgets('Conversations: Tapping a conversational card flips to reveal translation', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: DecoyHomeScreen(),
          ),
        ),
      );

      // Verify library card exists in English
      expect(find.text('Excuse me, where is the library?'), findsOneWidget);
      expect(find.text('Disculpe, ¿dónde está la biblioteca?'), findsNothing);

      // Tap to flip
      await tester.tap(find.text('Excuse me, where is the library?'));
      await tester.pump();

      // Now verify translation is shown
      expect(find.text('Disculpe, ¿dónde está la biblioteca?'), findsOneWidget);
    });

    testWidgets('Interactive Lesson Flow: Tapping Continue Learning opens vocab, quiz, and results phases', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: DecoyHomeScreen(),
          ),
        ),
      );

      // Verify starting progress at 340 XP
      expect(find.text('340 / 500 XP'), findsOneWidget);

      // Launch overlay dialog
      await tester.tap(find.text('Continue Learning'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500)); // Dialog opens

      // Modal open, verify phase 1
      expect(find.text('Vocab Flashcards'), findsOneWidget);
      expect(find.text('Vocab 1/10'), findsOneWidget);

      // Tap card to flip
      await tester.tap(find.text('Tap to reveal'));
      await tester.pump();
      expect(find.text('SPANISH TRANSLATION'), findsOneWidget);

      // Study all 10 cards
      for (int i = 0; i < 9; i++) {
        await tester.tap(find.text('Next Word'));
        await tester.pump();
      }

      // Proceed to quiz
      await tester.tap(find.text('Proceed to Quiz'));
      await tester.pump();

      // Phase 2: Quiz
      expect(find.text('UNIT MINI-QUIZ'), findsOneWidget);
      expect(find.text('Quiz 1/5'), findsOneWidget);

      // Answer all 5 questions
      for (int i = 0; i < 5; i++) {
        await tester.tap(find.text('A.'));
        await tester.pump();
        await tester.tap(find.text('Check Answer'));
        await tester.pump();

        final buttonLabel = (i == 4) ? 'Finish Quiz' : 'Next Question';
        await tester.tap(find.text(buttonLabel));
        await tester.pump();
      }

      // Phase 3: Results
      expect(find.text('Lesson Completed!'), findsOneWidget);

      // Return to dashboard
      await tester.tap(find.text('Return to Dashboard'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500)); // Dialog closes

      // Verify back on main dashboard and modal is removed from tree
      expect(find.text('Vocab Flashcards'), findsNothing);
    });
  });

  group('OfflineTranslationScreen Widget Tests', () {
    testWidgets('Normal Flow: Phrase translator renders inputs, swaps languages, and handles debounced queries successfully', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: OfflineTranslationScreen(),
          ),
        ),
      );

      // Verify the translation interface builds successfully
      expect(find.text('Phrase Translator'), findsOneWidget);
      expect(find.text('Hybrid Mode'), findsOneWidget);
      expect(find.text('🇬🇧 English'), findsOneWidget);
      expect(find.text('🇪🇸 Spanish'), findsOneWidget);
      
      // Verify initial empty state graphic
      expect(find.text('Your translation will appear here'), findsOneWidget);

      // Type text into the phrase input field
      final textField = find.byType(TextField);
      expect(textField, findsOneWidget);
      await tester.enterText(textField, 'hello');
      await tester.pump();

      // Debounce delay (500ms) - pump 600ms
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      // Verify translation has completed (mock translationSearchProvider returns 'hola' in tests!)
      expect(find.text('SPANISH TRANSLATION'), findsOneWidget);
      expect(find.text('hola'), findsOneWidget);

      // Swap languages
      final swapBtn = find.byIcon(Icons.swap_horiz_rounded);
      expect(swapBtn, findsOneWidget);
      await tester.tap(swapBtn);
      await tester.pump();
      await tester.pumpAndSettle(); // Resolve new Riverpod family Future!

      // Verify languages swapped internally (query translates 'hello' Spanish to English -> mock still 'hola')
      expect(find.text('ENGLISH TRANSLATION'), findsOneWidget);

      // Tap clear button to reset input
      final clearBtn = find.byIcon(Icons.clear_rounded);
      expect(clearBtn, findsOneWidget);
      await tester.tap(clearBtn);
      await tester.pump();

      // Verify empty state graphic is shown again
      expect(find.text('Your translation will appear here'), findsOneWidget);
    });

    testWidgets('Interactive Chips: Tapping a phrase chip fills the text input and triggers translation', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: OfflineTranslationScreen(),
          ),
        ),
      );

      final chipFinder = find.text('Hello, my friend!');
      expect(chipFinder, findsOneWidget);

      // Ensure the chip is scrolled into view before tapping to avoid hit-test viewport truncation
      await tester.ensureVisible(chipFinder);
      await tester.pump();

      // Tap chip
      await tester.tap(chipFinder);
      await tester.pump();

      // Verify input text is filled inside the TextField
      expect(
        find.descendant(of: find.byType(TextField), matching: find.text('Hello, my friend!')),
        findsOneWidget,
      );

      // Wait for debouncer
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      // Verify translation renders
      expect(find.text('SPANISH TRANSLATION'), findsOneWidget);
      expect(find.text('hola'), findsOneWidget);
    });
  });

  group('ReportIssueFormScreen Widget Tests', () {
    testWidgets('Validation and Submission Flow: Report issue form validates fields, shows loading spinner, and displays success state', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: ReportIssueFormScreen(),
          ),
        ),
      );

      // Verify the interface components render successfully
      expect(find.text('Report an Issue'), findsOneWidget);
      expect(find.text('Category of Issue'), findsOneWidget);
      expect(find.text('Attach System Diagnostics'), findsOneWidget);
      
      final submitBtn = find.text('Submit Error Report');
      expect(submitBtn, findsOneWidget);

      // Scroll submit button into view
      await tester.ensureVisible(submitBtn);
      await tester.pump();

      // 1. Submit empty form - triggers validation error
      await tester.tap(submitBtn);
      await tester.pump();

      expect(find.text('Please describe the issue'), findsOneWidget);

      // 2. Enter too short description - triggers length validation error
      final textFields = find.byType(TextFormField);
      expect(textFields, findsNWidgets(2));
      final textFormField = textFields.last;
      
      await tester.enterText(textFormField, 'short');
      await tester.pump();

      // Scroll submit button into view again
      await tester.ensureVisible(submitBtn);
      await tester.pump();

      await tester.tap(submitBtn);
      await tester.pump();

      expect(find.text('Please write at least 10 characters'), findsOneWidget);

      // 3. Enter a valid description and submit
      await tester.enterText(textFormField, 'The translation for welcome is incorrect in context.');
      await tester.pump();

      // Scroll submit button into view again
      await tester.ensureVisible(submitBtn);
      await tester.pump();

      await tester.tap(submitBtn);
      await tester.pump();

      // Verify the submission loading overlay is rendered
      expect(find.text('Uploading Diagnostic Package...'), findsOneWidget);

      // Pump 2 seconds to complete the diagnostic upload timer
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();

      // Verify success screen is displayed
      expect(find.text('Report Filed successfully!'), findsOneWidget);
      expect(find.text('Return to Dashboard'), findsOneWidget);

      // Click return to close screen
      await tester.tap(find.text('Return to Dashboard'));
      await tester.pump();
    });

    testWidgets('Error Code Hook in Report Form: Entering an error code saves it to issueReportProvider successfully', (WidgetTester tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: ReportIssueFormScreen(),
          ),
        ),
      );

      // Verify Error Code field renders
      expect(find.text('Error Code (optional)'), findsOneWidget);
      
      final textFields = find.byType(TextFormField);
      // Wait, there are now two TextFormFields: one for error code, one for description!
      // In ReportIssueFormScreen, the first is error code, the second is description.
      expect(textFields, findsNWidgets(2));

      // Enter error code in the first text field
      await tester.enterText(textFields.first, 'SEC-GATEWAY-112');
      await tester.enterText(textFields.last, 'The word goodbye is translated as hola instead of adios.');
      await tester.pump();

      // Submit form
      final submitBtn = find.text('Submit Error Report');
      await tester.ensureVisible(submitBtn);
      await tester.pump();
      await tester.tap(submitBtn);
      await tester.pump();

      // Wait 2 seconds for submit mock timer
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();

      // Verify the issueReportProvider holds the correct code and body now!
      expect(container.read(issueReportProvider).code, 'SEC-GATEWAY-112');
      expect(container.read(issueReportProvider).body, 'The word goodbye is translated as hola instead of adios.');
    });

    testWidgets('Error Code Hook in Report Form: Entering a 6-digit error code bypasses description validation', (WidgetTester tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: ReportIssueFormScreen(),
          ),
        ),
      );

      final textFields = find.byType(TextFormField);
      expect(textFields, findsNWidgets(2));

      // Enter exactly 6 digits in the error code field and leave description blank
      await tester.enterText(textFields.first, '123456');
      await tester.enterText(textFields.last, '');
      await tester.pump();

      // Submit form
      final submitBtn = find.text('Submit Error Report');
      await tester.ensureVisible(submitBtn);
      await tester.pump();
      await tester.tap(submitBtn);
      await tester.pump();

      // Ensure no validation error text is displayed
      expect(find.text('Please describe the issue'), findsNothing);
      expect(find.text('Please write at least 10 characters'), findsNothing);

      // Verify loading overlay appears (submission started)
      expect(find.text('Uploading Diagnostic Package...'), findsOneWidget);

      // Verify provider state
      expect(container.read(issueReportProvider).code, '123456');
      expect(container.read(issueReportProvider).body, '');
    });
  });

  group('DecoySettingsScreen Widget Tests', () {
    testWidgets('Save Settings Flow: Modifying goals and diagnostics code updates issueReportProvider state and shows a SnackBar', (WidgetTester tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: DecoySettingsScreen(),
          ),
        ),
      );

      // Verify settings page components render successfully
      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Dark Mode Theme'), findsOneWidget);
      expect(find.text('Sound Effects'), findsOneWidget);
      expect(find.text('Daily Reminders'), findsOneWidget);
      expect(find.text('System Diagnostics & Codes'), findsOneWidget);

      // Enter diagnostic reference code
      final diagField = find.byType(TextFormField);
      expect(diagField, findsOneWidget);
      await tester.enterText(diagField, 'SEC-BYPASS-007');
      await tester.pump();

      // Tap save settings button
      final saveBtn = find.text('Save Settings');
      expect(saveBtn, findsOneWidget);
      
      await tester.ensureVisible(saveBtn);
      await tester.pump();
      await tester.tap(saveBtn);
      await tester.pump();

      // Verify snackbar feedback
      expect(find.text('Settings saved successfully!'), findsOneWidget);

      // Verify the issueReportProvider state is updated!
      expect(container.read(issueReportProvider).code, 'SEC-BYPASS-007');
      expect(container.read(issueReportProvider).body, '');
    });
  });
}
