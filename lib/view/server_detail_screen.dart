import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:james_bond/view-model/server_detail_view_model.dart';
import 'app_theme.dart';
import 'widgets/ui.dart';

/// VIEW LAYER — Server detail, one server fully alive (spec §2).
/// Composed ONLY from widgets in `widgets/ui.dart`.
class ServerDetailScreen extends StatefulWidget {
  final String baseUrl;
  final String serverId;
  final bool fromAlert;
  final ValueChanged<String> onOpenHistory;
  /// Client poll cadence (seconds) driving the ECG auto force-poll.
  /// Snapshotted from UiPrefs when the route opens.
  final int pollSec;
  const ServerDetailScreen({
    super.key,
    required this.baseUrl,
    required this.serverId,
    this.fromAlert = false,
    required this.onOpenHistory,
    this.pollSec = 1,
  });

  @override
  State<ServerDetailScreen> createState() => _ServerDetailScreenState();
}

class _ServerDetailScreenState extends State<ServerDetailScreen> {
  late final ServerDetailViewModel vm;
  Timer? _autoTimer;

  @override
  void initState() {
    super.initState();
    vm = ServerDetailViewModel(
        baseUrl: widget.baseUrl, serverId: widget.serverId);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      vm.loadLive(refresh: false).then((_) => vm.loadMeta());
      vm.loadNetSpark();
      _restartAutoPoll();
    });
  }

  @override
  void didUpdateWidget(covariant ServerDetailScreen old) {
    super.didUpdateWidget(old);
    if (old.pollSec != widget.pollSec) _restartAutoPoll();
  }

  /// ECG driver: force-poll the open server at the user's interval so
  /// fresh samples land every second at 1s. Guarded to this route
  /// (a pushed History route pauses us — it runs its own timer) and
  /// to idle (never overlap an in-flight poll). WS pushes between
  /// polls also flow via watchLive for free.
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

  Future<void> _forcePoll() async {
    final msg = await vm.poll();
    if (!mounted) return;
    final fired = vm.live?.firedLabels ?? const [];
    if (msg != null || fired.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(children: [
            Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                    color: AppTheme.red,
                    shape: BoxShape.circle)),
            const SizedBox(width: 9),
            Expanded(
                child: Text(
                    '${fired.length} alert(s) fired${msg == null ? '' : ' · $msg'}')),
          ]),
        ),
      );
    } else if (msg != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  void _overflow() {
    final err = vm.live?.errorText;
    showAppSheet(context, title: 'Server actions', child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (err != null)
          ListTile(
            dense: true,
            leading: Icon(Icons.copy_rounded,
                size: 19, color: AppTheme.sub),
            title: Text('Copy error',
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppTheme.ink)),
            onTap: () {
              Clipboard.setData(ClipboardData(text: err));
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Error copied')));
            },
          ),
        if (err == null)
          ListTile(
            dense: true,
            leading: Icon(Icons.check_circle_outline_rounded,
                size: 19, color: AppTheme.sub),
            title: Text('No issues',
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppTheme.ink)),
            subtitle: Text('Last poll reported no error.',
                style: TextStyle(fontSize: 11, color: AppTheme.sub)),
            onTap: () => Navigator.pop(context),
          ),
      ],
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          decoration: BoxDecoration(
            color: AppTheme.bg,
            border:
                Border(top: BorderSide(color: AppTheme.border)),
          ),
          child: Row(children: [
            Expanded(
              flex: 3,
              child: FilledButton.icon(
                onPressed:
                    vm.loadingLive ? null : _forcePoll,
                icon: const Icon(Icons.bolt_rounded, size: 16),
                label: Text(vm.loadingLive
                    ? 'Polling…'
                    : 'Force poll'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: OutlinedButton.icon(
                onPressed: () =>
                    widget.onOpenHistory('cpu'),
                icon: const Icon(Icons.show_chart_rounded,
                    size: 16),
                label: const Text('History'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.ink,
                  backgroundColor: AppTheme.panel,
                  side: BorderSide(
                      color: AppTheme.border),
                  shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(
                      vertical: 13),
                ),
              ),
            ),
            IconButton(
              tooltip: 'More actions',
              icon: Icon(Icons.more_horiz_rounded,
                  color: AppTheme.sub),
              onPressed: _overflow,
            ),
          ]),
        ),
      ),
      body: ListenableBuilder(
        listenable: vm,
        builder: (context, _) {
          final live = vm.live;
          final down = live?.status == 'down';
          return RefreshIndicator(
            color: AppTheme.accent,
            onRefresh: () => vm.loadLive(refresh: false),
            child: CustomScrollView(slivers: [
              SliverAppBar(
                pinned: true,
                expandedHeight: 168,
                backgroundColor:
                    AppTheme.bg.withValues(alpha: 0.82),
                flexibleSpace: FlexibleSpaceBar(
                  titlePadding: const EdgeInsets.only(
                      left: 56, bottom: 12, right: 76),
                  title: Hero(
                    tag: 'server-title-${widget.serverId}',
                    child: Material(
                      color: Colors.transparent,
                      child: Text(widget.serverId,
                          style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.ink)),
                    ),
                  ),
                  background: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          (down
                                  ? AppTheme.red
                                  : AppTheme.accent)
                              .withValues(alpha: 0.10),
                          Colors.transparent,
                        ],
                      ),
                    ),
                    padding: const EdgeInsets.only(
                        left: 16, right: 16, top: 96),
                    child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          if (live?.hostLine != null)
                            Text(live!.hostLine!,
                                maxLines: 1,
                                overflow:
                                    TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.sub)),
                          const SizedBox(height: 4),
                          Row(children: [
                            if (widget.fromAlert)
                              Padding(
                                padding: EdgeInsets.only(
                                    right: 6),
                                child: MiniChip(
                                    'from alert',
                                    tint: AppTheme.amber,
                                    filled: true),
                              ),
                            if (live != null)
                              StatusBadge(live.status,
                                  cached: live.cached),
                            const SizedBox(width: 8),
                            if (live != null)
                              Expanded(
                                child: Text(
                                    'Last poll ${live.agoLabel}${live.durationLabel == null ? '' : ' · ${live.durationLabel}'}',
                                    maxLines: 1,
                                    overflow:
                                        TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 11.5,
                                        color: AppTheme.sub)),
                              ),
                          ]),
                        ]),
                  ),
                ),
                actions: [
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Center(
                      child: StatusOrb(live?.status ?? 'unknown',
                          size: 40,
                          onTap: vm.loadingLive
                              ? null
                              : () =>
                                  vm.loadLive(refresh: true)),
                    ),
                  ),
                ],
                bottom: PreferredSize(
                  preferredSize: Size.fromHeight(1),
                  child: SizedBox(
                      height: 1,
                      width: double.infinity,
                      child:
                          ColoredBox(color: AppTheme.border)),
                ),
              ),
              if (vm.loadingLive && live == null)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Column(children: [
                      SkeletonCard(),
                      SizedBox(height: 10),
                      SkeletonCard(),
                    ]),
                  ),
                ),
              if (live?.errorText != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding:
                        const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: ErrorCard(
                      text: live!.errorText!,
                      title: down
                          ? 'Host unreachable'
                          : 'Last poll reported an error',
                      onRetry: () =>
                          vm.loadLive(refresh: true),
                    ),
                  ),
                ),
              if (down)
                SliverToBoxAdapter(
                  child: Padding(
                    padding:
                        EdgeInsets.fromLTRB(16, 10, 16, 0),
                    child: AppCard(
                      child: Text(
                          'No metrics — host unreachable',
                          style: TextStyle(
                              fontSize: 13,
                              color: AppTheme.sub,
                              fontStyle:
                                  FontStyle.italic)),
                    ),
                  ),
                ),
              if (live != null && !down) ...[
                // LIVE ECG strip — last 60 live CPU samples, newest
                // right. Flows on every WS push + the auto force-poll
                // above, morphing between ticks (see AreaChart live).
                SliverToBoxAdapter(
                  child: Padding(
                    padding:
                        const EdgeInsets.fromLTRB(16, 10, 16, 0),
                    child: AppCard(
                      glow: AppTheme.accent,
                      child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            SectionLabel('Live CPU',
                                trailing:
                                    '${live.cpuPct?.toStringAsFixed(1) ?? '—'}% · ${widget.pollSec}s'),
                            const SizedBox(height: 8),
                            Row(children: [
                              MiniChip('LIVE · ${widget.pollSec}s',
                                  tint: AppTheme.accent,
                                  filled: true),
                              const Spacer(),
                              Text(live.agoLabel,
                                  style: TextStyle(
                                      fontSize: 11.5,
                                      color: AppTheme.sub)),
                            ]),
                            const SizedBox(height: 8),
                            vm.liveCpu.isEmpty
                                ? const ShimmerBox(height: 84)
                                : AreaChart(
                                    series: [vm.liveCpu],
                                    height: 84,
                                    compact: true,
                                    live: true,
                                  ),
                          ]),
                    ),
                  ),
                ),
                // CPU card
                SliverToBoxAdapter(
                  child: Padding(
                    padding:
                        const EdgeInsets.fromLTRB(16, 10, 16, 0),
                    child: AppCard(
                      child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            const SectionLabel('CPU'),
                            const SizedBox(height: 6),
                            Row(children: [
                              RadialGauge(
                                percent: live.cpuPct,
                                size: 104,
                                center: live.cpuPct == null
                                    ? Text('—',
                                        style: TextStyle(
                                            fontSize: 20,
                                            color:
                                                AppTheme.sub))
                                    : HeroNumber(
                                        live.cpuPct!,
                                        decimals: 1,
                                        style:
                                            AppTheme.heroNumber),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: [
                                      MiniChip(
                                          'load1 ${live.cpuLoads == null ? '—' : live.cpuLoads![0].toStringAsFixed(2)}',
                                          tint: AppTheme.accent,
                                          filled: true),
                                      MiniChip(
                                          'load5 ${live.cpuLoads == null ? '—' : live.cpuLoads![1].toStringAsFixed(2)}',
                                          tint: AppTheme.accent,
                                          filled: true),
                                      MiniChip(
                                          'load15 ${live.cpuLoads == null ? '—' : live.cpuLoads![2].toStringAsFixed(2)}',
                                          tint: AppTheme.accent,
                                          filled: true),
                                    ]),
                              ),
                            ]),
                          ]),
                    ),
                  ),
                ),
                // Memory card
                SliverToBoxAdapter(
                  child: Padding(
                    padding:
                        const EdgeInsets.fromLTRB(16, 10, 16, 0),
                    child: AppCard(
                      child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            const SectionLabel('Memory'),
                            const SizedBox(height: 6),
                            live.memPct == null
                                ? Text('—',
                                    style: AppTheme
                                        .displayNumber)
                                : HeroNumber(live.memPct!,
                                    decimals: 1),
                            const SizedBox(height: 8),
                            MeterBar(
                                percent: live.memPct),
                            if (live.memDetail != null) ...[
                              const SizedBox(height: 6),
                              Text(live.memDetail!,
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: AppTheme.sub,
                                      fontFeatures: [
                                        FontFeature
                                            .tabularFigures()
                                      ],
                                      fontFamilyFallback: [
                                        'monospace'
                                      ])),
                            ],
                          ]),
                    ),
                  ),
                ),
                // Disk card
                SliverToBoxAdapter(
                  child: Padding(
                    padding:
                        const EdgeInsets.fromLTRB(16, 10, 16, 0),
                    child: AppCard(
                      child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            SectionLabel('Disk',
                                trailing: live.diskTarget ==
                                        null
                                    ? null
                                    : 'target: ${live.diskTarget}'),
                            const SizedBox(height: 6),
                            live.diskPct == null
                                ? Text('—',
                                    style: AppTheme
                                        .displayNumber)
                                : HeroNumber(live.diskPct!,
                                    decimals: 0),
                            const SizedBox(height: 8),
                            MeterBar(
                                percent: live.diskPct),
                          ]),
                    ),
                  ),
                ),
                // Network card
                SliverToBoxAdapter(
                  child: Padding(
                    padding:
                        const EdgeInsets.fromLTRB(16, 10, 16, 0),
                    child: AppCard(
                      child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            const SectionLabel('Network'),
                            const SizedBox(height: 8),
                            ...live.netIfaces.map((n) =>
                                Padding(
                                  padding:
                                      const EdgeInsets.only(
                                          bottom: 10),
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment
                                              .start,
                                      children: [
                                        Row(children: [
                                          Text(n.name,
                                              style: TextStyle(
                                                  fontWeight:
                                                      FontWeight
                                                          .w700,
                                                  fontSize:
                                                      13,
                                                  color: AppTheme
                                                      .ink)),
                                          const Spacer(),
                                          Text(n.ratesLabel,
                                              style: TextStyle(
                                                  fontSize:
                                                      11.5,
                                                  color: AppTheme
                                                      .sub,
                                                  fontFeatures: [
                                                    FontFeature
                                                        .tabularFigures()
                                                  ],
                                                  fontFamilyFallback: [
                                                    'monospace'
                                                  ])),
                                        ]),
                                        if (n.calculating) ...[
                                          const SizedBox(
                                              height: 6),
                                          const ShimmerBox(
                                              height: 26),
                                        ] else ...[
                                          const SizedBox(
                                              height: 6),
                                          AreaChart(
                                              series: [
                                                vm.netRxSpark
                                                        .isEmpty
                                                    ? [n.rx]
                                                    : vm.netRxSpark,
                                                vm.netTxSpark
                                                        .isEmpty
                                                    ? [n.tx]
                                                    : vm.netTxSpark,
                                              ],
                                              seriesLabels: const [
                                                'rx',
                                                'tx'
                                              ],
                                              height: 52,
                                              compact: true,
                                              live: true),
                                        ],
                                      ]),
                                )),
                          ]),
                    ),
                  ),
                ),
                // System card
                if (live.uptimeLabel != null ||
                    live.sysLoads != null)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                          16, 10, 16, 0),
                      child: AppCard(
                        child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              const SectionLabel('System'),
                              if (live.uptimeLabel !=
                                  null) ...[
                                const SizedBox(height: 6),
                                Text(
                                    'Uptime ${live.uptimeLabel}',
                                    style: TextStyle(
                                        fontSize: 18,
                                        fontWeight:
                                            FontWeight.w800,
                                        color:
                                            AppTheme.ink)),
                              ],
                              if (live.sysLoads != null) ...[
                                const SizedBox(height: 8),
                                Row(children: [
                                  MetricMini(
                                      icon: Icons
                                          .speed_rounded,
                                      label: 'LOAD1',
                                      percent: null,
                                      text: live
                                          .sysLoads![0]
                                          .toStringAsFixed(
                                              2)),
                                  const SizedBox(
                                      width: 10),
                                  MetricMini(
                                      icon: Icons
                                          .speed_rounded,
                                      label: 'LOAD5',
                                      percent: null,
                                      text: live
                                          .sysLoads![1]
                                          .toStringAsFixed(
                                              2)),
                                  const SizedBox(
                                      width: 10),
                                  MetricMini(
                                      icon: Icons
                                          .speed_rounded,
                                      label: 'LOAD15',
                                      percent: null,
                                      text: live
                                          .sysLoads![2]
                                          .toStringAsFixed(
                                              2)),
                                ]),
                              ],
                            ]),
                      ),
                    ),
                  ),
              ],
              const SliverToBoxAdapter(
                  child: SizedBox(height: 26)),
            ]),
          );
        },
      ),
    );
  }
}
