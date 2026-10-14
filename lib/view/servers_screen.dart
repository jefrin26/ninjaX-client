import 'package:flutter/material.dart';
import 'package:james_bond/view-model/servers_view_model.dart';
import 'app_theme.dart';
import 'widgets/ui.dart';

/// VIEW LAYER — Servers home, the command deck (spec §1).
/// Composed ONLY from widgets in `widgets/ui.dart`.
class ServersScreen extends StatefulWidget {
  final ServersViewModel vm;
  final ValueChanged<String> onOpenDetail;
  final void Function(String id, String metric) onOpenHistory;
  const ServersScreen({
    super.key,
    required this.vm,
    required this.onOpenDetail,
    required this.onOpenHistory,
  });

  @override
  State<ServersScreen> createState() => ServersScreenState();
}

class ServersScreenState extends State<ServersScreen>
    with SingleTickerProviderStateMixin {
  int _filter = 0; // All · Healthy · Down · Disabled
  bool _heroOpen = true;
  late final AnimationController _spin;

  ServersViewModel get vm => widget.vm;

  @override
  void initState() {
    super.initState();
    _spin = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  List<ServerRowData> get _visible {
    final rows = vm.rows;
    switch (_filter) {
      case 1:
        return rows.where((r) => r.status == 'ok').toList();
      case 2:
        return rows.where((r) => r.isDown).toList();
      case 3:
        return rows.where((r) => r.disabled).toList();
      default:
        return rows;
    }
  }

  void _palette() {
    final items = <CommandItem>[
      CommandItem(
          title: 'Poll all servers',
          subtitle: 'force-poll every host',
          icon: Icons.bolt_rounded,
          run: () async {
            await vm.pollAll();
          }),
    ];
    for (final r in vm.rows) {
      items.add(CommandItem(
          title: 'poll ${r.id}',
          subtitle: r.title,
          icon: Icons.sync_rounded,
          run: () async {
            final msg = await vm.pollServer(r.id);
            if (mounted) {
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text(msg)));
            }
          }));
      items.add(CommandItem(
          title: 'history ${r.id} cpu',
          subtitle: 'open metric history',
          icon: Icons.show_chart_rounded,
          run: () async => widget.onOpenHistory(r.id, 'cpu')));
      items.add(CommandItem(
          title: 'open ${r.id}',
          subtitle: r.title,
          icon: Icons.dns_outlined,
          run: () async => widget.onOpenDetail(r.id)));
    }
    CommandPalette.show(context, items);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: vm,
      builder: (context, _) {
        if (vm.loading && !_spin.isAnimating) _spin.repeat();
        if (!vm.loading && _spin.isAnimating) _spin.stop();
        final rows = _visible;
        return RefreshIndicator(
          color: AppTheme.accent,
          onRefresh: vm.load,
          child: CustomScrollView(slivers: [
            SliverAppBar(
              pinned: true,
              backgroundColor:
                  AppTheme.bg.withValues(alpha: 0.82),
              title: Row(children: [
                Expanded(
                  child: Text('NinjaX · ${vm.total} servers',
                      style: TextStyle(
                          fontWeight: FontWeight.w300,
                          fontSize: 17,
                          color: AppTheme.ink)),
                ),
                const LiveDot(),
              ]),
              actions: [
                IconButton(
                  tooltip: 'Command palette',
                  icon: Icon(Icons.search_rounded,
                      size: 20, color: AppTheme.sub),
                  onPressed: _palette,
                ),
                RotationTransition(
                  turns: _spin,
                  child: IconButton(
                    tooltip: 'Refresh',
                    icon: Icon(Icons.refresh_rounded,
                        size: 20, color: AppTheme.sub),
                    onPressed: vm.loading ? null : vm.load,
                  ),
                ),
              ],
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(1),
                child: Container(
                    height: 1, color: AppTheme.border),
              ),
            ),
            if (vm.error != null)
              SliverToBoxAdapter(
                  child: OfflineBanner(onRetry: vm.load)),
            // Hero strip (collapsible KPI chips)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Column(children: [
                  GestureDetector(
                    onTap: () =>
                        setState(() => _heroOpen = !_heroOpen),
                    child: Row(children: [
                      const Expanded(
                          child:
                              SectionLabel('Fleet health')),
                      Icon(
                          _heroOpen
                              ? Icons.expand_less_rounded
                              : Icons.expand_more_rounded,
                          size: 16,
                          color: AppTheme.sub),
                    ]),
                  ),
                  if (_heroOpen) ...[
                    const SizedBox(height: 8),
                    Row(children: [
                      KpiChip(
                          label: 'HEALTHY',
                          value: '${vm.healthyCount}',
                          dot: AppTheme.green),
                      const SizedBox(width: 8),
                      KpiChip(
                          label: 'DOWN',
                          value: '${vm.downCount}',
                          dot: AppTheme.red),
                      const SizedBox(width: 8),
                      KpiChip(
                          label: 'AVG CPU',
                          value: vm.cpuValue,
                          dot: AppTheme.accent),
                    ]),
                  ],
                ]),
              ),
            ),
            // Filter chips
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: FilterChips(
                  options: [
                    ChipOption('All', vm.total),
                    ChipOption('Healthy', vm.healthyCount),
                    ChipOption('Down', vm.downCount),
                    ChipOption('Disabled', vm.disabledCount),
                  ],
                  selected: _filter,
                  onSelected: (i) =>
                      setState(() => _filter = i),
                ),
              ),
            ),
            if (vm.loading && vm.rows.isEmpty)
              const SliverPadding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
                sliver: SliverList(
                  delegate: SliverChildListDelegate.fixed([
                    SkeletonCard(),
                    SizedBox(height: 10),
                    SkeletonCard(),
                    SizedBox(height: 10),
                    SkeletonCard(),
                  ]),
                ),
              ),
            if (vm.error != null && vm.rows.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding:
                      const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: ErrorCard(
                      text: vm.error!,
                      title: 'Backend unreachable',
                      onRetry: vm.load,
                      retryLabel: 'Retry'),
                ),
              ),
            if (vm.error == null &&
                !vm.loading &&
                vm.rows.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding:
                      const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: EmptyState(
                    icon: Icons.dns_outlined,
                    title: 'No servers yet',
                    subtitle:
                        'Add them to `servers.json` on the host.',
                    actionLabel: 'Test connection',
                    onAction: vm.load,
                  ),
                ),
              ),
            SliverPadding(
              padding:
                  const EdgeInsets.fromLTRB(16, 10, 16, 26),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) {
                    final r = rows[i];
                    final rail = r.isDown
                        ? AppTheme.red
                        : r.disabled
                            ? AppTheme.unknown
                            : AppTheme.green;
                    final card = AppCard(
                      rail: rail,
                      glow: r.isDown ? null : rail,
                      onTap: () =>
                          widget.onOpenDetail(r.id),
                      child: Opacity(
                        opacity: r.isDown ? 0.82 : 1,
                        child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                Expanded(
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment
                                              .start,
                                      children: [
                                        Hero(
                                          tag: 'server-title-${r.id}',
                                          child: Material(
                                            color:
                                                Colors.transparent,
                                            child: Text(r.id,
                                                style: TextStyle(
                                                    fontWeight:
                                                        FontWeight
                                                            .w600,
                                                    fontSize:
                                                        15,
                                                    color: AppTheme
                                                        .ink)),
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(r.title,
                                            maxLines: 1,
                                            overflow: TextOverflow
                                                .ellipsis,
                                            style: TextStyle(
                                                fontSize: 12,
                                                color:
                                                    AppTheme.sub)),
                                      ]),
                                ),
                                StatusBadge(r.status,
                                    cached: r.cached),
                              ]),
                              const SizedBox(height: 10),
                              Row(children: [
                                MetricMini(
                                    icon: Icons.memory_rounded,
                                    label: 'CPU',
                                    percent: r.cpuPct),
                                const SizedBox(width: 10),
                                MetricMini(
                                    icon: Icons.sd_card_outlined,
                                    label: 'MEM',
                                    percent: r.memPct),
                                const SizedBox(width: 10),
                                MetricMini(
                                    icon: Icons.storage_outlined,
                                    label: 'DISK',
                                    percent: r.diskPct),
                              ]),
                              const SizedBox(height: 8),
                              if (r.isDown && r.errorLine != null)
                                Text(r.errorLine!,
                                    maxLines: 1,
                                    overflow:
                                        TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color: AppTheme.red,
                                        fontSize: 12.5,
                                        fontWeight:
                                            FontWeight.w600)),
                              if (!r.isDown ||
                                  r.errorLine == null)
                                Text(
                                    '${r.agoLabel}${r.cached ? ' · cached' : ''}',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: AppTheme.sub)),
                            ]),
                      ),
                    );
                    // Title hero matches ServerDetailScreen's
                    // 'server-title-<id>' hero. Do NOT wrap the whole card
                    // in another Hero — a Hero cannot be the descendant of
                    // another Hero (heroes.dart:413 assertion).
                    return Padding(
                      padding: EdgeInsets.only(
                          bottom:
                              i == rows.length - 1 ? 0 : 10),
                      child: Dismissible(
                        key: ValueKey('srv-${r.id}'),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding:
                              const EdgeInsets.only(right: 20),
                          decoration: BoxDecoration(
                              color: AppTheme.panel,
                              borderRadius:
                                  BorderRadius.circular(20)),
                          child: Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.end,
                              mainAxisSize: MainAxisSize.min,
                               children: [
                                 Icon(Icons.bolt_rounded,
                                     size: 16,
                                     color: AppTheme.accent),
                                 SizedBox(width: 4),
                                 Text('Poll now',
                                     style: TextStyle(
                                         fontSize: 12,
                                         fontWeight:
                                             FontWeight.w700,
                                         color: AppTheme.sub)),
                               ]),
                        ),
                        confirmDismiss: (_) async {
                          showAppSheet(context,
                              title: r.id,
                              child: Column(
                                  mainAxisSize:
                                      MainAxisSize.min,
                                  children: [
                                    SizedBox(
                                      width: double.infinity,
                                      child: FilledButton.icon(
                                        onPressed: () async {
                                          Navigator.pop(
                                              context);
                                          final msg = await vm
                                              .pollServer(r.id);
                                          if (context.mounted) {
                                            ScaffoldMessenger.of(
                                                    context)
                                                .showSnackBar(
                                                    SnackBar(
                                                        content: Text(
                                                            msg)));
                                          }
                                        },
                                        icon: const Icon(
                                            Icons.bolt_rounded,
                                            size: 16),
                                        label: const Text(
                                            'Poll now'),
                                      ),
                                    ),
                                     const SizedBox(height: 8),
                                   ]));
                          return false;
                        },
                        child: card,
                      ),
                    );
                  },
                  childCount: rows.length,
                ),
              ),
            ),
          ]),
        );
      },
    );
  }
}
