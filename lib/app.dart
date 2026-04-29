import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/theme.dart';
import 'features/scan/scan_page.dart';
import 'features/scan/scan_provider.dart';
import 'features/history/history_page.dart';
import 'features/history/history_provider.dart';
import 'features/stats/stats_page.dart';
import 'features/stats/stats_provider.dart';
import 'features/subscription/subscription_page.dart';
import 'features/subscription/subscription_provider.dart';
import 'features/auth/auth_provider.dart';

class ScanOrderApp extends StatelessWidget {
  const ScanOrderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ScanProvider()),
        ChangeNotifierProvider(create: (_) => HistoryProvider()),
        ChangeNotifierProvider(create: (_) => StatsProvider()),
        ChangeNotifierProvider(create: (_) => SubscriptionProvider()),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
      ],
      child: MaterialApp(
        title: 'ScanOrder',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.system,
        home: const MainShell(),
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
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 150),
        child: _pages[_currentIndex],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) {
          setState(() => _currentIndex = i);
          // Refresh data when switching tabs
          if (i == 1) {
            context.read<HistoryProvider>().refresh();
          } else if (i == 2) {
            context.read<StatsProvider>().loadStats();
          } else if (i == 3) {
            context.read<SubscriptionProvider>().loadStatus();
          }
        },
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
            label: 'Pro',
          ),
        ],
      ),
    );
  }
}
