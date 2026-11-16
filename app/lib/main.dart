import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';
import 'presentation/screens/home_screen.dart';
import 'presentation/screens/controllers_screen.dart';
import 'presentation/screens/automations_screen.dart';
import 'presentation/screens/analytics_screen.dart';
import 'presentation/screens/device_screen.dart';
import 'presentation/widgets/emergency_alarm_dialog.dart';
import 'presentation/widgets/quick_controls_sheet.dart';
import 'services/device_manager.dart';
import 'services/native_controls_service.dart';

class NavigationIndexNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void setIndex(int index) => state = index;
}

final navigationIndexProvider = NotifierProvider<NavigationIndexNotifier, int>(
  NavigationIndexNotifier.new,
);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: SmartHomeApp()));
}

class SmartHomeApp extends ConsumerWidget {
  const SmartHomeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp(
      title: 'SmartHome Pro',
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeAnimationDuration: Duration.zero,
      builder: (context, child) {
        final platformBrightness = MediaQuery.of(context).platformBrightness;
        final isDark =
            themeMode == ThemeMode.dark ||
            (themeMode == ThemeMode.system &&
                platformBrightness == Brightness.dark);
        AppColors.isDark = isDark;
        return child!;
      },
      home: const MainShell(),
    );
  }
}

class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell>
    with WidgetsBindingObserver {
  late final DeviceManager _deviceManager;

  static const List<Widget> _screens = [
    HomeScreen(),
    ControllersScreen(),
    AutomationsScreen(),
    AnalyticsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _deviceManager = ref.read(deviceManagerProvider.notifier);
    WidgetsBinding.instance.addObserver(this);
    NativeControlsService.instance.setLaunchActionListener(_handleLaunchAction);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final pending = await NativeControlsService.instance.consumeLaunchAction();
      if (pending != null && mounted) {
        _handleLaunchAction(pending);
      }
    });
  }

  void _handleLaunchAction(NativeLaunchAction action) {
    if (!mounted) return;
    if (action.tileSlot != null) {
      QuickControlsSheet.show(context, initialSlot: action.tileSlot);
      return;
    }
    final devId = action.deviceId;
    if (devId != null && devId.isNotEmpty) {
      final exists = ref.read(deviceManagerProvider).any((d) => d.id == devId);
      if (exists) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => DeviceScreen(deviceId: devId)),
        );
      }
    }
  }

  @override
  void dispose() {
    NativeControlsService.instance.setLaunchActionListener(null);
    WidgetsBinding.instance.removeObserver(this);
    _deviceManager.stopForegroundSync();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _deviceManager.startForegroundSync();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _deviceManager.stopForegroundSync();
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<EmergencyAlarmEvent?>(emergencyAlarmProvider, (prev, next) {
      if (next == null) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          EmergencyAlarmDialog.show(
            context,
            ref,
            deviceId: next.deviceId,
            alarmType: next.alarmType,
          );
        }
      });
    });

    final currentIndex = ref.watch(navigationIndexProvider);
    final themeMode = ref.watch(themeModeProvider);
    final platformBrightness = MediaQuery.of(context).platformBrightness;
    final isDark =
        themeMode == ThemeMode.dark ||
        (themeMode == ThemeMode.system &&
            platformBrightness == Brightness.dark);
    AppColors.isDark = isDark;

    final navSurfaceColor = isDark
        ? const Color(0xFF111726)
        : const Color(0xFFFFFFFF);
    final navBorderColor = isDark
        ? const Color(0x1FFFFFFF)
        : const Color(0xFFE2E8F0);
    final selectedIconColor = isDark
        ? const Color(0xFF818CF8)
        : const Color(0xFF4F46E5);
    final unselectedIconColor = isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF64748B);
    final indicatorColor = isDark
        ? const Color(0x336366F1)
        : const Color(0x204F46E5);

    final overlayStyle = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: navSurfaceColor,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarIconBrightness: isDark
          ? Brightness.light
          : Brightness.dark,
      systemNavigationBarContrastEnforced: false,
    );

    final navBarWidget = Container(
      decoration: BoxDecoration(
        color: navSurfaceColor,
        border: Border(top: BorderSide(color: navBorderColor, width: 1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.05),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: NavigationBar(
          selectedIndex: currentIndex,
          backgroundColor: navSurfaceColor,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          indicatorColor: indicatorColor,
          onDestinationSelected: (idx) =>
              ref.read(navigationIndexProvider.notifier).setIndex(idx),
          destinations: [
            NavigationDestination(
              icon: Icon(Icons.dashboard_outlined, color: unselectedIconColor),
              selectedIcon: Icon(
                Icons.dashboard_rounded,
                color: selectedIconColor,
              ),
              label: 'Dashboard',
            ),
            NavigationDestination(
              icon: Icon(Icons.hub_outlined, color: unselectedIconColor),
              selectedIcon: Icon(Icons.hub_rounded, color: selectedIconColor),
              label: 'Controllers',
            ),
            NavigationDestination(
              icon: Icon(Icons.auto_mode_outlined, color: unselectedIconColor),
              selectedIcon: Icon(
                Icons.auto_mode_rounded,
                color: selectedIconColor,
              ),
              label: 'Automations',
            ),
            NavigationDestination(
              icon: Icon(Icons.insights_outlined, color: unselectedIconColor),
              selectedIcon: Icon(
                Icons.insights_rounded,
                color: selectedIconColor,
              ),
              label: 'Monitoring',
            ),
          ],
        ),
      ),
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: Scaffold(
        backgroundColor: isDark
            ? const Color(0xFF090D16)
            : const Color(0xFFF8FAFC),
        body: IndexedStack(index: currentIndex, children: _screens),
        bottomNavigationBar: navBarWidget,
      ),
    );
  }
}
