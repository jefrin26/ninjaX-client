import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// MODEL LAYER: persisted backend connection settings.
///
/// Backend speaks WebSocket only (`ws://<host>:<port>/`, PORT from
/// `.env`, default `3000`). Plain HTTP gets `426 Upgrade Required`.
/// View-models may hold this. Views must NOT import it directly —
/// they go through a SettingsViewModel.
class BackendSettings extends ChangeNotifier {
  static const _kHost = 'backend_host';
  static const _kPort = 'backend_port';
  static const defaultHost = '0.0.0.0';
  static const defaultPort = 0;

  String _host = defaultHost;
  int _port = defaultPort;

  String get host => _host;
  int get port => _port;

  /// e.g. `ws://localhost:3000`
  String get baseUrl => 'ws://$_host:$_port';

  /// Alias — the whole app talks WebSocket now.
  String get wsUrl => baseUrl;

  BackendSettings();

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _host = (prefs.getString(_kHost) ?? defaultHost).trim();
    if (_host.isEmpty) _host = defaultHost;
    _port = prefs.getInt(_kPort) ?? defaultPort;
    notifyListeners();
  }

  Future<void> save(String host, int port) async {
    final h = host.trim().isEmpty ? defaultHost : host.trim();
    // Strip scheme/trailing slash if the user pastes a full URL.
    var cleaned = h.replaceFirst(RegExp(r'^(https?|wss?)://'), '');
    cleaned = cleaned.split('/').first.split(':').first;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kHost, cleaned);
    await prefs.setInt(_kPort, port);
    _host = cleaned;
    _port = port;
    notifyListeners();
  }

  Future<void> resetDefaults() => save(defaultHost, defaultPort);
}
