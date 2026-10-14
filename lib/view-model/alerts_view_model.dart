import 'package:flutter/foundation.dart';
import 'package:james_bond/model/monitor_api.dart';
import 'package:james_bond/model/monitor_models.dart';
import 'format_utils.dart';

/// VIEW-MODEL LAYER — Alerts tab. No JSON, no model leaks to view.
class AlertRowData {
  final String title; // "[rule] server · metric"
  final String message;
  final String detailLine; // timestamp + threshold info, pre-formatted
  final int ts; // epoch ms (for Today/7D client filters)
  final String serverId;
  final String ruleId;
  final String metric;
  final String agoLabel; // "12s ago"
  final String dayLabel; // "Today" / "Yesterday" / "Mar 12" (group header)
  final double? value; // threshold-alert value, null for host-down
  final double? threshold;
  final String thresholdLabel; // "95.2 > 90" or ""
  final bool isHostDown; // view picks icon/color from this bool
  const AlertRowData({
    required this.title,
    required this.message,
    required this.detailLine,
    required this.ts,
    required this.serverId,
    required this.ruleId,
    required this.metric,
    required this.agoLabel,
    required this.dayLabel,
    this.value,
    this.threshold,
    required this.thresholdLabel,
    required this.isHostDown,
  });
}

class AlertsViewModel extends ChangeNotifier {
  String _baseUrl;
  // ignore: prefer_initializing_formals
  AlertsViewModel({required String baseUrl})
      : _baseUrl = baseUrl,
        _api = MonitorApi(baseUrl);

  void updateBaseUrl(String url) {
    if (url == _baseUrl) return;
    _baseUrl = url;
    _api.close();
    _api = MonitorApi(url);
    notifyListeners();
  }

  MonitorApi _api;
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _api.close();
    super.dispose();
  }

  bool loading = false;
  String? error;
  List<AlertRowData> rows = const [];
  String filter = '';

  /// Client-side sheet filters (spec: Server / Rule / Time).
  /// Server goes to the API via [filter]; rule + time filter below.
  String ruleFilter = ''; // '' | 'host-down' | 'cpu-high' | …
  String timeFilter = 'all'; // 'all' | 'today' | '7d'

  /// Rows after rule + time filters (view groups these by day).
  /// Locally dismissed rows stay hidden until the next load.
  List<AlertRowData> get visibleRows {
    final now = DateTime.now().millisecondsSinceEpoch;
    return rows.where((r) {
      if (_dismissedKeys.contains(_key(r))) return false;
      if (ruleFilter.isNotEmpty && r.ruleId != ruleFilter) return false;
      if (timeFilter == 'today' && r.dayLabel != 'Today') return false;
      if (timeFilter == '7d' &&
          now - r.ts > const Duration(days: 7).inMilliseconds) {
        return false;
      }
      return true;
    }).toList();
  }

  /// Swipe → dismiss (local only, revived on next load).
  void dismiss(AlertRowData r) {
    _dismissedKeys.add(_key(r));
    notifyListeners();
  }

  void setRuleFilter(String v) {
    ruleFilter = v;
    notifyListeners();
  }

  void setTimeFilter(String v) {
    timeFilter = v;
    notifyListeners();
  }

  /// Locally dismissed/pinned read state (spec: swipe → dismiss,
  /// overflow → mark all read). Keyed by title+detail (stable enough
  /// for an inbox without server-side ids).
  final Set<String> _readKeys = {};
  final Set<String> _dismissedKeys = {};

  String get countLabel => '${rows.length} event(s), newest first';

  /// Unread drives the Alerts tab live badge.
  int get unreadCount =>
      rows.where((r) => !_readKeys.contains(_key(r))).length;

  static String _key(AlertRowData r) => '${r.title}|${r.detailLine}';

  void setFilter(String v) {
    filter = v.trim();
    notifyListeners();
  }

  /// Day groups in order, newest day first (sticky headers in view).
  List<String> get dayGroups {
    final seen = <String>[];
    for (final r in rows) {
      if (!seen.contains(r.dayLabel)) seen.add(r.dayLabel);
    }
    return seen;
  }

  List<AlertRowData> forDay(String day) =>
      rows.where((r) => r.dayLabel == day).toList();

  void markAllRead() {
    for (final r in rows) {
      _readKeys.add(_key(r));
    }
    notifyListeners();
  }

  void markRead(AlertRowData r) {
    _readKeys.add(_key(r));
    notifyListeners();
  }

  Future<void> load() async {
    if (_disposed) return;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final alerts = await _api.alerts(
          serverId: filter.isEmpty ? null : filter);
      if (_disposed) return;
      rows = alerts.map(_toRow).toList();
    } on ApiException catch (e) {
      error = e.statusCode == 0 ? e.message : '${e.statusCode}: ${e.message}';
    } catch (e) {
      error = e.toString();
    } finally {
      loading = false;
      if (!_disposed) notifyListeners();
    }
  }

  AlertRowData _toRow(AlertEvent a) {
    final cond = a.operator != null
        ? '${a.metric} ${a.operator} ${a.threshold} (got ${a.value})'
        : 'value ${a.value}';
    final v = a.value?.toDouble();
    final t = a.threshold?.toDouble();
    return AlertRowData(
      title: '[${a.ruleId}] ${a.serverId} · ${a.metric}',
      message: a.message,
      detailLine: '${formatTs(a.ts)} · $cond',
      ts: a.ts,
      serverId: a.serverId,
      ruleId: a.ruleId,
      metric: a.metric,
      agoLabel: timeAgo(a.ts),
      dayLabel: dayLabel(a.ts),
      value: v,
      threshold: t,
      thresholdLabel: (v != null && t != null && a.operator != null)
          ? '$v ${a.operator} $t'
          : '',
      isHostDown: a.ruleId == 'host-down',
    );
  }
}
