import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'core/theme.dart';
import 'core/supabase/supabase_service.dart';
import 'core/l10n/app_localizations.dart';
import 'core/monitoring/monitoring_service.dart';
import 'core/logging/logger.dart';
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
import 'features/splash/splash_screen.dart';
import 'features/splash/onboarding_screen.dart';

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
      child: Consumer2<SettingsProvider, AuthProvider>(
        builder: (_, settings, auth, __) {
          final locale = auth.currentLocale != null 
              ? Locale(auth.currentLocale!) 
              : const Locale('id');
          
          return MaterialApp(
            title: 'ScanOrder',
            debugShowCheckedModeBanner: false,
            locale: locale,
            supportedLocales: kSupportedLocales,
            localizationsDelegates: [
              AppLocalizationsDelegate(locale),
              ...GlobalMaterialLocalizations.delegates,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: _getThemeMode(settings.darkMode),
            home: const _AppEntry(),
          );
        },
      ),
    );
  }
}

/// Decides entry: SplashScreen → OnboardingScreen (first time) or MainShell
class _AppEntry extends StatefulWidget {
  const _AppEntry();

  @override
  State<_AppEntry> createState() => _AppEntryState();
}

class _AppEntryState extends State<_AppEntry> {
  bool? _showOnboarding;

  @override
  void initState() {
    super.initState();
    _checkOnboarding();
  }

  Future<void> _checkOnboarding() async {
    final show = await shouldShowOnboarding();
    if (mounted) setState(() => _showOnboarding = show);
  }

  @override
  Widget build(BuildContext context) {
    if (_showOnboarding == null) {
      // Still loading — show splash
      return SplashScreen(
        next: const SizedBox.shrink(),
      );
    }
    if (_showOnboarding!) {
      // First time — splash → onboarding → main
      return SplashScreen(
        next: OnboardingScreen(next: const MainShell()),
      );
    }
    // Returning user — splash → main
    return SplashScreen(next: const MainShell());
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with WidgetsBindingObserver {
  int _currentIndex = 0;
  // Sentinel values so first _syncUserId always detects a change
  String? _lastSyncedUserId = '<init>';
  String? _lastSyncedTeamId = '<init>';

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
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = context.read<AuthProvider>();
      auth.addListener(_onAuthChange);
      _syncUserId(auth);
      context.read<SettingsProvider>().loadSettings();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    try { context.read<AuthProvider>().removeListener(_onAuthChange); } catch (_) {}
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Check session validity when app comes to foreground
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.read<AuthProvider>().checkSessionOnResume();
      });
    }
  }

  void _onAuthChange() {
    final auth = context.read<AuthProvider>();
    _syncUserId(auth);
  }

  void _syncUserId(AuthProvider auth) {
    final userId = SupabaseService().currentUser?.id;
    final team = auth.currentTeam;
    final isAdmin = auth.isAdmin;
    final teamId = team?.id;
    final adminUserId = isAdmin ? null : team?.createdBy;

    // Skip refresh if nothing changed — prevents infinite loop from authStateChanges
    final changed = userId != _lastSyncedUserId || teamId != _lastSyncedTeamId;
    _lastSyncedUserId = userId;
    _lastSyncedTeamId = teamId;

    AppLogger.info('App', '_syncUserId: userId=$userId, teamId=$teamId, isAdmin=$isAdmin, adminUserId=$adminUserId, changed=$changed');
    // Set user context for crash reports
    MonitoringService.setUser(id: userId);
    context.read<HistoryProvider>().setUserId(userId);
    context.read<HistoryProvider>().setTeamContext(teamId, adminUserId);
    context.read<ScanProvider>().setTeamContext(teamId, adminUserId);
    context.read<StatsProvider>().setTeamContext(teamId, adminUserId);

    if (changed) {
      context.read<HistoryProvider>().refresh();
      context.read<ScanProvider>().loadCounts();
      context.read<StatsProvider>().loadStats();
      context.read<SubscriptionProvider>().loadStatus();
    }

    // Repair scan_categories in Supabase for team users (admin has local data)
    if (teamId != null) {
      SupabaseService().repairScanCategories();
    }
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
  }
}
