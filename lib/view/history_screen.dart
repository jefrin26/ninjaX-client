import 'dart:async';

import 'package:flutter/material.dart';
import 'package:james_bond/view-model/server_detail_view_model.dart';
import 'app_theme.dart';
import 'widgets/ui.dart';

/// VIEW LAYER — History, time travel for one metric (spec §3).
/// Composed ONLY from widgets in `widgets/ui.dart`.
class HistoryScreen extends StatefulWidget {
  final String baseUrl;
  final String serverId;
  final String initialMetric;
  /// Client poll cadence (seconds) driving live-follow. Snapshotted
  /// from UiPrefs when the route opens.
  final int pollSec;
  const HistoryScreen({
    super.key,
    required this.baseUrl,
    required this.serverId,
    this.initialMetric = 'cpu',
    this.pollSec = 1,
  });

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late final ServerDetailViewModel vm;
  Timer? _autoTimer;
  int _metricIdx = 0;
  int _rangeIdx = 4; // All (null since)
  bool _rx = true;
  bool _tx = true;
  bool _pointsOpen = false;

  static const _metrics = [
    'cpu',
    'mem',
    'disk',
    'net',
    'system',
    'disk_full'
  ];
  static const _metricLabels = [
    'CPU',
    'MEM',
    'DISK',
    'NET',
    'SYSTEM',
    'DISK FULL'
  ];
  static const _ranges = ['1H', '6H', '24H', '7D', 'All', 'Custom'];

  @override
  void initState() {
    super.initState();
    _metricIdx = _metrics
        .indexOf(widget.initialMetric)
        .clamp(0, _metrics.length - 1);
    vm = ServerDetailViewModel(
        baseUrl: widget.baseUrl, serverId: widget.serverId);
    vm.setMetric(_metrics[_metricIdx]);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Subscribe first so WS pushes live-append even before the
      // history fetch lands; then fetch + start the ECG driver.
      vm.watchLive();
      vm.loadHistory();
      _restartAutoPoll();
    });
  }

  @override
  void didUpdateWidget(covariant HistoryScreen old) {
    super.didUpdateWidget(old);
    if (old.pollSec != widget.pollSec) _restartAutoPoll();
  }

  /// ECG driver: force-poll at the user interval; each fresh sample
  /// appends to the chart window (see VM _appendLiveToHistory) so the
  /// big chart scrolls instead of freezing. Same guards as detail.
  void _restartAutoPoll() {
    _autoTimer?.cancel();
    final sec = widget.pollSec.clamp(1, 3600);
    _autoTimer = Timer.periodic(Duration(seconds: sec), (_) async {
      if (!mounted) return;
      if (ModalRoute.of(context)?.isCurrent != true) return;
      if (vm.loadingLive) return;
      try {
        await vm.poll();
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    vm.dispose();
    super.dispose();
  }

  String get _metric => _metrics[_metricIdx];

  Future<void> _pickRange(int i) async {
    if (i == 5) {
      final now = DateTime.now();
      final picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(now.year - 2),
        lastDate: now,
        builder: (context, child) => Theme(
          data: Theme.of(context),
          child: child!,
        ),
      );
      if (picked == null || !mounted) return;
      vm.setSince(picked.start.millisecondsSinceEpoch, 'Custom');
      setState(() => _rangeIdx = 5);
      await vm.loadHistory();
      return;
    }
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    const h = Duration.millisecondsPerHour;
    switch (i) {
      case 0:
        vm.setSince(nowMs - h, '1H');
        break;
      case 1:
        vm.setSince(nowMs - 6 * h, '6H');
        break;
      case 2:
        vm.setSince(nowMs - 24 * h, '24H');
        break;
      case 3:
        vm.setSince(nowMs - 7 * 24 * h, '7D');
        break;
      default:
        vm.setSince(null);
    }
    setState(() => _rangeIdx = i);
    await vm.loadHistory();
  }

  List<List<double>> _series() {
    final h = vm.history;
    if (h == null) return const [];
    if (_metric == 'net') {
      final out = <List<double>>[];
      if (_rx) out.add(h.rxSeries.isEmpty ? h.chartValues : h.rxSeries);
      if (_tx) out.add(h.txSeries.isEmpty ? h.chartValues : h.txSeries);
      return out.isEmpty ? [h.chartValues] : out;
    }
    if (_metric == 'system' &&
        (h.load1Series.any((v) => v != 0) ||
            h.load5Series.any((v) => v != 0))) {
      return [h.load1Series, h.load5Series, h.load15Series];
    }
    return [h.chartValues];
  }

  List<String>? get _legend =>
      _metric == 'net' ? ['rx', 'tx'] : _metric == 'system' ? ['load1', 'load5', 'load15'] : null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.bg.withValues(alpha: 0.82),
        title: Text('${widget.serverId} · History',
            style: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: Icon(Icons.refresh_rounded,
                size: 20, color: AppTheme.sub),
            onPressed:
                vm.loadingHistory ? null : vm.loadHistory,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(1),
          child:
              SizedBox(height: 1, child: ColoredBox(color: AppTheme.border)),
        ),
      ),
      body: ListenableBuilder(
        listenable: vm,
        builder: (context, _) {
          return RefreshIndicator(
            color: AppTheme.accent,
            onRefresh: vm.loadHistory,
            child: ListView(
                padding:
                    const EdgeInsets.fromLTRB(16, 12, 16, 26),
                children: [
                  FilterChips(
                    segmented: true,
                    options:
                        _metricLabels.map(ChipOption.new).toList(),
                    selected: _metricIdx,
                    onSelected: (i) {
                      setState(() => _metricIdx = i);
                      vm.setMetric(_metrics[i]);
                      vm.loadHistory();
                    },
                  ),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(
                      child: FilterChips(
                        options: _ranges.map(ChipOption.new).toList(),
                        selected: _rangeIdx,
                        onSelected: _pickRange,
                      ),
                    ),
                  ]),
                  const SizedBox(height: 6),
                  Row(children: [
                    MiniChip(vm.history?.countLabel ??
                        vm.sinceLabel ??
                        '…'),
                    if (vm.history != null) ...[
                      const SizedBox(width: 6),
                      MiniChip('LIVE · ${widget.pollSec}s',
                          tint: AppTheme.accent, filled: true),
                    ],
                    const Spacer(),
                    if (_metric == 'net') ...[
                      GestureDetector(
                        onTap: () =>
                            setState(() => _rx = !_rx),
                        child: MiniChip('rx',
                            tint: _rx
                                ? AppTheme.accent
                                : AppTheme.sub,
                            filled: _rx),
                      ),
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: () =>
                            setState(() => _tx = !_tx),
                        child: MiniChip('tx',
                            tint: _tx
                                ? AppTheme.amber
                                : AppTheme.sub,
                            filled: _tx),
                      ),
                    ],
                  ]),
                  const SizedBox(height: 10),
                  if (vm.loadingHistory &&
                      vm.history == null)
                    const AppCard(
                        child: ChartSkeleton()),
                  if (vm.historyError != null)
                    ErrorCard(
                        text: vm.historyError!,
                        title: 'History unavailable',
                        onRetry: vm.loadHistory),
                  if (vm.historyError == null &&
                      !vm.loadingHistory &&
                      (vm.history == null ||
                          vm.history!.chartValues.isEmpty))
                    EmptyState(
                      icon: Icons.show_chart_rounded,
                      title: 'No samples yet',
                      subtitle:
                          'No history for $_metric. Host may be down.',
                      actionLabel: 'Force poll',
                      onAction: () async {
                        await vm.poll();
                        await vm.loadHistory();
                      },
                    ),
                  if (vm.history != null &&
                      vm.history!.chartValues.isNotEmpty) ...[
                    AppCard(
                      glow: AppTheme.accent,
                      child: AreaChart(
                        series: _series(),
                        seriesLabels: _legend,
                        height: 210,
                        live: true,
                      ),
                    ),
                    const SizedBox(height: 10),
                    AppCard(
                      child: Row(children: [
                        _Stat(
                            label: 'MIN',
                            value: vm.history!.minLabel),
                        _Stat(
                            label: 'AVG',
                            value: vm.history!.avgLabel),
                        _Stat(
                            label: 'MAX',
                            value: vm.history!.maxLabel),
                        _Stat(
                            label: 'LAST',
                            value: vm.history!.lastLabel),
                      ]),
                    ),
                    const SizedBox(height: 10),
                    AppCard(
                      onTap: () => setState(
                          () => _pointsOpen = !_pointsOpen),
                      child: Column(children: [
                        Row(children: [
                          const Expanded(
                              child: SectionLabel(
                                  'Recent points')),
                          Icon(
                              _pointsOpen
                                  ? Icons.expand_less_rounded
                                  : Icons.expand_more_rounded,
                              size: 16,
                              color: AppTheme.sub),
                        ]),
                        if (_pointsOpen) ...[
                          const SizedBox(height: 8),
                          ...vm.history!.entries
                              .take(10)
                              .map((p) => Padding(
                                    padding:
                                        const EdgeInsets.only(
                                            bottom: 7),
                                    child: Row(children: [
                                      Expanded(
                                        child: Text(
                                            p.timeLabel,
                                            style: TextStyle(
                                                fontSize: 12,
                                                fontWeight:
                                                    FontWeight
                                                        .w700,
                                                color: AppTheme
                                                    .ink,
                                                fontFeatures: [
                                                  FontFeature
                                                      .tabularFigures()
                                                ],
                                                fontFamilyFallback: [
                                                  'monospace'
                                                ])),
                                      ),
                                      Expanded(
                                        flex: 2,
                                        child: Text(
                                            p.detailLabel,
                                            maxLines: 1,
                                            overflow:
                                                TextOverflow
                                                    .ellipsis,
                                            textAlign:
                                                TextAlign.end,
                                            style: TextStyle(
                                                fontSize:
                                                    11.5,
                                                color: AppTheme
                                                    .sub,
                                                fontFamilyFallback: [
                                                  'monospace'
                                                ])),
                                      ),
                                    ]),
                                  )),
                        ],
                      ]),
                    ),
                  ],
                ]),
          );
        },
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  const _Stat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(children: [
        Text(label,
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: AppTheme.sub)),
        const SizedBox(height: 4),
        Text(value,
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: AppTheme.ink,
                fontFeatures: [FontFeature.tabularFigures()],
                fontFamilyFallback: ['monospace'])),
      ]),
    );
  }
}
