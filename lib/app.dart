import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/theme.dart';
import 'core/supabase/supabase_service.dart';
import 'features/scan/scan_page.dart';
import 'features/scan/scan_provider.dart';
import 'features/history/history_page.dart';
import 'features/history/history_provider.dart';
import 'features/stats/stats_page.dart';
import 'features/stats/stats_provider.dart';
import 'features/subscription/subscription_page.dart';
import 'features/subscription/subscription_provider.dart';
import 'features/settings/settings_page.dart';
import 'features/settings/settings_provider.dart';
import 'features/auth/auth_provider.dart';

class ScanOrderApp extends StatelessWidget {
  const ScanOrderApp({super.key});

  static ThemeMode _getThemeMode(String mode) {
    switch (mode) {
      case 'light': return ThemeMode.light;
      case 'dark': return ThemeMode.dark;
      default: return ThemeMode.system;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ScanProvider()),
        ChangeNotifierProvider(create: (_) => HistoryProvider()),
        ChangeNotifierProvider(create: (_) => StatsProvider()),
        ChangeNotifierProvider(create: (_) => SubscriptionProvider()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
      ],
      child: Consumer<SettingsProvider>(
        builder: (_, settings, _) => MaterialApp(
          title: 'ScanOrder',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: _getThemeMode(settings.darkMode),
          home: const MainShell(),
        ),
      ),
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;

  final _pages = [
    const ScanPage(key: PageStorageKey('scan')),
    const HistoryPage(key: PageStorageKey('history')),
    const StatsPage(key: PageStorageKey('stats')),
    const SubscriptionPage(key: PageStorageKey('subscription')),
    const SettingsPage(key: PageStorageKey('settings')),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = context.read<AuthProvider>();
      auth.addListener(_onAuthChange);
      _syncUserId(auth);
      context.read<SettingsProvider>().loadSettings();
    });
  }

  void _onAuthChange() {
    final auth = context.read<AuthProvider>();
    _syncUserId(auth);
  }

  void _syncUserId(AuthProvider auth) {
    final userId = SupabaseService().currentUser?.id;
    context.read<HistoryProvider>().setUserId(userId);
    context.read<HistoryProvider>().refresh();
    context.read<ScanProvider>().loadCounts();
    context.read<SubscriptionProvider>().loadStatus();
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 700;

    return Scaffold(
      body: Row(
        children: [
          if (isWide)
            NavigationRail(
              selectedIndex: _currentIndex,
              onDestinationSelected: _selectPage,
              labelType: NavigationRailLabelType.all,
              minWidth: 88,
              destinations: const [
                NavigationRailDestination(
                  icon: Icon(Icons.qr_code_scanner_outlined),
                  selectedIcon: Icon(Icons.qr_code_scanner),
                  label: Text('Scan'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.history_outlined),
                  selectedIcon: Icon(Icons.history),
                  label: Text('Riwayat'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.bar_chart_outlined),
                  selectedIcon: Icon(Icons.bar_chart),
                  label: Text('Statistik'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.workspace_premium_outlined),
                  selectedIcon: Icon(Icons.workspace_premium),
                  label: Text('Info Paket'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.settings_outlined),
                  selectedIcon: Icon(Icons.settings),
                  label: Text('Settings'),
                ),
              ],
            ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 150),
              child: _pages[_currentIndex],
            ),
          ),
        ],
      ),
      bottomNavigationBar: isWide
          ? null
          : NavigationBar(
              height: 60,
              selectedIndex: _currentIndex,
              onDestinationSelected: _selectPage,
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.qr_code_scanner_outlined),
                  selectedIcon: Icon(Icons.qr_code_scanner),
                  label: 'Scan',
                ),
                NavigationDestination(
                  icon: Icon(Icons.history_outlined),
                  selectedIcon: Icon(Icons.history),
                  label: 'Riwayat',
                ),
                NavigationDestination(
                  icon: Icon(Icons.bar_chart_outlined),
                  selectedIcon: Icon(Icons.bar_chart),
                  label: 'Statistik',
                ),
                NavigationDestination(
                  icon: Icon(Icons.workspace_premium_outlined),
                  selectedIcon: Icon(Icons.workspace_premium),
                  label: 'Info Paket',
                ),
                NavigationDestination(
                  icon: Icon(Icons.settings_outlined),
                  selectedIcon: Icon(Icons.settings),
                  label: 'Settings',
                ),
              ],
            ),
    );
  }

  void _selectPage(int i) {
    setState(() => _currentIndex = i);
    if (i == 1) {
      context.read<HistoryProvider>().refresh();
    } else if (i == 2) {
      context.read<StatsProvider>().loadStats();
    } else if (i == 3) {
      context.read<SubscriptionProvider>().loadStatus();
    } else if (i == 4) {
      context.read<SettingsProvider>().loadSettings();
    }
  }
}
