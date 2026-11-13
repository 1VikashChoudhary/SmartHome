import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smarthome_app/presentation/screens/about_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('AboutScreen renders app title, developer, PayPal and UPI sponsorship info', (tester) async {
    tester.view.physicalSize = const Size(1080, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final log = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (MethodCall methodCall) async {
      log.add(methodCall);
      return null;
    });

    await tester.pumpWidget(
      const MaterialApp(
        home: AboutScreen(),
      ),
    );
    await tester.pumpAndSettle();

    // Verify Title & Brand & Logo
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('About & Sponsorship'), findsOneWidget);
    expect(find.text('SmartHome Pro'), findsOneWidget);
    expect(find.text('v1.0.0 Stable'), findsOneWidget);
    expect(find.text('100% Local-First'), findsOneWidget);

    // Verify Developer
    expect(find.text(AboutScreen.developerName), findsOneWidget);

    // Verify Sponsorship Section
    expect(find.text('SPONSOR & SUPPORT PROJECT'), findsOneWidget);

    // Verify UPI info
    expect(find.text('India • UPI Payment'), findsOneWidget);
    expect(find.text(AboutScreen.upiId), findsOneWidget);
    expect(find.text('Google Pay'), findsOneWidget);
    expect(find.text('PhonePe'), findsOneWidget);
    expect(find.text('Paytm'), findsOneWidget);

    // Verify PayPal info
    expect(find.text('International • PayPal'), findsOneWidget);
    expect(find.text(AboutScreen.paypalUrl), findsOneWidget);
    expect(find.text('Donate via PayPal.Me'), findsOneWidget);

    // Test copying UPI ID
    final copyUpiBtn = find.widgetWithText(OutlinedButton, 'Copy ID');
    expect(copyUpiBtn, findsOneWidget);
    await tester.tap(copyUpiBtn);
    await tester.pumpAndSettle();

    expect(log.any((call) => call.method == 'Clipboard.setData' && call.arguments['text'] == AboutScreen.upiId), isTrue);
    expect(find.text('Copied'), findsOneWidget);

    // Advance past the 3-second reset timer
    await tester.pump(const Duration(seconds: 4));
    expect(find.text('Copy ID'), findsOneWidget);
  });
}
