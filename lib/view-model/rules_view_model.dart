import 'package:flutter/foundation.dart';
import 'package:james_bond/model/monitor_api.dart';
import 'package:james_bond/model/monitor_models.dart';

/// VIEW-MODEL LAYER — Rules tab.
class RuleRowData {
  final String title; // "id · metric > threshold"
  final String subtitle; // "serverId: … · forConsecutive: …"
  final String id;
  final String metric;
  final String operator;
  final String thresholdLabel;
  final String serverLabel;
  final int forConsecutive;

  /// Natural-language sentence (spec §5 line 2):
  /// `cpu.usagePct` **>** **90** — for **3** consecutive samples.
  final String formula;

  /// Full JSON for the tap → bottom sheet (+ Copy).
  final String jsonText;

  /// Scale max for the threshold tick visual (pct metrics → 100,
  /// otherwise threshold × 1.5 so the tick never sits at the edge).
  final double scaleMax;

  const RuleRowData({
    required this.title,
    required this.subtitle,
    required this.id,
    required this.metric,
    required this.operator,
    required this.thresholdLabel,
    required this.serverLabel,
    required this.forConsecutive,
    required this.formula,
    required this.jsonText,
    required this.scaleMax,
  });
}

class RulesViewModel extends ChangeNotifier {
  String _baseUrl;
  // ignore: prefer_initializing_formals
  RulesViewModel({required String baseUrl})
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
  List<RuleRowData> rows = const [];
  bool groupByMetric = false;

  String get headerLabel =>
      'Rules live on the host — the WebSocket API exposes none';

  void toggleGrouping() {
    groupByMetric = !groupByMetric;
    notifyListeners();
  }

  /// Metric groups in first-seen order (section headers in view).
  List<String> get metricGroups {
    final seen = <String>[];
    for (final r in rows) {
      if (!seen.contains(r.metric)) seen.add(r.metric);
    }
    return seen;
  }

  List<RuleRowData> forMetric(String metric) =>
      rows.where((r) => r.metric == metric).toList();

  Future<void> load() async {
    if (_disposed) return;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final rules = await _api.rules();
      if (_disposed) return;
      rows = rules.map(_toRow).toList();
    } on ApiException catch (e) {
      rows = const [];
      error = e.message;
    } catch (e) {
      rows = const [];
      error = e.toString();
    } finally {
      loading = false;
      if (!_disposed) notifyListeners();
    }
  }

  RuleRowData _toRow(AlertRule r) {
    final isPct = ['cpu', 'mem', 'disk', 'disk_full'].contains(r.metric);
    final t = r.threshold.toDouble();
    return RuleRowData(
      title: '${r.id} · ${r.metric} ${r.operator} ${r.threshold}',
      subtitle:
          'serverId: ${r.serverId} · forConsecutive: ${r.forConsecutive}',
      id: r.id,
      metric: r.metric,
      operator: r.operator,
      thresholdLabel: '${r.threshold}',
      serverLabel: r.serverId == '*' ? 'All servers' : r.serverId,
      forConsecutive: r.forConsecutive,
      formula:
          '${r.metric == 'disk_full' ? 'disk' : r.metric}.usagePct ${r.operator} ${r.threshold} — for ${r.forConsecutive} consecutive sample${r.forConsecutive == 1 ? '' : 's'}',
      jsonText: '{\n'
          '  "id": "${r.id}",\n'
          '  "serverId": "${r.serverId}",\n'
          '  "metric": "${r.metric}",\n'
          '  "operator": "${r.operator}",\n'
          '  "threshold": ${r.threshold},\n'
          '  "forConsecutive": ${r.forConsecutive}\n'
          '}',
      scaleMax: isPct ? 100.0 : (t <= 0 ? 10.0 : t * 1.5),
    );
  }
}
