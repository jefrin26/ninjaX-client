/// VIEW-MODEL LAYER: pure display formatting.
///
/// Views must display strings prepared here — they do no formatting
/// themselves. Models are never exposed to views; only these helpers'
/// outputs (String / double / bool) cross the VM -> View boundary.
library;

String formatBytes(int? bytes) {
  if (bytes == null) return '—';
  if (bytes < 1024) return '$bytes B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var v = bytes.toDouble();
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v.toStringAsFixed(1)} ${units[i]}';
}

String formatTs(int ts) {
  final d = DateTime.fromMillisecondsSinceEpoch(ts);
  final hh = d.hour.toString().padLeft(2, '0');
  final mm = d.minute.toString().padLeft(2, '0');
  final ss = d.second.toString().padLeft(2, '0');
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} $hh:$mm:$ss';
}

String pct(double? v) =>
    v == null ? 'null (1st poll)' : '${v.toStringAsFixed(1)}%';

String fmtLoad(double? v) => v == null ? '—' : v.toStringAsFixed(2);

/// Relative timestamp for glanceable rows (spec: `12s ago`).
String timeAgo(int ts) {
  final dt = DateTime.fromMillisecondsSinceEpoch(ts);
  final d = DateTime.now().difference(dt);
  if (d.inSeconds < 5) return 'just now';
  if (d.inSeconds < 60) return '${d.inSeconds}s ago';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  if (d.inHours < 24) return '${d.inHours}h ago';
  if (d.inDays == 1) return 'Yesterday';
  if (d.inDays < 7) return '${d.inDays}d ago';
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  return '${months[dt.month - 1]} ${dt.day}';
}

/// Sticky day-group header for the Alerts list.
String dayLabel(int ts) {
  final dt = DateTime.fromMillisecondsSinceEpoch(ts);
  final now = DateTime.now();
  final day = DateTime(dt.year, dt.month, dt.day);
  final today = DateTime(now.year, now.month, now.day);
  final diff = today.difference(day).inDays;
  if (diff <= 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  return '${months[dt.month - 1]} ${dt.day}';
}

/// Pick the chartable number out of a history point value map.
/// (VM-level projection — NOT JSON parsing.)
double? primaryNumber(Map<String, dynamic> v) {
  for (final k in ['usagePct', 'load1', 'rxBytesPerSec', 'txBytesPerSec']) {
    final n = v[k];
    if (n is num) return n.toDouble();
  }
  // Fall back to first numeric entry so mem/disk_full still chart.
  for (final e in v.values) {
    if (e is num) return e.toDouble();
  }
  return null;
}

String historyValueLabel(Map<String, dynamic> v) {
  if (v.isEmpty) return '—';
  return v.entries.map((e) => '${e.key}: ${e.value}').join(' · ');
}
