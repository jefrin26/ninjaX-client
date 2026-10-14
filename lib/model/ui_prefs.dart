import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// MODEL LAYER: persisted UI preferences (spec §6 Settings).
///
/// Views must NOT import this directly — they go through the shell
/// (composition root) or a view-model. Only `main.dart` wires it.
class UiPrefs extends ChangeNotifier {
  static const _kTheme = 'ui_theme'; // system | dark | light
  static const _kAccent = 'ui_accent'; // hex int
  static const _kAnims = 'ui_anims';
  static const _kCompact = 'ui_compact';
  static const _kPollSec = 'ui_poll_sec';
  static const _kTimeoutSec = 'ui_timeout_sec';
  static const _kNotif = 'ui_notif_master';
  static const _kNotifRules = 'ui_notif_rules'; // csv
  static const _kOnboard = 'ui_onboard_seen';

  static const defaultAccent = Color(0xFF0E9F6E);

  /// Fixed swatches for the accent row (spec: user-pickable, one accent).
  static const swatches = <Color>[
    Color(0xFF0E9F6E), // emerald (default, light-first)
    Color(0xFF6EA8FE), // sky
    Color(0xFFB79CFF), // violet
    Color(0xFFFFB020), // amber
    Color(0xFFFF5C5C), // coral red
    Color(0xFFF471B5), // pink
  ];

  String _theme = 'light';
  Color _accent = defaultAccent;
  bool _anims = true;
  bool _compact = false;
  int _pollSec = 1;
  int _timeoutSec = 15;
  bool _notifMaster = true;
  Set<String> _notifRules = {'host-down', 'cpu-high', 'mem-high'};
  bool _onboardSeen = false;

  String get theme => _theme;
  Color get accent => _accent;
  bool get anims => _anims;
  bool get compact => _compact;
  int get pollSec => _pollSec;
  int get timeoutSec => _timeoutSec;
  bool get notifMaster => _notifMaster;
  Set<String> get notifRules => _notifRules;
  bool get onboardSeen => _onboardSeen;

  ThemeMode get themeMode => switch (_theme) {
        'dark' => ThemeMode.dark,
        'light' => ThemeMode.light,
        _ => ThemeMode.system,
      };

  bool ruleEnabled(String ruleId) =>
      _notifMaster && _notifRules.contains(ruleId);

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    _theme = p.getString(_kTheme) ?? 'light';
    _accent = Color(p.getInt(_kAccent) ?? defaultAccent.toARGB32());
    _anims = p.getBool(_kAnims) ?? true;
    _compact = p.getBool(_kCompact) ?? false;
    _pollSec = p.getInt(_kPollSec) ?? 1;
    _timeoutSec = p.getInt(_kTimeoutSec) ?? 15;
    _notifMaster = p.getBool(_kNotif) ?? true;
    final csv = p.getString(_kNotifRules);
    if (csv != null && csv.isNotEmpty) _notifRules = csv.split(',').toSet();
    _onboardSeen = p.getBool(_kOnboard) ?? false;
    notifyListeners();
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kTheme, _theme);
    await p.setInt(_kAccent, _accent.toARGB32());
    await p.setBool(_kAnims, _anims);
    await p.setBool(_kCompact, _compact);
    await p.setInt(_kPollSec, _pollSec);
    await p.setInt(_kTimeoutSec, _timeoutSec);
    await p.setBool(_kNotif, _notifMaster);
    await p.setString(_kNotifRules, _notifRules.join(','));
    await p.setBool(_kOnboard, _onboardSeen);
  }

  Future<void> setTheme(String v) async {
    _theme = v;
    notifyListeners();
    await _save();
  }

  Future<void> setAccent(Color c) async {
    _accent = c;
    notifyListeners();
    await _save();
  }

  Future<void> setAnims(bool v) async {
    _anims = v;
    notifyListeners();
    await _save();
  }

  Future<void> setCompact(bool v) async {
    _compact = v;
    notifyListeners();
    await _save();
  }

  Future<void> setPollSec(int v) async {
    _pollSec = v;
    notifyListeners();
    await _save();
  }

  Future<void> setTimeoutSec(int v) async {
    _timeoutSec = v.round();
    notifyListeners();
    await _save();
  }

  Future<void> setNotifMaster(bool v) async {
    _notifMaster = v;
    notifyListeners();
    await _save();
  }

  Future<void> toggleNotifRule(String ruleId, bool v) async {
    if (v) {
      _notifRules.add(ruleId);
    } else {
      _notifRules.remove(ruleId);
    }
    notifyListeners();
    await _save();
  }

  Future<void> markOnboardSeen() async {
    _onboardSeen = true;
    notifyListeners();
    await _save();
  }
}
