import 'package:flutter/material.dart';
import 'package:james_bond/view-model/alerts_view_model.dart';
import 'package:james_bond/view-model/servers_view_model.dart';
import 'app_theme.dart';
import 'widgets/ui.dart';

/// VIEW LAYER — Alerts, the pulse of the fleet (spec §4).
/// Composed ONLY from widgets in `widgets/ui.dart`.
class AlertsScreen extends StatefulWidget {
  final AlertsViewModel vm;
  final ServersViewModel serversVm;
  final ValueChanged<String> onOpenServer;
  const AlertsScreen({
    super.key,
    required this.vm,
    required this.serversVm,
    required this.onOpenServer,
  });

  @override
  State<AlertsScreen> createState() => AlertsScreenState();
}

class AlertsScreenState extends State<AlertsScreen> {
  int _prevTotal = -1; // -1 = first load (no slide-in)

  AlertsViewModel get vm => widget.vm;

  static const _ruleIds = [
    '',
    'host-down',
    'cpu-high',
    'mem-high',
    'disk-high',
    'load-high'
  ];
  static const _ruleLabels = [
    'All',
    'host-down',
    'cpu-high',
    'mem-high',
    'disk-high',
    'load-high'
  ];

  void _filterSheet() {
    final servers = widget.serversVm.rows.map((r) => r.id).toList();
    showAppSheet(context, title: 'Filter alerts', child: StatefulBuilder(
      builder: (context, setSheet) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionLabel('Server'),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue:
                  vm.filter.isEmpty ? null : vm.filter,
              hint: const Text('All servers'),
              items: [
                const DropdownMenuItem(
                    value: '', child: Text('All servers')),
                ...servers.map((s) =>
                    DropdownMenuItem(value: s, child: Text(s))),
              ],
              onChanged: (v) {
                vm.setFilter(v ?? '');
                vm.load();
                setSheet(() {});
              },
            ),
            const SizedBox(height: 12),
            const SectionLabel('Rule'),
            const SizedBox(height: 8),
            Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _ruleIds.indexed.map((e) {
                  final sel = vm.ruleFilter == e.$2;
                  return GestureDetector(
                    onTap: () {
                      vm.setRuleFilter(e.$2);
                      setSheet(() {});
                    },
                    child: MiniChip(_ruleLabels[e.$1],
                        tint: sel
                            ? AppTheme.accent
                            : AppTheme.sub,
                        filled: sel),
                  );
                }).toList()),
            const SizedBox(height: 12),
            const SectionLabel('Time'),
            const SizedBox(height: 8),
            FilterChips(
              options: const [
                ChipOption('Today'),
                ChipOption('7D'),
                ChipOption('All'),
              ],
              selected: vm.timeFilter == 'today'
                  ? 0
                  : vm.timeFilter == '7d'
                      ? 1
                      : 2,
              onSelected: (i) {
                vm.setTimeFilter(
                    ['today', '7d', 'all'][i]);
                setSheet(() {});
              },
            ),
          ]),
    ));
  }

  void _overflow() {
    showAppSheet(context, title: 'Bulk actions', child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          dense: true,
          leading: Icon(Icons.mark_email_read_outlined,
              size: 19, color: AppTheme.sub),
          title: Text('Mark all read',
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AppTheme.ink)),
          onTap: () {
            Navigator.pop(context);
            vm.markAllRead();
          },
        ),
      ],
    ));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: vm,
      builder: (context, _) {
        final rows = vm.visibleRows;
        // New alerts slide in from the top (only rows that arrived
        // after the previous build, never the first load).
        final freshCount = _prevTotal < 0
            ? 0
            : (rows.length - _prevTotal).clamp(0, rows.length);
        if (_prevTotal != rows.length) {
          final total = rows.length;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _prevTotal = total);
          });
        }
        final groups = <String>[];
        for (final r in rows) {
          if (!groups.contains(r.dayLabel)) groups.add(r.dayLabel);
        }
        return RefreshIndicator(
          color: AppTheme.accent,
          onRefresh: vm.load,
          child: CustomScrollView(slivers: [
            SliverAppBar(
              pinned: true,
              backgroundColor:
                  AppTheme.bg.withValues(alpha: 0.82),
              title: Row(children: [
                Text('Alerts',
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.ink)),
                const SizedBox(width: 8),
                if (vm.unreadCount > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppTheme.red
                          .withValues(alpha: 0.14),
                      borderRadius:
                          BorderRadius.circular(999),
                      border: Border.all(
                          color: AppTheme.red
                              .withValues(alpha: 0.4)),
                    ),
                    child: Text('${vm.unreadCount}',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.red)),
                  ),
                const Spacer(),
                const LiveDot(),
              ]),
              actions: [
                IconButton(
                  tooltip: 'Filter',
                  icon: Icon(
                      Icons.filter_list_rounded,
                      size: 20,
                      color: AppTheme.sub),
                  onPressed: _filterSheet,
                ),
                IconButton(
                  tooltip: 'Bulk actions',
                  icon: Icon(Icons.more_horiz_rounded,
                      size: 20, color: AppTheme.sub),
                  onPressed: _overflow,
                ),
              ],
              bottom: PreferredSize(
                preferredSize: Size.fromHeight(1),
                child: SizedBox(
                    height: 1,
                    child:
                        ColoredBox(color: AppTheme.border)),
              ),
            ),
            if (vm.loading && vm.rows.isEmpty)
              const SliverPadding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
                sliver: SliverList(
                  delegate: SliverChildListDelegate.fixed([
                    SkeletonCard(),
                    SizedBox(height: 10),
                    SkeletonCard(),
                  ]),
                ),
              ),
            if (vm.error != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding:
                      const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: ErrorCard(
                      text: vm.error!,
                      title: 'Alerts unavailable',
                      onRetry: vm.load),
                ),
              ),
            if (vm.error == null &&
                !vm.loading &&
                rows.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding:
                      const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Column(children: [
                    const SizedBox(height: 26),
                    const LiveDot(),
                    const SizedBox(height: 10),
                    const EmptyState(
                      icon: Icons.mark_email_read_outlined,
                      title: 'All quiet.',
                      subtitle:
                          'No alert events. Your fleet is healthy.',
                    ),
                  ]),
                ),
              ),
            for (final day in groups) ...[
              StickyLabel(day),
              SliverPadding(
                padding:
                    const EdgeInsets.fromLTRB(16, 2, 16, 0),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, i) {
                      final dayRows = rows
                          .where((r) => r.dayLabel == day)
                          .toList();
                      final a = dayRows[i];
                      final accent = a.isHostDown
                          ? AppTheme.red
                          : AppTheme.amber;
                      final globalIdx =
                          rows.indexOf(a);
                      final fresh = globalIdx >= 0 &&
                          globalIdx < freshCount;
                      final card = AppCard(
                        rail: accent,
                        glow: fresh ? accent : null,
                        onTap: () {
                          vm.markRead(a);
                          widget.onOpenServer(a.serverId);
                        },
                        child: Row(children: [
                          Container(
                            padding:
                                const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: accent.withValues(
                                  alpha: 0.1),
                              borderRadius:
                                  BorderRadius.circular(11),
                            ),
                            child: Icon(
                                a.isHostDown
                                    ? Icons.cloud_off_outlined
                                    : Icons
                                        .warning_amber_rounded,
                                color: accent,
                                size: 20),
                          ),
                          const SizedBox(width: 11),
                          Expanded(
                            child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment
                                        .start,
                                children: [
                                  Row(children: [
                                    Expanded(
                                      child: Text(
                                          a.serverId,
                                          style: TextStyle(
                                              fontWeight:
                                                  FontWeight
                                                      .w600,
                                              fontSize: 14,
                                              color: AppTheme
                                                  .ink)),
                                    ),
                                    MiniChip(a.ruleId,
                                        tint: accent,
                                        filled: true),
                                    const SizedBox(width: 6),
                                    Text(a.agoLabel,
                                        style: TextStyle(
                                            fontSize: 11,
                                            color:
                                                AppTheme.sub)),
                                  ]),
                                  const SizedBox(height: 3),
                                  Text(a.message,
                                      maxLines: 2,
                                      overflow: TextOverflow
                                          .ellipsis,
                                      style: TextStyle(
                                          fontSize: 13,
                                          color:
                                              AppTheme.ink)),
                                  if (a.thresholdLabel
                                      .isNotEmpty) ...[
                                    const SizedBox(
                                        height: 7),
                                    MeterBar(
                                        percent: a.value,
                                        max: (a.threshold ??
                                                    0) >
                                                0
                                            ? (a.value ??
                                                        0) >
                                                    (a.threshold ??
                                                        0)
                                                ? (a.value ??
                                                        1) *
                                                    1.1
                                                : (a.threshold ??
                                                        1) *
                                                    1.2
                                            : 100,
                                        threshold:
                                            a.threshold,
                                        height: 5),
                                    const SizedBox(height: 3),
                                    Text(a.thresholdLabel,
                                        style: TextStyle(
                                            fontSize: 11.5,
                                            fontWeight:
                                                FontWeight.w700,
                                            color:
                                                AppTheme.amber,
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
                          Icon(
                              Icons.chevron_right_rounded,
                              size: 18,
                              color: AppTheme.sub),
                        ]),
                      );
                      Widget row = Padding(
                        padding: EdgeInsets.only(
                            bottom: i == dayRows.length - 1
                                ? 10
                                : 9),
                        child: Dismissible(
                          key: ValueKey(
                              'alert-${a.title}-${a.detailLine}'),
                          direction:
                              DismissDirection.endToStart,
                          background: Container(
                            alignment:
                                Alignment.centerRight,
                            padding:
                                const EdgeInsets.only(
                                    right: 20),
                            decoration: BoxDecoration(
                                color: AppTheme.panel,
                                borderRadius:
                                    BorderRadius.circular(
                                        20)),
                            child: Icon(
                                Icons
                                    .check_circle_outline_rounded,
                                color: AppTheme.sub),
                          ),
                          onDismissed: (_) =>
                              vm.dismiss(a),
                          child: card,
                        ),
                      );
                      if (fresh) {
                        row = TweenAnimationBuilder<double>(
                          tween: Tween(
                              begin: 0, end: 1),
                          duration: AppMotion.entry,
                          curve: Curves.easeOut,
                          builder: (context, t, child) =>
                              Opacity(
                            opacity: t,
                            child: Transform.translate(
                                offset: Offset(
                                    0, -14 * (1 - t)),
                                child: child),
                          ),
                          child: row,
                        );
                      }
                      return row;
                    },
                    childCount: rows
                        .where((r) => r.dayLabel == day)
                        .length,
                  ),
                ),
              ),
            ],
            const SliverToBoxAdapter(
                child: SizedBox(height: 26)),
          ]),
        );
      },
    );
  }
}
