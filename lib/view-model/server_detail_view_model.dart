import 'package:flutter/foundation.dart';
import 'package:james_bond/model/monitor_api.dart';
import 'package:james_bond/model/monitor_models.dart';
import 'format_utils.dart';
import 'dart:async';

/// VIEW-MODEL LAYER — Server detail.
///
/// Owns live sample + history, maps MODEL objects to display DTOs.
/// No JSON here. VIEW only consumes [LiveDisplay] / [HistoryDisplay].
class MetricRowData {
  final String label;
  final String value;
  const MetricRowData(this.label, this.value);
}

class LiveDisplay {
  final String status; // raw 'ok'/'down' for the dot
  final String statusLabel; // "ok" / "ok (cached)" / "down"
  final String timeLabel;
  final String agoLabel; // "12s ago" — sticky subtitle
  final bool cached; // served from cache → `cached` chip
  final String? hostLine; // "host:port · authType · username" (from inventory)
  final String? errorText;
  final String? durationLabel;
  final List<MetricRowData> metricRows;
  final List<String> firedLabels;
  final double? cpuPct; // 0..100, for beautiful tiles/bars
  final double? memPct;
  final double? diskPct;
  final List<double>? cpuLoads; // load1/5/15
  final List<double>? sysLoads; // load1/5/15
  final String? uptimeLabel; // "5 days, 2:11"
  final String? memDetail; // "5.1 GB / 8.2 GB · swap …"
  final String? diskTarget; // "/"
  final List<NetIfaceData> netIfaces;

  const LiveDisplay({
    required this.status,
    required this.statusLabel,
    required this.timeLabel,
    required this.agoLabel,
    required this.cached,
    this.hostLine,
    this.errorText,
    this.durationLabel,
    required this.metricRows,
    required this.firedLabels,
    this.cpuPct,
    this.memPct,
    this.diskPct,
    this.cpuLoads,
    this.sysLoads,
    this.uptimeLabel,
    this.memDetail,
    this.diskTarget,
    this.netIfaces = const [],
  });
}

/// One network interface row (pre-formatted for the Network card).
class NetIfaceData {
  final String name; // "eth0"
  final String ratesLabel; // "10 B/s ↓ · 20 B/s ↑" or "calculating…"
  final double rx; // bytes/sec, 0 when unknown
  final double tx;
  final bool calculating;
  const NetIfaceData({
    required this.name,
    required this.ratesLabel,
    required this.rx,
    required this.tx,
    required this.calculating,
  });
}

class HistoryEntryData {
  final String timeLabel;
  final String detailLabel;
  const HistoryEntryData(this.timeLabel, this.detailLabel);
}

class HistoryDisplay {
  final String countLabel;
  final List<double> chartValues;
  final List<HistoryEntryData> entries; // newest-first, capped at 20
  final String minLabel;
  final String avgLabel;
  final String maxLabel;
  final String lastLabel;
  final List<double> rxSeries; // net metric: rx bytes/sec per point
  final List<double> txSeries; // net metric: tx bytes/sec per point
  final List<double> load1Series; // system metric overlays
  final List<double> load5Series;
  final List<double> load15Series;
  const HistoryDisplay({
    required this.countLabel,
    required this.chartValues,
    required this.entries,
    required this.minLabel,
    required this.avgLabel,
    required this.maxLabel,
    required this.lastLabel,
    this.rxSeries = const [],
    this.txSeries = const [],
    this.load1Series = const [],
    this.load5Series = const [],
    this.load15Series = const [],
  });
}

const kMetrics = ['cpu', 'mem', 'disk', 'disk_full', 'net', 'system'];

class ServerDetailViewModel extends ChangeNotifier {
  final String baseUrl;
  final String serverId;

  ServerDetailViewModel({required this.baseUrl, required this.serverId})
      : _api = MonitorApi(baseUrl);

  final MonitorApi _api;
  StreamSubscription<Sample>? _liveSub;
  bool _disposed = false;

  bool loadingLive = false;
  String? liveErrorTitle; // e.g. "live error HTTP 502"
  String? liveErrorText;
  LiveDisplay? live;

  String metric = 'cpu';
  int limit = 100;
  int? sinceMs; // time-range filter (1H/6H/24H/7D/Custom), null = all
  String? sinceLabel;
  bool loadingHistory = false;
  String? historyError;
  HistoryDisplay? history;

  int get firedCount => live?.firedLabels.length ?? 0;

  /// Recent rx/tx points for the Network card sparklines (last 60
  /// `net` samples). Empty → card shows the "calculating…" shimmer.
  /// Live-appended on every WS push / poll so the strip flows like
  /// an ECG when the poll interval is 1s.
  List<double> netRxSpark = const [];
  List<double> netTxSpark = const [];

  /// Live ring buffers for the ECG strips (last 60 live samples,
  /// newest last). Appended in [_applySample] on every push/poll;
  /// down/null samples append 0 so the trace flatlines instead of
  /// jumping. Empty until the first live sample lands.
  static const liveWindow = 60;
  List<double> liveCpu = const [];
  List<double> liveMem = const [];
  List<double> liveDisk = const [];
  int _lastAppliedTs = -1;

  /// Live push subscription for this server (scheduler ticks land
  /// here without polling). Idempotent — first call wins.
  void watchLive() {
    if (_disposed) return;
    _liveSub ??= _api.watchLive().listen(
      (s) {
        if (_disposed || s.serverId != serverId) return;
        final fired = _firedLabels(s.alertsFired);
        _applySample(
            s, fired.isEmpty ? (live?.firedLabels ?? const []) : fired);
      },
      onError: (_) {},
    );
  }

  /// Single entry point for every fresh sample (push, get_live,
  /// poll, down-sample). Updates the live numbers, appends the ECG
  /// ring buffers (deduped by ts — a poll response and its
  /// broadcast push carry the same ts), live-appends history, and
  /// notifies once.
  void _applySample(Sample s, List<String> fired) {
    live = _toLive(s, fired);
    liveErrorTitle = null;
    liveErrorText = null;
    if (s.ts != _lastAppliedTs) {
      _lastAppliedTs = s.ts;
      _appendLiveBuffers(s);
      _appendLiveToHistory(s);
    }
    if (!_disposed) notifyListeners();
  }

  void _appendLiveBuffers(Sample s) {
    List<double> push(List<double> cur, double v) {
      final next = [...cur, v];
      if (next.length > liveWindow) {
        next.removeRange(0, next.length - liveWindow);
      }
      return next;
    }

    liveCpu = push(liveCpu, s.cpu?.usagePct ?? 0);
    liveMem = push(liveMem, s.mem?.usagePct ?? 0);
    liveDisk = push(liveDisk, s.disk?.usagePct ?? 0);
    final net = s.net;
    if (net != null) {
      netRxSpark = push(netRxSpark, _pointRx(net));
      netTxSpark = push(netTxSpark, _pointTx(net));
    } else if (s.isDown) {
      netRxSpark = push(netRxSpark, 0);
      netTxSpark = push(netTxSpark, 0);
    }
  }

  /// Appends one live sample to the loaded history so the big chart
  /// scrolls like an ECG instead of freezing at fetch time. Sliding
  /// window capped at [limit]; min/avg/max/last + recent-points update.
  void _appendLiveToHistory(Sample s) {
    final h = history;
    if (h == null) return;
    final window = limit.clamp(1, 5000);
    List<double> pushH(List<double> cur, double v) {
      final next = [...cur, v];
      if (next.length > window) {
        next.removeRange(0, next.length - window);
      }
      return next;
    }

    List<double> chart = h.chartValues;
    List<double> rx = h.rxSeries;
    List<double> tx = h.txSeries;
    List<double> l1 = h.load1Series;
    List<double> l5 = h.load5Series;
    List<double> l15 = h.load15Series;
    switch (metric) {
      case 'cpu':
        chart = pushH(chart, s.cpu?.usagePct ?? 0);
        break;
      case 'mem':
        chart = pushH(chart, s.mem?.usagePct ?? 0);
        break;
      case 'disk':
        chart = pushH(chart, s.disk?.usagePct ?? 0);
        break;
      case 'disk_full':
        var worst = s.disk?.usagePct ?? 0;
        final mounts = s.disk?.mounts;
        if (mounts != null) {
          for (final m in mounts) {
            final p = ((m['usagePct'] as num?)?.toDouble() ?? 0);
            if (p > worst) worst = p;
          }
        }
        chart = pushH(chart, worst);
        break;
      case 'net':
        final r = s.net == null ? 0.0 : _pointRx(s.net!);
        final t = s.net == null ? 0.0 : _pointTx(s.net!);
        rx = pushH(rx, r);
        tx = pushH(tx, t);
        chart = pushH(chart, r + t);
        break;
      case 'system':
        final a = s.system?.load1 ?? 0;
        final b = s.system?.load5 ?? 0;
        final c = s.system?.load15 ?? 0;
        l1 = pushH(l1, a);
        l5 = pushH(l5, b);
        l15 = pushH(l15, c);
        chart = pushH(chart, a);
        break;
      default:
        return;
    }
    String fmt(double v) => v.toStringAsFixed(1);
    String mm(List<double> vs, double Function(double a, double b) pick) =>
        vs.isEmpty ? '—' : fmt(vs.reduce(pick));
    final entries = [
      HistoryEntryData(formatTs(s.ts), _liveDetailLabel(s)),
      ...h.entries,
    ].take(20).toList();
    history = HistoryDisplay(
      countLabel: '${chart.length} point(s) · metric=$metric · LIVE',
      chartValues: chart,
      entries: entries,
      minLabel: mm(chart, (a, b) => a < b ? a : b),
      avgLabel: chart.isEmpty
          ? '—'
          : fmt(chart.reduce((a, b) => a + b) / chart.length),
      maxLabel: mm(chart, (a, b) => a > b ? a : b),
      lastLabel: chart.isEmpty ? '—' : fmt(chart.last),
      rxSeries: rx,
      txSeries: tx,
      load1Series: l1,
      load5Series: l5,
      load15Series: l15,
    );
  }

  String _liveDetailLabel(Sample s) {
    switch (metric) {
      case 'cpu':
        return 'cpu: ${s.cpu?.usagePct?.toStringAsFixed(1) ?? '—'}%';
      case 'mem':
        return 'mem: ${s.mem?.usagePct?.toStringAsFixed(1) ?? '—'}%';
      case 'disk':
      case 'disk_full':
        return 'disk: ${s.disk?.usagePct?.toStringAsFixed(1) ?? '—'}%';
      case 'net':
        return s.net == null ? 'live' : _netSummary(s.net!);
      case 'system':
        return 'load ${fmtLoad(s.system?.load1)}/${fmtLoad(s.system?.load5)}/${fmtLoad(s.system?.load15)}';
      default:
        return 'live';
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _liveSub?.cancel();
    _api.close();
    super.dispose();
  }

  static List<String> _firedLabels(List<Map<String, dynamic>>? fired) =>
      (fired ?? [])
          .map((a) => '${a['ruleId'] ?? a['rule'] ?? 'rule'}')
          .toList();

  Future<void> loadNetSpark() async {
    try {
      final h =
          await _api.history(serverId, metric: 'net', limit: 60);
      if (_disposed) return;
      netRxSpark = h.points.map((p) => _pointRx(p.value)).toList();
      netTxSpark = h.points.map((p) => _pointTx(p.value)).toList();
      notifyListeners();
    } catch (_) {
      // Best-effort; the card degrades to "calculating…".
    }
  }

  /// Sum rx/tx across interfaces for one history/live value map.
  /// WS nests rates under `rates: {iface: {…}}`; legacy flat
  /// `{rxBytesPerSec, txBytesPerSec}` still works.
  static double _pointRx(Map<String, dynamic> v) =>
      _sumRates(v, 'rxBytesPerSec');
  static double _pointTx(Map<String, dynamic> v) =>
      _sumRates(v, 'txBytesPerSec');

  static double _sumRates(Map<String, dynamic> v, String key) {
    final rates = v['rates'];
    if (rates is Map) {
      var total = 0.0;
      rates.forEach((_, iface) {
        if (iface is Map) {
          total += ((iface[key] as num?)?.toDouble() ?? 0);
        }
      });
      return total;
    }
    return ((v[key] as num?)?.toDouble() ?? 0);
  }

  /// Inventory line for the collapsing header. WS strips static
  /// inventory (`host:port · auth · user`), so there is nothing to
  /// fetch — the header shows the server id. Kept as a no-op for
  /// existing callers.
  Future<void> loadMeta() async {}

  Future<void> loadLive({required bool refresh}) async {
    if (_disposed) return;
    loadingLive = true;
    liveErrorTitle = null;
    liveErrorText = null;
    notifyListeners();
    watchLive();
    try {
      final s = await _api.live(serverId, refresh: refresh);
      if (_disposed) return;
      _applySample(s, _firedLabels(s.alertsFired));
    } on ApiException catch (e) {
      // Parsing helper lives in MODEL (downSampleParsed), not here.
      // Apply the down-sample first (it clears stale errors), then
      // record the fresh error so it survives.
      final down = e.downSampleParsed;
      if (down != null && !_disposed) _applySample(down, const []);
      liveErrorTitle = e.statusCode == 0 ? 'live error' : 'live error ${e.statusCode}';
      liveErrorText = e.message;
    } catch (e) {
      liveErrorTitle = 'live error';
      liveErrorText = e.toString();
    } finally {
      loadingLive = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<String?> poll() async {
    if (_disposed) return null;
    loadingLive = true;
    liveErrorTitle = null;
    liveErrorText = null;
    notifyListeners();
    watchLive();
    try {
      final res = await _api.poll(serverId);
      if (_disposed) return null;
      final firedLabels = _firedLabels(res.alertsFired);
      _applySample(res.sample, firedLabels);
      if (firedLabels.isNotEmpty) return '${firedLabels.length} alert(s) fired';
      return null;
    } on ApiException catch (e) {
      final down = e.downSampleParsed;
      if (down != null && !_disposed) _applySample(down, const []);
      liveErrorTitle = e.statusCode == 0 ? 'poll error' : 'poll error ${e.statusCode}';
      liveErrorText = e.message;
      return null;
    } finally {
      loadingLive = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> loadHistory() async {
    if (_disposed) return;
    loadingHistory = true;
    historyError = null;
    notifyListeners();
    try {
      final h = await _api.history(serverId,
          metric: metric,
          since: sinceMs,
          limit: limit.clamp(1, 5000));
      if (_disposed) return;
      history = _toHistory(h);
    } on ApiException catch (e) {
      history = null;
      historyError = e.statusCode == 0 ? e.message : '${e.statusCode}: ${e.message}';
    } catch (e) {
      history = null;
      historyError = e.toString();
    } finally {
      loadingHistory = false;
      if (!_disposed) notifyListeners();
    }
  }

  void setMetric(String m) {
    if (m == metric) return;
    metric = m;
    notifyListeners();
  }

  void setLimit(int v) {
    limit = v.clamp(1, 5000);
    notifyListeners();
  }

  void setSince(int? ms, [String? label]) {
    sinceMs = ms;
    sinceLabel = label;
    notifyListeners();
  }

  // ---- model -> display ----

  LiveDisplay _toLive(Sample s, List<String> fired) {
    final statusLabel = '${s.status}${s.cached == true ? ' (cached)' : ''}';
    final rows = <MetricRowData>[
      MetricRowData(
          'cpu',
          s.cpu == null
              ? 'null'
              : 'usagePct ${pct(s.cpu!.usagePct)} · load ${fmtLoad(s.cpu!.load1)}/${fmtLoad(s.cpu!.load5)}/${fmtLoad(s.cpu!.load15)}'),
      MetricRowData(
          'mem',
          s.mem == null
              ? 'null'
              : 'usagePct ${pct(s.mem!.usagePct)} · ${formatBytes(s.mem!.usedBytes)}/${formatBytes(s.mem!.totalBytes)}'),
      MetricRowData(
          'disk',
          s.disk == null
              ? 'null'
              : 'usagePct ${pct(s.disk!.usagePct)} · ${formatBytes(s.disk!.usedBytes)}/${formatBytes(s.disk!.totalBytes)} · ${s.disk!.target ?? ''}'),
      MetricRowData('net', s.net == null ? 'null' : _netSummary(s.net!)),
      MetricRowData(
          'system',
          s.system == null
              ? 'null'
              : '${s.system!.uptimeHuman ?? ''} · load ${fmtLoad(s.system!.load1)}/${fmtLoad(s.system!.load5)}/${fmtLoad(s.system!.load15)}'),
    ];
    return LiveDisplay(
      status: s.status,
      statusLabel: statusLabel,
      timeLabel: formatTs(s.ts),
      agoLabel: timeAgo(s.ts),
      cached: s.cached == true,
      hostLine: s.host.isEmpty ? null : s.host,
      errorText: s.error,
      durationLabel:
          s.durationMs == null ? null : 'durationMs: ${s.durationMs}',
      metricRows: rows,
      firedLabels: fired,
      cpuPct: s.cpu?.usagePct,
      memPct: s.mem?.usagePct,
      diskPct: s.disk?.usagePct,
      cpuLoads: s.cpu == null
          ? null
          : [s.cpu!.load1 ?? 0, s.cpu!.load5 ?? 0, s.cpu!.load15 ?? 0],
      sysLoads: s.system == null
          ? null
          : [
              s.system!.load1 ?? 0,
              s.system!.load5 ?? 0,
              s.system!.load15 ?? 0
            ],
      uptimeLabel: s.system?.uptimeHuman,
      memDetail: s.mem == null
          ? null
          : '${formatBytes(s.mem!.usedBytes)} / ${formatBytes(s.mem!.totalBytes)}',
      diskTarget: s.disk?.target,
      netIfaces: _toNetIfaces(s.net),
    );
  }

  /// Per-iface rows for the Network card. First poll's nulls → a single
  /// "calculating…" row so the card never shows raw JSON.
  /// WS nests interfaces under `net.rates`; legacy flat shapes still work.
  List<NetIfaceData> _toNetIfaces(Map<String, dynamic>? net) {
    final rates = (net?['rates'] is Map)
        ? Map<String, dynamic>.from(net!['rates'] as Map)
        : net;
    if (rates == null || rates.isEmpty) {
      return const [
        NetIfaceData(
            name: 'all',
            ratesLabel: 'calculating…',
            rx: 0,
            tx: 0,
            calculating: true),
      ];
    }
    // Shape A: { "eth0": {"rxBytesPerSec": n, "txBytesPerSec": n}, … }
    // (WS: identical, nested under `net.rates` and unwrapped above.)
    final perIface = <NetIfaceData>[];
    rates.forEach((iface, v) {
      if (v is Map) {
        final rx = (v['rxBytesPerSec'] as num?)?.toDouble();
        final tx = (v['txBytesPerSec'] as num?)?.toDouble();
        if (rx == null && tx == null) return;
        final rxn = rx ?? 0;
        final txn = tx ?? 0;
        final calc = rx == null || tx == null;
        perIface.add(NetIfaceData(
          name: iface,
          ratesLabel: calc
              ? 'calculating…'
              : '${formatBytes(rxn.toInt())}/s ↓ · ${formatBytes(txn.toInt())}/s ↑',
          rx: rxn,
          tx: txn,
          calculating: calc,
        ));
      }
    });
    if (perIface.isNotEmpty) return perIface;
    // Shape B: flat { rxBytesPerSec, txBytesPerSec } (+ optional rates:null)
    final rx = (rates['rxBytesPerSec'] as num?)?.toDouble();
    final tx = (rates['txBytesPerSec'] as num?)?.toDouble();
    if (rx == null && tx == null) {
      return const [
        NetIfaceData(
            name: 'all',
            ratesLabel: 'calculating…',
            rx: 0,
            tx: 0,
            calculating: true),
      ];
    }
    return [
      NetIfaceData(
        name: (rates['iface'] ?? 'all').toString(),
        ratesLabel:
            '${formatBytes(rx?.toInt())}/s ↓ · ${formatBytes(tx?.toInt())}/s ↑',
        rx: rx ?? 0,
        tx: tx ?? 0,
        calculating: false,
      ),
    ];
  }

  String _netSummary(Map<String, dynamic> net) {
    final rows = _toNetIfaces(net);
    return rows.map((r) => '${r.name}: ${r.ratesLabel}').join(' · ');
  }

  HistoryDisplay _toHistory(HistoryResponse h) {
    // Chartable number per point. WS `net` values nest under
    // `rates:{iface:{…}}` (summed here); `disk_full` values carry
    // only `mounts` (chart the worst mount).
    double chartable(Map<String, dynamic> v) {
      if (v.containsKey('rates')) {
        return _pointRx(v) + _pointTx(v);
      }
      if (v['mounts'] is List) {
        var worst = 0.0;
        for (final m in (v['mounts'] as List)) {
          if (m is Map) {
            final p = ((m['usagePct'] as num?)?.toDouble() ?? 0);
            if (p > worst) worst = p;
          }
        }
        return worst;
      }
      return primaryNumber(v) ?? 0;
    }

    final values = h.points.map((p) => chartable(p.value)).toList();
    final entries = h.points.reversed.take(20).map((p) {
      return HistoryEntryData(formatTs(p.ts), historyValueLabel(p.value));
    }).toList();
    String fmt(double v) => v.toStringAsFixed(1);
    final minL = values.isEmpty
        ? '—'
        : fmt(values.reduce((a, b) => a < b ? a : b));
    final maxL = values.isEmpty
        ? '—'
        : fmt(values.reduce((a, b) => a > b ? a : b));
    final avgL = values.isEmpty
        ? '—'
        : fmt(values.reduce((a, b) => a + b) / values.length);
    final lastL = values.isEmpty ? '—' : fmt(values.last);
    List<double> numSeries(String k) => h.points
        .map((p) => ((p.value[k] as num?)?.toDouble() ?? 0))
        .toList();
    return HistoryDisplay(
      countLabel: '${h.points.length} point(s) · metric=${h.metric}',
      chartValues: values,
      entries: entries,
      minLabel: minL,
      avgLabel: avgL,
      maxLabel: maxL,
      lastLabel: lastL,
      rxSeries: h.points.map((p) => _pointRx(p.value)).toList(),
      txSeries: h.points.map((p) => _pointTx(p.value)).toList(),
      load1Series: numSeries('load1'),
      load5Series: numSeries('load5'),
      load15Series: numSeries('load15'),
    );
  }
}
