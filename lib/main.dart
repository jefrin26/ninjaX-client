import 'dart:async';

import 'package:flutter/material.dart';
import 'model/backend_settings.dart';
import 'model/ui_prefs.dart';
import 'view-model/alerts_view_model.dart';
import 'view-model/servers_view_model.dart';
import 'view-model/settings_view_model.dart';
import 'view/app_theme.dart';
import 'view/history_screen.dart';
import 'view/onboarding_screen.dart';
import 'view/server_detail_screen.dart';
import 'view/servers_screen.dart';
import 'view/alerts_screen.dart';
import 'view/rules_screen.dart';
import 'view/settings_screen.dart';
import 'view/widgets/ui.dart';

/// Composition root (light-first shell).
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = BackendSettings();
  await settings.load();
  final prefs = UiPrefs();
  await prefs.load();
  AppMotion.enabled = prefs.anims;
  AppDensity.compact = prefs.compact;
  final settingsVm = SettingsViewModel(settings: settings, prefs: prefs);
  runApp(MainApp(settings: settings, prefs: prefs, settingsVm: settingsVm));
}

class MainApp extends StatefulWidget {
  final BackendSettings settings;
  final UiPrefs prefs;
  final SettingsViewModel settingsVm;
  const MainApp(
      {super.key,
      required this.settings,
      required this.prefs,
      required this.settingsVm});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  int _index = 0;
  late final ServersViewModel serversVm;
  late final AlertsViewModel alertsVm;
  final _navKey = GlobalKey<NavigatorState>();
  Timer? _pollTimer;
  String _baseUrl = '';

  @override
  void initState() {
    super.initState();
    _baseUrl = widget.settings.baseUrl;
    serversVm = ServersViewModel(baseUrl: _baseUrl);
    alertsVm = AlertsViewModel(baseUrl: _baseUrl);
    widget.settings.addListener(_onBackend);
    widget.prefs.addListener(_onPrefs);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      serversVm.load();
      alertsVm.load();
      _restartPollTimer();
      if (!widget.prefs.onboardSeen && mounted) {
        _navKey.currentState?.push(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => OnboardingScreen(vm: widget.settingsVm),
          ),
        );
      }
    });
  }

  void _onBackend() {
    final next = widget.settings.baseUrl;
    if (next == _baseUrl) return;
    setState(() => _baseUrl = next);
    serversVm.updateBaseUrl(next);
    alertsVm.updateBaseUrl(next);
    serversVm.load();
    alertsVm.load();
  }

  void _onPrefs() {
    AppMotion.enabled = widget.prefs.anims;
    AppDensity.compact = widget.prefs.compact;
    _restartPollTimer();
    if (mounted) setState(() {});
  }

  void _restartPollTimer() {
    _pollTimer?.cancel();
    final sec = widget.prefs.pollSec;
    if (sec <= 0) return;
    _pollTimer = Timer.periodic(Duration(seconds: sec), (_) {
      serversVm.load();
      alertsVm.load();
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    widget.settings.removeListener(_onBackend);
    widget.prefs.removeListener(_onPrefs);
    serversVm.dispose();
    alertsVm.dispose();
    super.dispose();
  }

  void _openDetail(String id, {bool fromAlert = false}) {
    // NOTE: `context` here is above MaterialApp, so Navigator.of(context)
    // would throw. Use the app navigator key instead.
    // pollSec is snapshotted: the detail/history ECG auto force-poll
    // runs at this cadence (1s flows like a hospital monitor).
    final pollSec = widget.prefs.pollSec;
    _navKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => ServerDetailScreen(
          baseUrl: _baseUrl,
          serverId: id,
          fromAlert: fromAlert,
          pollSec: pollSec,
          onOpenHistory: (metric) => _navKey.currentState?.push(
            MaterialPageRoute(
              builder: (_) => HistoryScreen(
                  baseUrl: _baseUrl,
                  serverId: id,
                  initialMetric: metric,
                  pollSec: pollSec),
            ),
          ),
        ),
      ),
    );
  }

  void _onLongPressTab(int i) {
    final navCtx = _navKey.currentContext;
    if (navCtx == null) return;
    if (i == 0) {
      final ids = serversVm.rows.map((r) => r.id).toList();
      if (ids.isEmpty) {
        ScaffoldMessenger.of(navCtx).showSnackBar(
            const SnackBar(content: Text('No servers to poll yet')));
        return;
      }
      QuickPollSheet.show(navCtx,
          serverIds: ids, onPoll: serversVm.pollServer);
    } else if (i == 1) {
      alertsVm.markAllRead();
      ScaffoldMessenger.of(navCtx).showSnackBar(
          const SnackBar(content: Text('All alerts marked read')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.prefs,
      builder: (context, _) {
        final accent = widget.prefs.accent;
        // Light-first: explicit prefs win, system falls back to platform.
        final mode = widget.prefs.themeMode;
        if (mode == ThemeMode.light) {
          AppTheme.isLight = true;
        } else if (mode == ThemeMode.dark) {
          AppTheme.isLight = false;
        } else {
          AppTheme.isLight =
              WidgetsBinding.instance.platformDispatcher.platformBrightness ==
                  Brightness.light;
        }
        final pages = [
          ServersScreen(
            key: ValueKey('servers-$_baseUrl'),
            vm: serversVm,
            onOpenDetail: (id) => _openDetail(id),
            onOpenHistory: (id, metric) => _navKey.currentState?.push(
              MaterialPageRoute(
                builder: (_) => HistoryScreen(
                    baseUrl: _baseUrl,
                    serverId: id,
                    initialMetric: metric,
                    pollSec: widget.prefs.pollSec),
              ),
            ),
          ),
          AlertsScreen(
            key: ValueKey('alerts-$_baseUrl'),
            vm: alertsVm,
            serversVm: serversVm,
            onOpenServer: (id) => _openDetail(id, fromAlert: true),
          ),
          RulesScreen(key: ValueKey('rules-$_baseUrl'), baseUrl: _baseUrl),
          SettingsScreen(vm: widget.settingsVm),
        ];
        return MaterialApp(
          title: 'NinjaX',
          navigatorKey: _navKey,
          theme: AppTheme.light(seed: accent),
          darkTheme: AppTheme.dark(seed: accent),
          themeMode: widget.prefs.themeMode,
          builder: (context, child) {
            // Keep AppTheme statics in sync when following the system theme.
            if (widget.prefs.themeMode == ThemeMode.system) {
              final sysLight =
                  MediaQuery.of(context).platformBrightness ==
                      Brightness.light;
              if (AppTheme.isLight != sysLight) {
                // Defer write to avoid setState-during-build; next frame
                // rebuild picks it up via prefs listener / MediaQuery.
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  AppTheme.isLight = sysLight;
                  if (mounted) setState(() {});
                });
              }
            }
            return child!;
          },
          home: Scaffold(
            body: IndexedStack(index: _index, children: pages),
            bottomNavigationBar: ListenableBuilder(
              listenable: alertsVm,
              builder: (context, _) => AppTabBar(
                index: _index,
                onTap: (i) => setState(() => _index = i),
                onLongPress: _onLongPressTab,
                badge: alertsVm.unreadCount,
                items: const [
                  TabItem(Icons.dns_outlined, Icons.dns_rounded,
                      'Servers'),
                  TabItem(Icons.notifications_outlined,
                      Icons.notifications_rounded, 'Alerts'),
                  TabItem(Icons.tune_outlined, Icons.tune_rounded,
                      'Rules'),
                  TabItem(Icons.settings_outlined,
                      Icons.settings_rounded, 'Settings'),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
