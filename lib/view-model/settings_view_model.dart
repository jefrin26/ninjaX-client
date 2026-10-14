import 'package:flutter/material.dart';
import 'package:james_bond/model/backend_settings.dart';
import 'package:james_bond/model/monitor_api.dart';
import 'package:james_bond/model/ui_prefs.dart';

/// VIEW-MODEL LAYER — Settings tab.
///
/// Wraps MODEL [BackendSettings] (+ [UiPrefs] for appearance/polling/
/// notifications). VIEW never imports model/ — it only talks to this
/// VM with plain String/int/bool/Color.
class SettingsViewModel extends ChangeNotifier {
  final BackendSettings settings;
  final UiPrefs prefs;
  SettingsViewModel({required this.settings, required this.prefs}) {
    settings.addListener(_onSettingsChanged);
    prefs.addListener(_onSettingsChanged);
  }

  String? testResult;
  bool testing = false;
  bool saving = false;

  String get activeBaseUrl => settings.baseUrl;
  String get host => settings.host;
  int get port => settings.port;

  static const defaultHost = BackendSettings.defaultHost;
  static const defaultPort = BackendSettings.defaultPort;

  @override
  void dispose() {
    settings.removeListener(_onSettingsChanged);
    prefs.removeListener(_onSettingsChanged);
    super.dispose();
  }

  void _onSettingsChanged() => notifyListeners();

  // ---- appearance / polling / notifications (UiPrefs passthrough) ----

  String get theme => prefs.theme;
  Color get accent => prefs.accent;
  bool get anims => prefs.anims;
  bool get compact => prefs.compact;
  int get pollSec => prefs.pollSec;
  int get timeoutSec => prefs.timeoutSec;
  bool get notifMaster => prefs.notifMaster;
  Set<String> get notifRules => prefs.notifRules;

  Future<void> setTheme(String v) => prefs.setTheme(v);
  Future<void> setAccent(Color c) => prefs.setAccent(c);
  Future<void> setAnims(bool v) => prefs.setAnims(v);
  Future<void> setCompact(bool v) => prefs.setCompact(v);
  Future<void> setPollSec(int v) => prefs.setPollSec(v);
  Future<void> setTimeoutSec(int v) => prefs.setTimeoutSec(v);
  Future<void> setNotifMaster(bool v) => prefs.setNotifMaster(v);
  Future<void> toggleNotifRule(String ruleId, bool v) =>
      prefs.toggleNotifRule(ruleId, v);

  String previewUrl(String hostText, String portText) {
    final h = hostText.trim().isEmpty ? defaultHost : hostText.trim();
    final p = int.tryParse(portText.trim()) ?? defaultPort;
    return 'ws://$h:$p';
  }

  bool isDirty(String hostText, String portText) {
    final p = int.tryParse(portText.trim());
    return hostText.trim() != settings.host || p != settings.port;
  }

  String? validateHost(String? v) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return 'Hostname is required';
    if (t.contains(' ')) return 'No spaces allowed';
    return null;
  }

  String? validatePort(String? v) {
    final p = int.tryParse((v ?? '').trim());
    if (p == null) return 'Port must be a number';
    if (p < 1 || p > 65535) return 'Port must be 1–65535';
    return null;
  }

  String _friendlyTestError(Object e, String preview) {
    final s = e.toString();
    if (s.contains('Failed to fetch') || s.contains('ClientException')) {
      return '$s\n\n'
          'The app talks WebSocket to $preview. '
          'Check: backend listening on 0.0.0.0, '
          'firewall allows the port, and you pressed Save below.';
    }
    return s;
  }

  Future<void> testConnection(String hostText, String portText) async {
    testing = true;
    testResult = null;
    notifyListeners();
    final preview = previewUrl(hostText, portText);
    try {
      final api = MonitorApi(preview);
      final h = await api.healthz();
      testResult = 'OK: WS $preview → pong ts=${h['ts']}';
    } catch (e) {
      testResult = 'FAILED: $preview → ${_friendlyTestError(e, preview)}';
    } finally {
      testing = false;
      notifyListeners();
    }
  }

  Future<String> save(String hostText, int port) async {
    saving = true;
    notifyListeners();
    try {
      await settings.save(hostText.trim(), port);
      return 'Saved backend: ${settings.baseUrl}';
    } finally {
      saving = false;
      notifyListeners();
    }
  }

  Future<void> resetDefaults() => settings.resetDefaults();
}
