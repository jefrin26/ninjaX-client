import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:james_bond/view-model/rules_view_model.dart';
import 'app_theme.dart';
import 'widgets/ui.dart';

/// VIEW LAYER — Rules, read-only and beautifully explained (spec §5).
/// Composed ONLY from widgets in `widgets/ui.dart`.
class RulesScreen extends StatefulWidget {
  final String baseUrl;
  const RulesScreen({super.key, required this.baseUrl});

  @override
  State<RulesScreen> createState() => RulesScreenState();
}

class RulesScreenState extends State<RulesScreen> {
  late final RulesViewModel vm;

  @override
  void initState() {
    super.initState();
    vm = RulesViewModel(baseUrl: widget.baseUrl);
    WidgetsBinding.instance.addPostFrameCallback((_) => vm.load());
  }

  @override
  void didUpdateWidget(covariant RulesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.baseUrl != widget.baseUrl) {
      vm.updateBaseUrl(widget.baseUrl);
      vm.load();
    }
  }

  @override
  void dispose() {
    vm.dispose();
    super.dispose();
  }

  void _jsonSheet(RuleRowData r) {
    showAppSheet(context, title: r.id, child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.panel,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.border),
          ),
          child: SelectableText(r.jsonText,
              style: TextStyle(
                  fontSize: 12.5,
                  color: AppTheme.ink,
                  fontFamilyFallback: ['monospace'])),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: r.jsonText));
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Rule JSON copied')));
            },
            icon: const Icon(Icons.copy_rounded, size: 16),
            label: const Text('Copy'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.ink,
              side: BorderSide(color: AppTheme.border),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              padding:
                  const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
      ],
    ));
  }

  Widget _ruleCard(RuleRowData r) {
    // Natural-language formula with operator + numbers emphasized.
    final metric =
        r.metric == 'disk_full' ? 'disk' : r.metric;
    return AppCard(
      onTap: () => _jsonSheet(r),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text(r.id,
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        color: AppTheme.ink)),
              ),
              MiniChip(r.serverLabel,
                  tint: r.serverLabel == 'All servers'
                      ? AppTheme.accent
                      : AppTheme.sub,
                  filled: true),
            ]),
            const SizedBox(height: 7),
            RichText(
              text: TextSpan(
                style: TextStyle(
                    fontSize: 13.5, color: AppTheme.ink),
                children: [
                  TextSpan(
                      text: '$metric.usagePct',
                      style: const TextStyle(
                          fontFamilyFallback: [
                            'monospace'
                          ])),
                  const TextSpan(text: '  '),
                  TextSpan(
                      text: r.operator,
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: AppTheme.accent)),
                  const TextSpan(text: '  '),
                  TextSpan(
                      text: r.thresholdLabel,
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: AppTheme.accent,
                          fontFeatures: [
                            FontFeature.tabularFigures()
                          ],
                          fontFamilyFallback: [
                            'monospace'
                          ])),
                  TextSpan(
                      text:
                          ' — for ${r.forConsecutive} consecutive sample${r.forConsecutive == 1 ? '' : 's'}',
                      style: TextStyle(
                          color: AppTheme.sub)),
                ],
              ),
            ),
            const SizedBox(height: 9),
            MeterBar(
                percent:
                    double.tryParse(r.thresholdLabel) ?? 0,
                max: r.scaleMax,
                threshold:
                    double.tryParse(r.thresholdLabel) ?? 0,
                height: 5),
            const SizedBox(height: 6),
            Text(
                'Fires after ${r.forConsecutive} consecutive breach${r.forConsecutive == 1 ? '' : 'es'}',
                style: TextStyle(
                    fontSize: 11.5, color: AppTheme.sub)),
          ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: vm,
      builder: (context, _) {
        final groups =
            vm.groupByMetric ? vm.metricGroups : const <String>[];
        return RefreshIndicator(
          color: AppTheme.accent,
          onRefresh: vm.load,
          child: CustomScrollView(slivers: [
            SliverAppBar(
              pinned: true,
              backgroundColor:
                  AppTheme.bg.withValues(alpha: 0.82),
              title: Row(children: [
                Text('Rules',
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.ink)),
                const SizedBox(width: 8),
                MiniChip('${vm.rows.length}',
                    tint: AppTheme.accent, filled: true),
                const Spacer(),
                const LiveDot(),
              ]),
              actions: [
                IconButton(
                  tooltip:
                      'Rules live in `alerts.json` on the host — the WebSocket API does not expose them.',
                  icon: Icon(Icons.info_outline_rounded,
                      size: 20, color: AppTheme.sub),
                  onPressed: () => ScaffoldMessenger.of(
                          context)
                      .showSnackBar(const SnackBar(
                          content: Text(
                              'Rules live in `alerts.json` on the host — the WebSocket API does not expose them.'))),
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
            SliverToBoxAdapter(
              child: Padding(
                padding:
                    const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Row(children: [
                  const Expanded(
                      child:
                          SectionLabel('Evaluation')),
                  GestureDetector(
                    onTap: vm.toggleGrouping,
                    child: Row(children: [
                      Text('Group by metric',
                          style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.sub)),
                      const SizedBox(width: 6),
                      Switch(
                        value: vm.groupByMetric,
                        activeThumbColor: AppTheme.accent,
                        onChanged: (_) =>
                            vm.toggleGrouping(),
                      ),
                    ]),
                  ),
                ]),
              ),
            ),
            if (vm.loading && vm.rows.isEmpty)
              const SliverPadding(
                padding: EdgeInsets.fromLTRB(16, 10, 16, 0),
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
                      const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: ErrorCard(
                      text: vm.error!,
                      title: 'Rules unavailable',
                      onRetry: vm.load),
                ),
              ),
            if (vm.error == null &&
                !vm.loading &&
                vm.rows.isEmpty)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: EmptyState(
                    icon: Icons.tune_rounded,
                    title: 'No rules configured.',
                    subtitle:
                        'Edit `alerts.json` on the host to add evaluation rules.',
                  ),
                ),
              ),
            if (!vm.groupByMetric)
              SliverPadding(
                padding:
                    const EdgeInsets.fromLTRB(16, 10, 16, 26),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => Padding(
                      padding: EdgeInsets.only(
                          bottom: i == vm.rows.length - 1
                              ? 0
                              : 10),
                      child: _ruleCard(vm.rows[i]),
                    ),
                    childCount: vm.rows.length,
                  ),
                ),
              ),
            if (vm.groupByMetric)
              for (final g in groups) ...[
                StickyLabel(g),
                SliverPadding(
                  padding:
                      const EdgeInsets.fromLTRB(16, 2, 16, 0),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, i) {
                        final list =
                            vm.forMetric(g);
                        return Padding(
                          padding: EdgeInsets.only(
                              bottom:
                                  i == list.length - 1
                                      ? 10
                                      : 9),
                          child:
                              _ruleCard(list[i]),
                        );
                      },
                      childCount:
                          vm.forMetric(g).length,
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
