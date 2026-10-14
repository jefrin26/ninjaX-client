import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'monitor_models.dart';

/// MODEL LAYER: WebSocket client for the monitor backend.
///
/// The backend speaks WebSocket only (`ws://<host>:<port>/` — plain
/// HTTP gets `426 Upgrade Required`). One persistent connection per
/// base URL is shared by every [MonitorApi] instance via [_hubs]:
/// the server pushes `{type:live}` every scheduler tick, and unary
/// calls (`poll`, `get_live`, `get_history`, `get_alerts`, `ping`)
/// are multiplexed over the same socket.
///
/// Protocol (see spec):
/// - server push: `welcome`, `live` (ok/down) per enabled server.
/// - client: `subscribe`/`unsubscribe`, `poll`, `get_live`,
///   `get_history`, `get_alerts`, `ping`.
/// - replies: `subscribed`, `live`, `history`, `alerts`, `pong`,
///   `error`.
///
/// Conventions: `id` = server id (client maps `id → {name, ip}`
/// locally), `metric ∈ cpu|mem|disk|net|system` (+ read-only
/// `disk_full`), `since` = epoch ms, `limit` = max points
/// (default 500, cap 5000). History exists only for `ok` samples.
///
/// This is the ONLY place that touches the socket / `jsonDecode`.
/// View-models call these typed methods and never parse JSON
/// directly. Views must never import this file.
class MonitorApi {
  final String baseUrl;
  final Duration timeout;
  final Object _owner = Object();

  MonitorApi(this.baseUrl, {this.timeout = const Duration(seconds: 15)});

  /// Cancels this instance's in-flight requests (frees their
  /// timeouts). View-models call this from `dispose()` so widget
  /// tests never end with pending timers. The shared socket stays
  /// open for other instances.
  void close() => _WsHub.forUrl(normalize(baseUrl)).cancelFor(_owner);

  /// Accepts `http(s)://`, `ws(s)://` or bare `host:port` and
  /// normalizes to a `ws(s)://host:port/` URL.
  static String normalize(String url) {
    var u = url.trim();
    if (u.isEmpty) return u;
    if (u.startsWith('http://')) {
      u = 'ws://${u.substring('http://'.length)}';
    } else if (u.startsWith('https://')) {
      u = 'wss://${u.substring('https://'.length)}';
    } else if (!u.startsWith('ws://') && !u.startsWith('wss://')) {
      u = 'ws://$u';
    }
    final uri = Uri.parse(u);
    // Backend serves WS at the root path.
    final path = uri.path.isEmpty ? '/' : uri.path;
    return uri.replace(path: path).toString();
  }

  _WsHub get _hub => _WsHub.forUrl(normalize(baseUrl));

  /// Live push stream. Always subscribes to ALL servers (omitted
  /// `ids`); callers filter locally. Staying on "all" avoids one
  /// screen narrowing the shared subscription for the rest.
  Stream<Sample> watchLive({List<String>? ids}) =>
      _hub.watchLive(timeout: timeout);

  /// Liveness via `ping`/`pong` (there is no HTTP `/healthz`).
  Future<Map<String, dynamic>> healthz() async {
    final ts = await _hub.ping(_owner, timeout: timeout);
    return {'ok': true, 'ts': ts};
  }

  /// No inventory endpoint over WS — synthesize from cached live
  /// pushes. Empty on first boot until the next scheduler tick;
  /// callers should also listen to [watchLive] for updates.
  Future<List<ServerInfo>> servers() async {
    final live = await _hub.cachedServers(timeout: timeout);
    return live.map(ServerInfo.fromSample).toList();
  }

  /// Cached snapshot (`get_live`), or forced SSH poll
  /// (`poll`) when [refresh] is true.
  Future<Sample> live(String id, {bool refresh = false}) async {
    if (refresh) {
      return (await poll(id)).sample;
    }
    return _hub.getLive(_owner, id, timeout: timeout);
  }

  /// Force SSH poll now; replies with a fresh `live` sample.
  /// Returns (sample, alertsFired).
  Future<({Sample sample, List<Map<String, dynamic>> alertsFired})> poll(
      String id) async {
    final s = await _hub.poll(_owner, id, timeout: timeout);
    return (sample: s, alertsFired: s.alertsFired ?? const []);
  }

  /// Metric history (`since` epoch ms, `limit` default 500/cap 5000).
  Future<HistoryResponse> history(
    String id, {
    String metric = 'cpu',
    int? since,
    int limit = 500,
  }) async {
    return _hub.getHistory(_owner, id,
        metric: metric, since: since, limit: limit, timeout: timeout);
  }

  /// Alert events, optionally filtered by server.
  Future<List<AlertEvent>> alerts({String? serverId}) =>
      _hub.getAlerts(_owner, serverId: serverId, timeout: timeout);

  // No WS equivalents — the server exposes none of these.
  Future<List<AlertRule>> rules() async {
    throw ApiException(501, 'rules are not exposed over WebSocket');
  }

  Future<int> clearCache({String? serverId}) async {
    throw ApiException(501, 'clear cache is not supported over WebSocket');
  }

  Future<int> clearHistory({String? serverId, String? metric}) async {
    throw ApiException(501, 'clear history is not supported over WebSocket');
  }

  Future<int> clearAlerts({String? serverId}) async {
    throw ApiException(501, 'clear alerts is not supported over WebSocket');
  }
}

/// One persistent WS connection per normalized URL, shared by all
/// [MonitorApi] instances. Unary requests are serialized through
/// [_mutex] so `error` replies (which carry no request id) route
/// unambiguously; `live` pushes fan out to [_liveController]
/// regardless of in-flight requests.
class _WsHub {
  static final Map<String, _WsHub> _hubs = {};

  factory _WsHub.forUrl(String url) =>
      _hubs.putIfAbsent(url, () => _WsHub._(url));

  final String url;
  _WsHub._(this.url);

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  bool _connected = false;
  bool _connecting = false;
  Completer<void>? _connectingDone;

  final Map<String, Sample> _liveCache = {};
  final StreamController<Sample> _liveController =
      StreamController<Sample>.broadcast();

  final List<_LiveWaiter> _liveWaiters = [];
  final List<_HistoryWaiter> _historyWaiters = [];
  final List<_AlertsWaiter> _alertsWaiters = [];
  final List<_PongWaiter> _pongWaiters = [];

  Future<void> _mutex = Future<void>.value();
  final Set<Object> _closedOwners = {};

  Future<T> _serialized<T>(Object owner, Future<T> Function() fn) {
    final prev = _mutex;
    final done = Completer<void>();
    _mutex = done.future;
    return prev.then((_) {
      if (_closedOwners.contains(owner)) {
        throw ApiException(0, 'cancelled');
      }
      return fn();
    }).whenComplete(() {
      if (!done.isCompleted) done.complete();
    });
  }

  Stream<Sample> watchLive({Duration? timeout}) {
    unawaited(_ensureConnected(connectTimeout: timeout).then((_) {
      _send({'type': 'subscribe'});
    }).catchError((_) {}));
    return _liveController.stream;
  }

  Future<List<Sample>> cachedServers({Duration? timeout}) async {
    try {
      await _ensureConnected(connectTimeout: timeout);
      _send({'type': 'subscribe'});
    } catch (_) {
      // Offline — serve whatever we have (usually nothing on boot).
    }
    final cached = _liveCache.values.toList()
      ..sort((a, b) => a.serverId.compareTo(b.serverId));
    return cached;
  }

  Future<void> _ensureConnected({Duration? connectTimeout}) async {
    if (_connected) return;
    if (_connecting) {
      final t = connectTimeout ?? const Duration(seconds: 15);
      await _connectingDone!.future.timeout(t, onTimeout: () {
        throw ApiException(0, 'WebSocket connect timeout: $url');
      });
      if (!_connected) {
        throw ApiException(0, 'WebSocket unreachable: $url');
      }
      return;
    }
    _connecting = true;
    _connectingDone = Completer<void>();
    try {
      final ch = WebSocketChannel.connect(Uri.parse(url));
      _channel = ch;
      _sub = ch.stream.listen(_onData,
          onError: (_) => _onDisconnect('WebSocket error: $url'),
          onDone: () => _onDisconnect('WebSocket closed: $url'),
          cancelOnError: false);
      _connected = true;
    } catch (e) {
      _connected = false;
      if (!_connectingDone!.isCompleted) {
        _connectingDone!.completeError(
            ApiException(0, 'WebSocket unreachable: $url ($e)'));
      }
      _connecting = false;
      rethrow;
    } finally {
      if (_connected && !_connectingDone!.isCompleted) {
        _connectingDone!.complete();
      }
      _connecting = false;
    }
  }

  void _send(Map<String, dynamic> msg) {
    final ch = _channel;
    if (!_connected || ch == null) {
      throw ApiException(0, 'WebSocket not connected: $url');
    }
    ch.sink.add(jsonEncode(msg));
  }

  void _onData(dynamic raw) {
    Map<String, dynamic>? m;
    try {
      final text = raw is String ? raw : String.fromCharCodes(raw as List<int>);
      final decoded = jsonDecode(text);
      if (decoded is Map) {
        m = Map<String, dynamic>.from(decoded);
      }
    } catch (_) {
      return;
    }
    if (m == null) return;
    final type = m['type'] as String?;
    switch (type) {
      case 'welcome':
      case 'subscribed':
        break;
      case 'live':
        Sample? s;
        try {
          s = Sample.fromJson(m);
        } catch (_) {
          return;
        }
        if (s.serverId.isEmpty) return;
        final sample = s;
        _liveCache[sample.serverId] = sample;
        if (!_liveController.isClosed) _liveController.add(sample);
        final hit = _liveWaiters
            .where((w) => w.id == sample.serverId && !w.done)
            .toList();
        for (final w in hit) {
          w.done = true;
          w.completer.complete(sample);
        }
        _liveWaiters.removeWhere((w) => w.done);
        break;
      case 'history':
        final id = (m['id'] ?? m['serverId'] ?? '') as String;
        final metric = (m['metric'] ?? '') as String;
        HistoryResponse? h;
        try {
          h = HistoryResponse.fromJson(m);
        } catch (_) {
          return;
        }
        final response = h;
        final hit = _historyWaiters
            .where((w) => !w.done && w.id == id && w.metric == metric)
            .toList();
        if (hit.isEmpty) {
          // Late/unsolicited — ignore (a serialized waiter timed out).
          return;
        }
        for (final w in hit) {
          w.done = true;
          w.completer.complete(response);
        }
        _historyWaiters.removeWhere((w) => w.done);
        break;
      case 'alerts':
        final list = ((m['alerts'] as List?) ?? [])
            .whereType<Map>()
            .map((e) {
              try {
                return AlertEvent.fromJson(
                    Map<String, dynamic>.from(e));
              } catch (_) {
                return null;
              }
            })
            .whereType<AlertEvent>()
            .toList();
        final aw = _alertsWaiters.where((w) => !w.done).toList();
        if (aw.isNotEmpty) {
          final w = aw.first;
          w.done = true;
          _alertsWaiters.remove(w);
          if (!w.completer.isCompleted) w.completer.complete(list);
        }
        break;
      case 'pong':
        final ts = (m['ts'] as num? ?? 0).toInt();
        final pw = _pongWaiters.where((w) => !w.done).toList();
        if (pw.isNotEmpty) {
          final w = pw.first;
          w.done = true;
          _pongWaiters.remove(w);
          if (!w.completer.isCompleted) w.completer.complete(ts);
        }
        break;
      case 'error':
        _failOldest(m['error']?.toString() ?? 'server error');
        break;
      default:
        break;
    }
  }

  void _failOldest(String message) {
    final code = _errorCode(message);
    final err = ApiException(code, message);
    // The serialized op owns the head waiter of each queue; fail all
    // heads (only one queue is normally occupied).
    for (final w in _liveWaiters.where((w) => !w.done)) {
      w.done = true;
      if (!w.completer.isCompleted) w.completer.completeError(err);
    }
    _liveWaiters.removeWhere((w) => w.done);
    for (final w in _historyWaiters.where((w) => !w.done)) {
      w.done = true;
      if (!w.completer.isCompleted) w.completer.completeError(err);
    }
    _historyWaiters.removeWhere((w) => w.done);
    for (final w in _alertsWaiters.where((w) => !w.done)) {
      w.done = true;
      if (!w.completer.isCompleted) w.completer.completeError(err);
    }
    _alertsWaiters.removeWhere((w) => w.done);
    for (final w in _pongWaiters.where((w) => !w.done)) {
      w.done = true;
      if (!w.completer.isCompleted) w.completer.completeError(err);
    }
    _pongWaiters.removeWhere((w) => w.done);
  }

  /// Fails one owner's in-flight requests (see [MonitorApi.close]).
  /// Completing the source futures also cancels their `.timeout`
  /// timers, so disposed view-models leave nothing pending. Queued
  /// (not yet started) ops abort before creating any timer.
  void cancelFor(Object owner) {
    _closedOwners.add(owner);
    final err = ApiException(0, 'cancelled');
    void failLive(_LiveWaiter w) {
      w.done = true;
      if (!w.completer.isCompleted) w.completer.completeError(err);
    }

    for (final w in _liveWaiters.where((w) => w.owner == owner && !w.done)) {
      failLive(w);
    }
    _liveWaiters.removeWhere((w) => w.done);
    for (final w
        in _historyWaiters.where((w) => w.owner == owner && !w.done)) {
      w.done = true;
      if (!w.completer.isCompleted) w.completer.completeError(err);
    }
    _historyWaiters.removeWhere((w) => w.done);
    for (final w
        in _alertsWaiters.where((w) => w.owner == owner && !w.done)) {
      w.done = true;
      if (!w.completer.isCompleted) w.completer.completeError(err);
    }
    _alertsWaiters.removeWhere((w) => w.done);
    for (final w in _pongWaiters.where((w) => w.owner == owner && !w.done)) {
      w.done = true;
      if (!w.completer.isCompleted) w.completer.completeError(err);
    }
    _pongWaiters.removeWhere((w) => w.done);
  }

  int _errorCode(String message) {
    final m = message.toLowerCase();
    if (m.contains('unknown server') || m.contains('no history')) {
      return 404;
    }
    return 500;
  }

  void _onDisconnect(String message) {
    _connected = false;
    try {
      _sub?.cancel();
    } catch (_) {}
    _sub = null;
    _channel = null;
    final err = ApiException(0, message);
    for (final w in _liveWaiters) {
      if (!w.done && !w.completer.isCompleted) {
        w.done = true;
        w.completer.completeError(err);
      }
    }
    _liveWaiters.clear();
    for (final w in _historyWaiters) {
      if (!w.done && !w.completer.isCompleted) {
        w.done = true;
        w.completer.completeError(err);
      }
    }
    _historyWaiters.clear();
    for (final w in _alertsWaiters) {
      if (!w.done && !w.completer.isCompleted) {
        w.done = true;
        w.completer.completeError(err);
      }
    }
    _alertsWaiters.clear();
    for (final w in _pongWaiters) {
      if (!w.done && !w.completer.isCompleted) {
        w.done = true;
        w.completer.completeError(err);
      }
    }
    _pongWaiters.clear();
  }

  Future<int> ping(Object owner, {Duration? timeout}) {
    final t = timeout ?? const Duration(seconds: 15);
    return _serialized(owner, () async {
      await _ensureConnected(connectTimeout: t);
      final c = Completer<int>();
      final waiter = _PongWaiter(owner, c);
      _pongWaiters.add(waiter);
      try {
        _send({'type': 'ping'});
      } catch (e) {
        waiter.done = true;
        _pongWaiters.remove(waiter);
        throw e is ApiException ? e : ApiException(0, e.toString());
      }
      try {
        return await c.future.timeout(t);
      } on TimeoutException {
        waiter.done = true;
        _pongWaiters.remove(waiter);
        throw ApiException(0, 'WebSocket ping timeout: $url');
      }
    });
  }

  Future<Sample> getLive(Object owner, String id, {Duration? timeout}) {
    final t = timeout ?? const Duration(seconds: 15);
    return _serialized(owner, () async {
      // Serve cache instantly when a push already arrived.
      final cached = _liveCache[id];
      await _ensureConnected(connectTimeout: t);
      final c = Completer<Sample>();
      final waiter = _LiveWaiter(owner, id, c);
      _liveWaiters.add(waiter);
      try {
        _send({'type': 'get_live', 'id': id});
      } catch (e) {
        waiter.done = true;
        _liveWaiters.remove(waiter);
        if (cached != null) return cached;
        throw e is ApiException ? e : ApiException(0, e.toString());
      }
      try {
        return await c.future.timeout(t);
      } on TimeoutException {
        waiter.done = true;
        _liveWaiters.remove(waiter);
        if (cached != null) return cached;
        throw ApiException(0, 'WebSocket get_live timeout: $id');
      }
    });
  }

  Future<Sample> poll(Object owner, String id, {Duration? timeout}) {
    final t = timeout ?? const Duration(seconds: 15);
    return _serialized(owner, () async {
      await _ensureConnected(connectTimeout: t);
      final c = Completer<Sample>();
      final waiter = _LiveWaiter(owner, id, c);
      _liveWaiters.add(waiter);
      try {
        _send({'type': 'poll', 'id': id});
      } catch (e) {
        waiter.done = true;
        _liveWaiters.remove(waiter);
        throw e is ApiException ? e : ApiException(0, e.toString());
      }
      try {
        return await c.future.timeout(t);
      } on TimeoutException {
        waiter.done = true;
        _liveWaiters.remove(waiter);
        throw ApiException(0, 'WebSocket poll timeout: $id');
      }
    });
  }

  Future<HistoryResponse> getHistory(
    Object owner,
    String id, {
    String metric = 'cpu',
    int? since,
    int limit = 500,
    Duration? timeout,
  }) {
    final t = timeout ?? const Duration(seconds: 15);
    final capped = limit.clamp(1, 5000);
    return _serialized(owner, () async {
      await _ensureConnected(connectTimeout: t);
      final c = Completer<HistoryResponse>();
      final waiter = _HistoryWaiter(owner, id, metric, c);
      _historyWaiters.add(waiter);
      try {
        final msg = <String, dynamic>{
          'type': 'get_history',
          'id': id,
          'metric': metric,
          'limit': capped,
        };
        if (since != null) msg['since'] = since;
        _send(msg);
      } catch (e) {
        waiter.done = true;
        _historyWaiters.remove(waiter);
        throw e is ApiException ? e : ApiException(0, e.toString());
      }
      try {
        return await c.future.timeout(t);
      } on TimeoutException {
        waiter.done = true;
        _historyWaiters.remove(waiter);
        throw ApiException(0, 'WebSocket history timeout: $id/$metric');
      }
    });
  }

  Future<List<AlertEvent>> getAlerts(Object owner,
      {String? serverId, Duration? timeout}) {
    final t = timeout ?? const Duration(seconds: 15);
    return _serialized(owner, () async {
      await _ensureConnected(connectTimeout: t);
      final c = Completer<List<AlertEvent>>();
      final waiter = _AlertsWaiter(owner, c);
      _alertsWaiters.add(waiter);
      try {
        _send({
          'type': 'get_alerts',
          if (serverId != null && serverId.isNotEmpty)
            'serverId': serverId,
        });
      } catch (e) {
        waiter.done = true;
        _alertsWaiters.remove(waiter);
        throw e is ApiException ? e : ApiException(0, e.toString());
      }
      try {
        return await c.future.timeout(t);
      } on TimeoutException {
        waiter.done = true;
        _alertsWaiters.remove(waiter);
        throw ApiException(0, 'WebSocket alerts timeout');
      }
    });
  }
}

class _LiveWaiter {
  final Object owner;
  final String id;
  final Completer<Sample> completer;
  bool done = false;
  _LiveWaiter(this.owner, this.id, this.completer);
}

class _HistoryWaiter {
  final Object owner;
  final String id;
  final String metric;
  final Completer<HistoryResponse> completer;
  bool done = false;
  _HistoryWaiter(this.owner, this.id, this.metric, this.completer);
}

class _AlertsWaiter {
  final Object owner;
  final Completer<List<AlertEvent>> completer;
  bool done = false;
  _AlertsWaiter(this.owner, this.completer);
}

class _PongWaiter {
  final Object owner;
  final Completer<int> completer;
  bool done = false;
  _PongWaiter(this.owner, this.completer);
}
