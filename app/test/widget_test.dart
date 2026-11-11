import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smarthome_app/main.dart';
import 'package:smarthome_app/core/theme/app_colors.dart';
import 'package:smarthome_app/core/theme/app_theme.dart';

void main() {
  testWidgets('SmartHomeApp smoke test and dark theme verification', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: SmartHomeApp()));
    await tester.pumpAndSettle();

    expect(find.byType(SmartHomeApp), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);

    final BuildContext context = tester.element(find.byType(NavigationBar));
    final theme = Theme.of(context);

    // Verify dark theme is default and active
    expect(theme.brightness, Brightness.dark);
    expect(AppColors.isDark, isTrue);

    // Verify MaterialApp has zero theme animation duration to prevent lerp frame lag
    final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(materialApp.themeAnimationDuration, Duration.zero);
  });

  test(
    'AppTheme caches static ThemeData instances to eliminate GoogleFonts overhead',
    () {
      // Repeated access must return the exact same cached reference in memory
      final dark1 = AppTheme.darkTheme;
      final dark2 = AppTheme.darkTheme;
      expect(identical(dark1, dark2), isTrue);

      final light1 = AppTheme.lightTheme;
      final light2 = AppTheme.lightTheme;
      expect(identical(light1, light2), isTrue);
    },
  );

  testWidgets(
    'Instant theme toggling switches between Dark and Light mode seamlessly',
    (WidgetTester tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const SmartHomeApp(),
        ),
      );
      await tester.pumpAndSettle();

      expect(AppColors.isDark, isTrue);

      // Switch to Light Mode
      container.read(themeModeProvider.notifier).setTheme(ThemeMode.light);
      await tester.pump();

      expect(container.read(themeModeProvider), ThemeMode.light);
      expect(AppColors.isDark, isFalse);

      // Switch back to Dark Mode
      container.read(themeModeProvider.notifier).setTheme(ThemeMode.dark);
      await tester.pump();

      expect(container.read(themeModeProvider), ThemeMode.dark);
      expect(AppColors.isDark, isTrue);
    },
  );

  testWidgets(
    '4-Tab Bar renders Dashboard, Controllers, Automations, Monitoring',
    (WidgetTester tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const SmartHomeApp(),
        ),
      );
      await tester.pumpAndSettle();

      // Verify all 4 tab destinations exist in the NavigationBar
      expect(find.text('Dashboard'), findsOneWidget);
      expect(find.text('Controllers'), findsOneWidget);
      expect(find.text('Automations'), findsOneWidget);
      expect(find.text('Monitoring'), findsOneWidget);

      // Verify old hardware lifecycle tabs are no longer in bottom nav
      expect(find.text('OTA Update'), findsNothing);
      expect(find.text('Radar'), findsNothing);

      // Tap Controllers tab (index 1)
      await tester.tap(find.text('Controllers'));
      await tester.pumpAndSettle();
      expect(container.read(navigationIndexProvider), 1);
      expect(find.text('Controllers Hub'), findsOneWidget);

      // Tap Monitoring tab (index 3)
      await tester.tap(find.text('Monitoring'));
      await tester.pumpAndSettle();
      expect(container.read(navigationIndexProvider), 3);
      expect(find.text('LIVE CONTROLLER STATUS'), findsOneWidget);
    },
  );
}
