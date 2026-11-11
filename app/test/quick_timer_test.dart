import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smarthome_app/presentation/widgets/quick_timer_sheet.dart';

void main() {
  group('QuickTimerSheet Widget Tests', () {
    testWidgets('Defaults to Delay Turn ON when relay is OFF', (tester) async {
      String? recordedAction;
      int? recordedSeconds;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QuickTimerSheet(
              relayName: 'Fan',
              currentState: false, // OFF
              onStartTimer: (action, sec) {
                recordedAction = action;
                recordedSeconds = sec;
              },
            ),
          ),
        ),
      );

      // Verify header and mode chips
      expect(find.text('Quick Timer: Fan'), findsOneWidget);
      expect(find.text('Auto Turn OFF'), findsOneWidget);
      expect(find.text('Delay Turn ON'), findsOneWidget);

      // Tap 5m preset chip
      await tester.tap(find.text('5m'));
      await tester.pumpAndSettle();

      // Find Start button and tap it
      final startBtn = find.text('Start Turn-ON Timer (5m)');
      expect(startBtn, findsOneWidget);
      await tester.tap(startBtn);
      await tester.pumpAndSettle();

      expect(recordedAction, equals('on'));
      expect(recordedSeconds, equals(300));
    });

    testWidgets('Defaults to Auto Turn OFF (off) when relay is ON', (tester) async {
      String? recordedAction;
      int? recordedSeconds;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QuickTimerSheet(
              relayName: 'Light',
              currentState: true, // ON
              onStartTimer: (action, sec) {
                recordedAction = action;
                recordedSeconds = sec;
              },
            ),
          ),
        ),
      );

      expect(find.text('Auto Turn OFF'), findsOneWidget);
      expect(find.text('Delay Turn ON'), findsOneWidget);

      // Tap 30m preset chip
      await tester.tap(find.text('30m'));
      await tester.pumpAndSettle();

      final startBtn = find.text('Start Turn-OFF Timer (30m)');
      expect(startBtn, findsOneWidget);
      await tester.tap(startBtn);
      await tester.pumpAndSettle();

      expect(recordedAction, equals('off'));
      expect(recordedSeconds, equals(1800));
    });

    testWidgets('Tapping presets synchronizes hours and minutes without error', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QuickTimerSheet(
              relayName: 'Fan',
              currentState: false,
              onStartTimer: (action, sec) {},
            ),
          ),
        ),
      );

      // Tap 1h preset
      await tester.tap(find.text('1h'));
      await tester.pumpAndSettle();

      expect(find.text('Start Turn-ON Timer (1h)'), findsOneWidget);

      // Tap 2h preset
      await tester.tap(find.text('2h'));
      await tester.pumpAndSettle();

      expect(find.text('Start Turn-ON Timer (2h)'), findsOneWidget);
    });
  });
}
