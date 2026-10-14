/// Data models mirroring the monitor API reference.
///
/// MODEL LAYER ONLY:
/// - All incoming JSON parsing (`fromJson`) lives here.
/// - View-models must use these classes via [MonitorApi] / repository
///   and must NOT call `jsonDecode` or `fromJson` themselves.
/// - Views must NOT import this file. Views only see pre-formatted
///   strings/lists exposed by view-models.
library;

/// A live / last snapshot sample. `status` is `ok` or `down`.
class CpuSample {
  final double? usagePct;
  final double? load1;
  final double? load5;
  final double? load15;
  CpuSample({this.usagePct, this.load1, this.load5, this.load15});
  factory CpuSample.fromJson(Map<String, dynamic> j) => CpuSample(
        usagePct: (j['usagePct'] as num?)?.toDouble(),
        load1: (j['load1'] as num?)?.toDouble(),
        load5: (j['load5'] as num?)?.toDouble(),
        load15: (j['load15'] as num?)?.toDouble(),
      );
}

class MemSample {
  final double? usagePct;
  final int? usedBytes;
  final int? totalBytes;
  final int? availableBytes;
  MemSample({this.usagePct, this.usedBytes, this.totalBytes, this.availableBytes});
  factory MemSample.fromJson(Map<String, dynamic> j) => MemSample(
        usagePct: (j['usagePct'] as num?)?.toDouble(),
        usedBytes: (j['usedBytes'] as num?)?.toInt(),
        totalBytes: (j['totalBytes'] as num?)?.toInt(),
        availableBytes: (j['availableBytes'] as num?)?.toInt(),
      );
}

class DiskSample {
  final double? usagePct;
  final int? usedBytes;
  final int? totalBytes;
  final String? target;
  final List<Map<String, dynamic>>? mounts;
  DiskSample(
      {this.usagePct, this.usedBytes, this.totalBytes, this.target, this.mounts});
  factory DiskSample.fromJson(Map<String, dynamic> j) => DiskSample(
        usagePct: (j['usagePct'] as num?)?.toDouble(),
        usedBytes: (j['usedBytes'] as num?)?.toInt(),
        totalBytes: (j['totalBytes'] as num?)?.toInt(),
        target: j['target'] as String?,
        mounts: (j['mounts'] as List?)
            ?.whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList(),
      );
}

class SystemSample {
  final String? uptimeHuman;
  final double? load1;
  final double? load5;
  final double? load15;
  SystemSample({this.uptimeHuman, this.load1, this.load5, this.load15});
  factory SystemSample.fromJson(Map<String, dynamic> j) => SystemSample(
        uptimeHuman: j['uptimeHuman'] as String?,
        load1: (j['load1'] as num?)?.toDouble(),
        load5: (j['load5'] as num?)?.toDouble(),
        load15: (j['load15'] as num?)?.toDouble(),
      );
}

/// A live / last snapshot sample. `status` is `ok` or `down`.
/// WS shape: `{type:live, id, ts, status, cpu, mem, disk{…,mounts},
/// net:{rates:{…}}, system, alerts:[{rule,metric,op,…}], error?}`.
/// Static fields (`host`, `cached`, `durationMs`) are absent over WS
/// and stay null. `alerts` and legacy `alertsFired` both normalize
/// into [alertsFired].
class Sample {
  final String serverId;
  final String host;
  final int ts;
  final String status;
  final String? error;
  final CpuSample? cpu;
  final MemSample? mem;
  final DiskSample? disk;
  final Map<String, dynamic>? net;
  final SystemSample? system;
  final bool? cached;
  final int? durationMs;
  final List<Map<String, dynamic>>? alertsFired;

  Sample({
    required this.serverId,
    required this.host,
    required this.ts,
    required this.status,
    this.error,
    this.cpu,
    this.mem,
    this.disk,
    this.net,
    this.system,
    this.cached,
    this.durationMs,
    this.alertsFired,
  });

  bool get isDown => status == 'down';

  factory Sample.fromJson(Map<String, dynamic> j) => Sample(
        serverId: (j['serverId'] ?? j['id'] ?? '') as String,
        host: (j['host'] ?? '') as String,
        ts: (j['ts'] as num? ?? 0).toInt(),
        status: (j['status'] ?? 'down') as String,
        error: j['error'] as String?,
        cpu: j['cpu'] == null ? null : CpuSample.fromJson(j['cpu'] as Map<String, dynamic>),
        mem: j['mem'] == null ? null : MemSample.fromJson(j['mem'] as Map<String, dynamic>),
        disk: j['disk'] == null ? null : DiskSample.fromJson(j['disk'] as Map<String, dynamic>),
        net: j['net'] as Map<String, dynamic>?,
        system: j['system'] == null ? null : SystemSample.fromJson(j['system'] as Map<String, dynamic>),
        cached: j['cached'] as bool?,
        durationMs: (j['durationMs'] as num?)?.toInt(),
        alertsFired: ((j['alertsFired'] ?? j['alerts']) as List?)
            ?.whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList(),
      );
}

class ServerInfo {
  final String id;
  final String host;
  final int port;
  final bool enabled;
  final String authType;
  final String username;
  final Sample? last;
  ServerInfo({
    required this.id,
    this.host = '',
    this.port = 22,
    this.enabled = true,
    this.authType = '',
    this.username = '',
    this.last,
  });
  factory ServerInfo.fromJson(Map<String, dynamic> j) => ServerInfo(
        id: (j['id'] ?? '') as String,
        host: (j['host'] ?? '') as String,
        port: (j['port'] as num? ?? 22).toInt(),
        enabled: (j['enabled'] ?? true) as bool,
        authType: (j['authType'] ?? '') as String,
        username: (j['username'] ?? '') as String,
        last: j['last'] == null ? null : Sample.fromJson(j['last'] as Map<String, dynamic>),
      );

  /// WS has no inventory endpoint — synthesize from a live push.
  /// Static `id → {name, ip}` mapping lives client-side; until one
  /// exists the row shows just the id.
  factory ServerInfo.fromSample(Sample s) =>
      ServerInfo(id: s.serverId, last: s);
}

class HistoryPoint {
  final int ts;
  final Map<String, dynamic> value;
  HistoryPoint({required this.ts, required this.value});
  factory HistoryPoint.fromJson(Map<String, dynamic> j) => HistoryPoint(
        ts: (j['ts'] as num).toInt(),
        value: (j['value'] as Map<String, dynamic>?) ?? {},
      );
}

class HistoryResponse {
  final String serverId;
  final String metric;
  final List<HistoryPoint> points;
  HistoryResponse({required this.serverId, required this.metric, required this.points});
  factory HistoryResponse.fromJson(Map<String, dynamic> j) => HistoryResponse(
        serverId: (j['serverId'] ?? j['id'] ?? '') as String,
        metric: (j['metric'] ?? '') as String,
        points: ((j['points'] as List?) ?? [])
            .map((e) => HistoryPoint.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class AlertEvent {
  final int ts;
  final String serverId;
  final String ruleId;
  final String metric;
  final String? operator;
  final num? threshold;
  final num? value;
  final String message;
  AlertEvent({
    required this.ts,
    required this.serverId,
    required this.ruleId,
    required this.metric,
    this.operator,
    this.threshold,
    this.value,
    required this.message,
  });
  factory AlertEvent.fromJson(Map<String, dynamic> j) {
    final serverId = (j['serverId'] ?? j['id'] ?? '') as String;
    final ruleId = (j['ruleId'] ?? j['rule'] ?? '') as String;
    final metric = (j['metric'] ?? '') as String;
    final operator = j['operator'] as String? ?? j['op'] as String?;
    final threshold = (j['threshold'] as num?);
    final value = (j['value'] as num?);
    var message = (j['message'] ?? '') as String;
    if (message.isEmpty && ruleId.isNotEmpty) {
      message = operator != null && threshold != null
          ? '$ruleId: $metric $operator $threshold (got $value)'
          : '$ruleId: $metric = $value';
    }
    return AlertEvent(
      ts: (j['ts'] as num? ?? 0).toInt(),
      serverId: serverId,
      ruleId: ruleId,
      metric: metric,
      operator: operator,
      threshold: threshold,
      value: value,
      message: message,
    );
  }
}

class AlertRule {
  final String id;
  final String serverId;
  final String metric;
  final String operator;
  final num threshold;
  final int forConsecutive;
  AlertRule({
    required this.id,
    required this.serverId,
    required this.metric,
    required this.operator,
    required this.threshold,
    required this.forConsecutive,
  });
  factory AlertRule.fromJson(Map<String, dynamic> j) => AlertRule(
        id: (j['id'] ?? '') as String,
        serverId: (j['serverId'] ?? '*') as String,
        metric: (j['metric'] ?? '') as String,
        operator: (j['operator'] ?? '>') as String,
        threshold: (j['threshold'] as num? ?? 0),
        forConsecutive: (j['forConsecutive'] as num? ?? 1).toInt(),
      );
}

/// Thrown for API-level errors so the UI can show status codes faithfully.
class ApiException implements Exception {
  final int statusCode;
  final String message;
  final Map<String, dynamic>? downSample;
  ApiException(this.statusCode, this.message, {this.downSample});

  /// Parsed form of [downSample].
  ///
  /// Lives in the MODEL layer so view-models never call `fromJson`
  /// themselves (per MVVM rule: no direct JSON parsing in view-model).
  Sample? get downSampleParsed =>
      downSample == null ? null : Sample.fromJson(downSample!);

  @override
  String toString() => 'ApiException($statusCode): $message';
}
