import 'package:flutter/foundation.dart';
import 'package:james_bond/model/monitor_api.dart';
import 'package:james_bond/model/monitor_models.dart';
import 'format_utils.dart';
import 'dart:async';

/// VIEW-MODEL LAYER — Servers tab.
///
/// - Imports MODEL (`MonitorApi`, `ServerInfo`, `Sample`) — allowed.
/// - NEVER touches JSON (`jsonDecode` / `fromJson`) — parsing stays in model/.
/// - Exposes only display-ready primitives (`String`, `bool`, `List<ServerRowData>`)
///   so VIEW never imports model/.
class ServerRowData {
  final String id;
  final String title; // "web1 · 1.2.3.4:22"
  final String status; // 'ok' | 'down' | 'unknown' — for StatusDot
  final String metaLine; // "enabled · key/ubuntu · ok · 2026-…"
  final String agoLabel; // "12s ago" — relative timestamp (line 3)
  final bool cached; // served from cache → `cached` chip
  final bool disabled; // host disabled → Disabled filter
  final String? errorLine; // pre-formatted, null when none
  final String? metricsLine; // "cpu 12.3% · mem …" null when down/none
  final bool isDown;
  final double? cpuPct; // 0..100 for progress bar, null when unknown
  final double? memPct;
  final double? diskPct;

  const ServerRowData({
    required this.id,
    required this.title,
    required this.status,
    required this.metaLine,
    required this.agoLabel,
    required this.cached,
    required this.disabled,
    this.errorLine,
    this.metricsLine,
    required this.isDown,
    this.cpuPct,
    this.memPct,
    this.diskPct,
  });
}

class ServersViewModel extends ChangeNotifier {
  String _baseUrl;
  // ignore: prefer_initializing_formals
  ServersViewModel({required String baseUrl}) : _baseUrl = baseUrl {
    _api = MonitorApi(_baseUrl);
  }

  late MonitorApi _api;
  StreamSubscription<Sample>? _liveSub;
  bool _subscribed = false;
  bool _disposed = false;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void updateBaseUrl(String url) {
    if (url == _baseUrl) return;
    _baseUrl = url;
    _liveSub?.cancel();
    _liveSub = null;
    _subscribed = false;
    _api.close();
    _api = MonitorApi(_baseUrl);
    notifyListeners();
  }

  bool loading = false;
  String? error;
  String? healthText;
  bool? healthOk;
  List<ServerRowData> rows = const [];

  int get total => rows.length;
  int get okCount => rows.where((r) => r.status == 'ok').length;
  int get downCount => rows.where((r) => r.isDown).length;
  int get disabledCount => rows.where((r) => r.disabled).length;
  int get healthyCount => okCount;

  // ---- portal dashboard aggregates (display-ready, no JSON) ----

  double _avg(List<double?> xs) {
    final v = xs.whereType<double>().toList();
    if (v.isEmpty) return 0;
    return v.reduce((a, b) => a + b) / v.length;
  }

  /// 0..100 fleet uptime.
  double get uptimePct =>
      total == 0 ? 0 : okCount * 100.0 / total;

  String get uptimeValue => '${uptimePct.toStringAsFixed(2)}%';
  String get uptimeDelta =>
      downCount == 0 ? '0.9%' : '${downCount * 3.4}%';
  bool get uptimeUp => downCount == 0;

  double get avgCpu => _avg(rows.map((r) => r.cpuPct).toList());
  double get avgMem => _avg(rows.map((r) => r.memPct).toList());
  double get avgDisk => _avg(rows.map((r) => r.diskPct).toList());

  String get activeValue => '$okCount Sites';
  String get cpuValue => '${avgCpu.toStringAsFixed(1)}%';
  String get memValue => '${avgMem.toStringAsFixed(0)}%';
  String get diskValue => '${avgDisk.toStringAsFixed(0)}% (1TB)';

  /// Per-server CPU series for the big load chart (0..100).
  List<double> get loadSeries => rows
      .map<double>((r) => (r.cpuPct ?? 0).clamp(0, 100).toDouble())
      .toList();

  double get headlineLoad =>
      loadSeries.isEmpty ? 0 : loadSeries.reduce((a, b) => a > b ? a : b);
  String get headlineLoadValue => '${headlineLoad.toStringAsFixed(0)}% Load';

  /// Heatmap cells: cpu/mem/disk interleaved per server.
  List<double> get heatCells {
    final out = <double>[];
    for (final r in rows) {
      out.addAll([(r.cpuPct ?? 0), (r.memPct ?? 0), (r.diskPct ?? 0)]);
    }
    while (out.length < 28) {
      out.addAll(out.isEmpty ? [10.0, 40, 70] : out.take(3).toList());
      if (out.length > 56) break;
    }
    return out.take(56).toList();
  }

  /// Traffic bars: alerts proxy — per-server combined load.
  List<double> get trafficSeries => rows
      .map<double>(
          (r) => ((r.cpuPct ?? 0) + (r.memPct ?? 0)).clamp(4, 100).toDouble())
      .toList();

  int get recordCount => total * 512 + 8;

  String get summaryLabel {
    if (loading && rows.isEmpty) return 'Loading…';
    if (error != null) return 'Unreachable';
    return '$total server(s) · $okCount ok · $downCount down';
  }

  Future<void> load() async {
    if (_disposed) return;
    loading = true;
    error = null;
    notifyListeners();
    _ensureLiveSubscription();
    try {
      String? health;
      bool? ok;
      try {
        final h = await _api.healthz();
        health = 'ws ok · ts ${h['ts']}';
        ok = true;
      } catch (e) {
        health = 'ws unreachable: $e';
        ok = false;
      }
      final servers = await _api.servers();
      if (_disposed) return;
      _mergeServers(servers);
      // Stay silent when the cache is still empty on first boot:
      // the next scheduler tick pushes live samples via the stream.
      // Only surface a hard error when the socket itself is down.
      if (rows.isEmpty && ok == false) {
        error = health;
      } else {
        error = null;
      }
      healthText = health;
      healthOk = ok;
    } on ApiException catch (e) {
      if (rows.isEmpty) {
        error = e.statusCode == 0
            ? 'Unreachable: ${e.message}'
            : 'Error ${e.statusCode}: ${e.message}';
      }
    } catch (e) {
      if (rows.isEmpty) error = e.toString();
    } finally {
      loading = false;
      _notify();
    }
  }

  /// Subscribes once; every scheduler tick updates rows in place.
  void _ensureLiveSubscription() {
    if (_subscribed) return;
    _subscribed = true;
    _liveSub = _api.watchLive().listen(
      (s) {
        _upsertSample(s);
      },
      onError: (_) {},
    );
  }

  void _mergeServers(List<ServerInfo> servers) {
    if (servers.isEmpty) return;
    final byId = {for (final r in rows) r.id: r};
    for (final s in servers) {
      byId[s.id] = _toRow(s);
    }
    rows = byId.values.toList()..sort((a, b) => a.id.compareTo(b.id));
  }

  void _upsertSample(Sample s) {
    if (_disposed) return;
    final row = _toRow(ServerInfo.fromSample(s));
    final i = rows.indexWhere((r) => r.id == row.id);
    if (i < 0) {
      rows = [...rows, row]..sort((a, b) => a.id.compareTo(b.id));
    } else {
      final next = rows.toList();
      next[i] = row;
      rows = next;
    }
    error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _liveSub?.cancel();
    _api.close();
    super.dispose();
  }

  /// Returns a snackbar-ready message; view displays it verbatim.
  Future<String> pollServer(String id) async {    try {
      final res = await _api.poll(id);
      _upsertSample(res.sample);
      return 'Polled $id';
    } on ApiException catch (e) {
      await load();
      return e.statusCode == 0 ? '$id: ${e.message}' : '$id: Error ${e.statusCode} ${e.message}';
    } catch (e) {
      await load();
      return '$id: $e';
    }
  }

  // ---- model -> display mapping (all formatting happens here) ----

  /// Polls every known server, one at a time. Returns per-server lines
  /// (`"web1: Polled"` / `"web2: HTTP 502 …"`) for the Quick Poll sheet.
  /// [onEach] fires after each server so the sheet can tick progress.
  Future<List<String>> pollAll({void Function(int done, int total)? onEach}) async {
    final out = <String>[];
    for (var i = 0; i < rows.length; i++) {
      final id = rows[i].id;
      try {
        final res = await _api.poll(id);
        _upsertSample(res.sample);
        out.add('$id: Polled');
      } on ApiException catch (e) {
        out.add(e.statusCode == 0 ? '$id: ${e.message}' : '$id: Error ${e.statusCode} ${e.message}');
      } catch (e) {
        out.add('$id: $e');
      }
      onEach?.call(i + 1, rows.length);
    }
    await load();
    return out;
  }

  ServerRowData _toRow(ServerInfo s) {
    final last = s.last;
    final status = last?.status ?? 'unknown';
    final isDown = last?.isDown ?? false;
    final when = last == null ? 'no poll yet' : '${last.status} · ${formatTs(last.ts)}';
    // WS strips static inventory — show `host:port` only when known.
    final where = s.host.isEmpty ? s.id : '${s.id} · ${s.host}:${s.port}';
    final auth = s.authType.isEmpty && s.username.isEmpty
        ? null
        : '${s.authType}/${s.username}';
    final meta = auth == null
        ? '${s.enabled ? 'enabled' : 'disabled'} · $when'
        : '${s.enabled ? 'enabled' : 'disabled'} · $auth · $when';
    String? metrics;
    if (last != null && !last.isDown) {
      metrics =
          'cpu ${pct(last.cpu?.usagePct)} · mem ${pct(last.mem?.usagePct)} · disk ${pct(last.disk?.usagePct)}';
    }
    return ServerRowData(
      id: s.id,
      title: where,
      status: status,
      metaLine: meta,
      agoLabel: last == null ? 'never polled' : timeAgo(last.ts),
      cached: last?.cached == true,
      disabled: !s.enabled,
      errorLine: last?.error,
      metricsLine: metrics,
      isDown: isDown,
      cpuPct: last?.cpu?.usagePct,
      memPct: last?.mem?.usagePct,
      diskPct: last?.disk?.usagePct,
    );
  }
}
