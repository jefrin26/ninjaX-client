import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app_theme.dart';

/// VIEW LAYER — the ONLY widget library in the app.
///
/// Every screen (Servers, Detail, History, Alerts, Rules, Settings,
/// shell, sheets) is composed from the widgets in this one file.
/// Do NOT create per-screen card/row/chip widgets — reuse these.
///
/// Contents:
/// - [AppMotion] / [AppDensity]: global animation + compact switches
///   (driven by Settings, set once by the shell).
/// - [AppCard]: the only card container (20dp, hairline, rail, glow).
/// - [StatusBadge], [StatusOrb], [LiveDot], [MiniChip]: status language.
/// - [HeroNumber], [KpiChip], [MetricMini], [MeterBar]: data as hero.
/// - [FilterChips]: the only chip row (filters, segments, ranges).
/// - [RadialGauge], [AreaChart]: the only charts.
/// - [EmptyState], [ErrorCard], [ShimmerBox], [SkeletonCard],
///   [ChartSkeleton]: states (skeletons, never spinners).
/// - [SectionLabel]: all-caps micro section headers.
/// - [AppTabBar]: bottom nav with pill indicator + badge + long-press.
/// - [OfflineBanner]: thin "showing last known data" strip.
/// - [showAppSheet], [ConfirmSheet], [QuickPollSheet],
///   [showCommandPalette]: bottom sheets for every decision.

// ---------- global switches (set by shell from UiPrefs) ----------

/// Honors Settings → Appearance → Animations (+ reduced-motion).
class AppMotion {
  static bool enabled = true;
  static Duration get entry => enabled
      ? const Duration(milliseconds: 200)
      : Duration.zero;
  static Duration get value => enabled
      ? const Duration(milliseconds: 120)
      : Duration.zero;
}

/// Honors Settings → Appearance → Compact mode.
class AppDensity {
  static bool compact = false;
  static double get cardPad => compact ? 12 : 16;
}

void _tick() {
  if (AppMotion.enabled) HapticFeedback.lightImpact();
}

// ---------- the only card ----------

/// The only card container in the app. Rounded 20dp, 1px hairline,
/// optional 4dp left [rail] in a status color with soft glow, optional
/// ambient [glow] behind the card (8% opacity per spec).
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Color? rail;
  final Color? glow;
  final VoidCallback? onTap;
  const AppCard({
    super.key,
    required this.child,
    this.padding,
    this.rail,
    this.glow,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = scheme.surface;
    final border = Theme.of(context).dividerColor.withValues(alpha: 0.5);
    final content = Padding(
      padding: padding ?? EdgeInsets.all(AppDensity.cardPad),
      child: child,
    );
    final card = Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.border),
        boxShadow: [
          BoxShadow(
              color: AppTheme.cardShadow, blurRadius: 10, offset: Offset(0, 2)),
          if (glow != null)
            BoxShadow(
                color: glow!.withValues(alpha: 0.08), blurRadius: 28),
        ],
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: border, width: 0),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: rail == null
            ? content
            // NOTE: do NOT use IntrinsicHeight here. The card content
            // contains LayoutBuilder (MeterBar) and CustomPaint
            // (AreaChart), and IntrinsicHeight tries to compute their
            // intrinsic height, which throws "LayoutBuilder does not
            // support returning intrinsic dimensions" and leaves the
            // RenderIntrinsicHeight with size MISSING (box.dart:2251
            // "RenderBox was not laid out"). A Stack with a positioned
            // rail stretches to the content height without intrinsics
            // and is safe inside Dismissible + SliverList.
            : Stack(
                children: [
                  // SizedBox forces full card width: a bare Padding would
                  // shrink-wrap text-only cards (Stack gives loose
                  // constraints), while the original Row+Expanded always
                  // stretched content. Infinity resolves to maxWidth.
                  SizedBox(
                    width: double.infinity,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: content,
                    ),
                  ),
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    child: Container(
                      width: 4,
                      decoration: BoxDecoration(
                        color: rail,
                        boxShadow: [
                          BoxShadow(
                              color: rail!.withValues(alpha: 0.55),
                              blurRadius: 8),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          _tick();
          onTap!();
        },
        borderRadius: BorderRadius.circular(20),
        child: card,
      ),
    );
  }
}

// ---------- status language ----------

/// Pill status badge: `OK` / `DOWN` / `—`. Semantic colors only.
class StatusBadge extends StatelessWidget {
  final String status;
  final bool cached;
  const StatusBadge(this.status, {super.key, this.cached = false});

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.statusColor(status);
    final label = status == 'ok'
        ? 'OK'
        : status == 'down'
            ? 'DOWN'
            : '—';
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: c.withValues(alpha: 0.35)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 7,
              height: 7,
              decoration:
                  BoxDecoration(color: c, shape: BoxShape.circle)),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                  color: c,
                  fontWeight: FontWeight.w800,
                  fontSize: 10.5,
                  letterSpacing: 0.5)),
        ]),
      ),
      if (cached) ...[
        const SizedBox(width: 6),
        const MiniChip('cached'),
      ],
    ]);
  }
}

/// Soft glowing sphere (green/red) that breathes. Tap → force poll.
/// Down state: stops breathing and dims.
class StatusOrb extends StatefulWidget {
  final String status;
  final double size;
  final VoidCallback? onTap;
  const StatusOrb(this.status, {super.key, this.size = 44, this.onTap});

  @override
  State<StatusOrb> createState() => _StatusOrbState();
}

class _StatusOrbState extends State<StatusOrb>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1600));
    if (widget.status == 'ok' && AppMotion.enabled) _c.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant StatusOrb old) {
    super.didUpdateWidget(old);
    if (old.status != widget.status) {
      if (widget.status == 'ok' && AppMotion.enabled) {
        _c.repeat(reverse: true);
      } else {
        _c.stop();
      }
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.statusColor(widget.status);
    final dim = widget.status != 'ok';
    final orb = AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = dim ? 0.0 : _c.value;
        return Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: c.withValues(alpha: dim ? 0.25 : 0.35 + t * 0.2),
            boxShadow: [
              BoxShadow(
                  color: c.withValues(alpha: dim ? 0.15 : 0.35 + t * 0.25),
                  blurRadius: dim ? 8 : 16 + t * 10),
            ],
            border: Border.all(color: c.withValues(alpha: 0.6), width: 1.5),
          ),
          child: Icon(
              widget.status == 'down'
                  ? Icons.cloud_off_outlined
                  : Icons.check_rounded,
              color: c,
              size: widget.size * 0.45),
        );
      },
    );
    if (widget.onTap == null) return orb;
    return GestureDetector(
        onTap: () {
          _tick();
          widget.onTap!();
        },
        child: orb);
  }
}

/// Pulsing dot + LIVE label for the app bars.
class LiveDot extends StatefulWidget {
  const LiveDot({super.key});
  @override
  State<LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<LiveDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200));
    if (AppMotion.enabled) _c.repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: AppTheme.accent.withValues(
                alpha: AppMotion.enabled ? 0.55 + _c.value * 0.45 : 1),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                  color: AppTheme.accent.withValues(alpha: 0.5),
                  blurRadius: 6)
            ],
          ),
        ),
        const SizedBox(width: 6),
        Text('LIVE',
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
                color: AppTheme.sub)),
      ]),
    );
  }
}

/// Tiny outline/fill chip: `cached`, authType, ruleId, scope, counts.
class MiniChip extends StatelessWidget {
  final String label;
  final Color? tint;
  final bool filled;
  const MiniChip(this.label, {super.key, this.tint, this.filled = false});

  @override
  Widget build(BuildContext context) {
    final c = tint ?? AppTheme.sub;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: filled
            ? c.withValues(alpha: 0.16)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.withValues(alpha: 0.4)),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 10.5, fontWeight: FontWeight.w700, color: c)),
    );
  }
}

// ---------- data as hero ----------

/// Big tabular number that animates (count-up / crossfade) on change.
/// Digits never jitter (tabular figures + monospace fallback).
class HeroNumber extends StatefulWidget {
  final double value;
  final String suffix;
  final int decimals;
  final TextStyle? style;
  const HeroNumber(this.value,
      {super.key, this.suffix = '%', this.decimals = 1, this.style});

  @override
  State<HeroNumber> createState() => _HeroNumberState();
}

class _HeroNumberState extends State<HeroNumber> {
  double _shown = 0;
  @override
  void initState() {
    super.initState();
    _shown = widget.value;
  }

  @override
  void didUpdateWidget(covariant HeroNumber old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) {
      final from = _shown;
      final to = widget.value;
      if (!AppMotion.enabled) {
        _shown = to;
        return;
      }
      final start = DateTime.now();
      const dur = Duration(milliseconds: 120);
      Future.doWhile(() async {
        if (!mounted) return false;
        final t = DateTime.now().difference(start);
        final k = (t.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0);
        setState(() => _shown = from + (to - from) * k);
        await Future.delayed(const Duration(milliseconds: 16));
        return k < 1.0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Text('${_shown.toStringAsFixed(widget.decimals)}${widget.suffix}',
        style: widget.style ?? AppTheme.displayNumber);
  }
}

/// Tiny KPI chip for the hero strip: `Healthy N` etc.
class KpiChip extends StatelessWidget {
  final String label;
  final String value;
  final Color dot;
  const KpiChip(
      {super.key, required this.label, required this.value, required this.dot});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: AppTheme.panel,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.border),
        ),
        child: Row(children: [
          Container(
              width: 8,
              height: 8,
              decoration:
                  BoxDecoration(color: dot, shape: BoxShape.circle)),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                      color: AppTheme.sub)),
              Text(value,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.ink,
                      fontFeatures: [FontFeature.tabularFigures()],
                      fontFamilyFallback: ['monospace'])),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// One inline mini-metric: tiny icon + `CPU 42%` + micro-bar.
/// Null percent renders `—` (first poll / down host).
class MetricMini extends StatelessWidget {
  final IconData icon;
  final String label;
  final double? percent;
  final String? text;
  const MetricMini(
      {super.key,
      required this.icon,
      required this.label,
      required this.percent,
      this.text});

  @override
  Widget build(BuildContext context) {
    final shown = text ??
        (percent == null ? '—' : '${percent!.toStringAsFixed(0)}%');
    return Expanded(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 12, color: AppTheme.sub),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: AppTheme.sub)),
          const Spacer(),
          AnimatedSwitcher(
            duration: AppMotion.value,
            child: Text(shown,
                key: ValueKey(shown),
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.ink,
                    fontFeatures: [FontFeature.tabularFigures()],
                    fontFamilyFallback: ['monospace'])),
          ),
        ]),
        const SizedBox(height: 4),
        MeterBar(percent: percent, height: 4),
      ]),
    );
  }
}

/// The only progress bar. Thin, animated, threshold-colored
/// (accent < 70, amber < 90, red ≥ 90). Optional [threshold] tick
/// reuses the same widget for rule/alert threshold visuals.
class MeterBar extends StatelessWidget {
  final double? percent; // 0..100 (or 0..max)
  final double max;
  final double? threshold;
  final double height;
  const MeterBar(
      {super.key, required this.percent, this.max = 100, this.threshold, this.height = 6});

  @override
  Widget build(BuildContext context) {
    final v = percent == null
        ? 0.0
        : (percent! / max).clamp(0.0, 1.0).toDouble();
    final Color color = percent == null
        ? AppTheme.disabled
        : percent! >= 90 && max == 100
            ? AppTheme.red
            : percent! >= 70 && max == 100
                ? AppTheme.amber
                : AppTheme.accent;
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      return SizedBox(
        height: height + (threshold != null ? 3 : 0),
        child: Stack(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: v),
              duration: AppMotion.enabled
                  ? const Duration(milliseconds: 500)
                  : Duration.zero,
              curve: Curves.easeOutCubic,
              builder: (context, anim, _) => LinearProgressIndicator(
                value: anim,
                minHeight: height,
                backgroundColor: AppTheme.track,
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
          ),
          if (threshold != null)
            Positioned(
              left: ((threshold! / max).clamp(0.0, 1.0) * w) - 1,
              top: 0,
              bottom: 0,
              child: Container(
                  width: 2,
                  decoration: BoxDecoration(
                      color: AppTheme.ink,
                      borderRadius: BorderRadius.circular(2))),
            ),
        ]),
      );
    });
  }
}

// ---------- the only chip row ----------

class ChipOption {
  final String label;
  final int? count;
  const ChipOption(this.label, [this.count]);
}

/// The only chip row in the app: server filters, metric segments,
/// time ranges, alert kinds, polling intervals. Active chip has
/// accent fill; haptic tick on change.
class FilterChips extends StatelessWidget {
  final List<ChipOption> options;
  final int selected;
  final ValueChanged<int> onSelected;
  final bool segmented;
  const FilterChips({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
    this.segmented = false,
  });

  @override
  Widget build(BuildContext context) {
    final row = Row(
        mainAxisSize: MainAxisSize.min,
        children: options.indexed.map((e) {
          final i = e.$1;
          final o = e.$2;
          final sel = i == selected;
          return Padding(
            padding: EdgeInsets.only(
                right: i == options.length - 1 ? 0 : 6),
            child: GestureDetector(
              onTap: () {
                if (i == selected) return;
                _tick();
                onSelected(i);
              },
              child: AnimatedContainer(
                duration: AppMotion.value,
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: sel ? AppTheme.accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(segmented ? 12 : 999),
                  border: Border.all(
                      color: sel
                          ? Colors.transparent
                          : AppTheme.border),
                ),
                child: Text(
                    o.count == null
                        ? o.label
                        : '${o.label} ${o.count}',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: sel
                            ? AppTheme.onAccent
                            : AppTheme.sub)),
              ),
            ),
          );
        }).toList());
    if (segmented) {
      return Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: AppTheme.panel,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.border),
        ),
        child: SingleChildScrollView(
            scrollDirection: Axis.horizontal, child: row),
      );
    }
    return SingleChildScrollView(
        scrollDirection: Axis.horizontal, child: row);
  }
}

// ---------- the only charts ----------

/// Radial gauge with accent arc that sweeps to new values.
class RadialGauge extends StatelessWidget {
  final double? percent;
  final double size;
  final Widget? center;
  const RadialGauge(
      {super.key, required this.percent, this.size = 120, this.center});

  @override
  Widget build(BuildContext context) {
    final v = percent == null ? 0.0 : (percent! / 100).clamp(0.0, 1.0);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(alignment: Alignment.center, children: [
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: v),
          duration: AppMotion.enabled
              ? const Duration(milliseconds: 600)
              : Duration.zero,
          curve: Curves.easeOutCubic,
          builder: (context, anim, child) => CustomPaint(
            size: Size(size, size),
            painter: _GaugePainter(
                value: anim,
                track: AppTheme.track,
                accent: percent != null && percent! >= 90
                    ? AppTheme.red
                    : AppTheme.accent),
          ),
        ),
        Center(child: center ?? const SizedBox.shrink()),
      ]),
    );
  }
}

class _GaugePainter extends CustomPainter {
  final double value;
  final Color track;
  final Color accent;
  _GaugePainter(
      {required this.value, required this.track, required this.accent});

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 - 7;
    const start = 0.75 * 3.14159265; // 135°
    const sweep = 1.5 * 3.14159265; // 270°
    canvas.drawArc(Rect.fromCircle(center: c, radius: r), start, sweep,
        false, Paint()..color = track..strokeWidth = 9
          ..style = PaintingStyle.stroke..strokeCap = StrokeCap.round);
    if (value > 0) {
      canvas.drawArc(Rect.fromCircle(center: c, radius: r), start,
          sweep * value, false, Paint()..color = accent
            ..strokeWidth = 9..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round);
    }
  }

  @override
  bool shouldRepaint(covariant _GaugePainter old) =>
      old.value != value || old.accent != accent;
}

/// The only area chart: gradient fill accent → transparent, hairline
/// grid, minimal Y labels, crosshair + floating tooltip on scrub.
/// Multi-series for NET (rx/tx) and SYSTEM (3 loads); pass one series
/// for CPU/MEM/DISK. Same widget doubles as sparkline (compact).
class AreaChart extends StatefulWidget {
  final List<List<double>> series;
  final List<Color>? colors;
  final List<String>? seriesLabels;
  final double height;
  final bool compact;
  final String Function(int index)? tooltipFor;
  /// ECG mode: new points morph in smoothly (450ms ease-out) and a
  /// glowing head dot rides the leading edge like a hospital monitor.
  /// Set for live strips (detail LIVE card, net sparkline, history
  /// follow). Static snapshots leave it false.
  final bool live;
  const AreaChart({
    super.key,
    required this.series,
    this.colors,
    this.seriesLabels,
    this.height = 190,
    this.compact = false,
    this.tooltipFor,
    this.live = false,
  });

  @override
  State<AreaChart> createState() => _AreaChartState();
}

class _AreaChartState extends State<AreaChart>
    with SingleTickerProviderStateMixin {
  int? _scrub;
  late final AnimationController _flow;
  List<List<double>> _prev = const [];

  List<Color> get _colors => widget.colors ??
      [AppTheme.accent, AppTheme.amber, AppTheme.blue];

  @override
  void initState() {
    super.initState();
    _flow = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 450))
      ..value = 1;
    _prev = widget.series;
  }

  @override
  void dispose() {
    _flow.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant AreaChart old) {
    super.didUpdateWidget(old);
    if (old.live != widget.live) setState(() => _scrub = null);
    if (!_seriesEqual(old.series, widget.series)) {
      // Freeze the currently displayed frame as the morph source so
      // rapid 1s ticks never jump — then ease to the new target.
      _prev = _lerped(_prev, old.series, Curves.easeOutCubic
          .transform(_flow.value.clamp(0.0, 1.0)));
      if (!AppMotion.enabled) {
        _prev = widget.series;
        _flow.value = 1;
      } else {
        _flow.forward(from: 0);
      }
    }
  }

  static bool _seriesEqual(
      List<List<double>> a, List<List<double>> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var s = 0; s < a.length; s++) {
      if (a[s].length != b[s].length) return false;
      for (var i = 0; i < a[s].length; i++) {
        if (a[s][i] != b[s][i]) return false;
      }
    }
    return true;
  }

  /// Morph [from] into [to] at progress [t] (0..1). Display length
  /// follows the target; the source is resampled proportionally and
  /// right-feeling (append/push slides in, window-shift morphs each
  /// point to its successor — the ECG flow).
  static List<List<double>> _lerped(
      List<List<double>> from, List<List<double>> to, double t) {
    if (t >= 1) return to;
    if (t <= 0) return from.isEmpty ? to : from;
    final out = <List<double>>[];
    for (var s = 0; s < to.length; s++) {
      final tgt = to[s];
      final src = s < from.length ? from[s] : tgt;
      if (src.isEmpty || tgt.isEmpty) {
        out.add(List<double>.from(tgt));
        continue;
      }
      final n = tgt.length;
      final m = src.length;
      out.add(List<double>.generate(
          n,
          (i) {
            final p = src[((i * m) / n).floor().clamp(0, m - 1)];
            return p + (tgt[i] - p) * t;
          },
          growable: false));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final flat = widget.series.expand((s) => s);
    if (flat.isEmpty) {
      return Container(
        height: widget.height,
        alignment: Alignment.center,
        decoration: BoxDecoration(
            color: AppTheme.panel,
            borderRadius: BorderRadius.circular(12)),
        child: Text('No data yet',
            style: TextStyle(color: AppTheme.sub)),
      );
    }
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      final n =
          widget.series.map((s) => s.length).reduce((a, b) => a > b ? a : b);
      double xFor(int i) =>
          n <= 1 ? w / 2 : (w - 8) * i / (n - 1) + 4;
      String tip(int i) {
        if (widget.tooltipFor != null) return widget.tooltipFor!(i);
        final parts = <String>[];
        for (var s = 0; s < widget.series.length; s++) {
          final vals = widget.series[s];
          if (i < vals.length) {
            final name = widget.seriesLabels != null &&
                    s < widget.seriesLabels!.length
                ? '${widget.seriesLabels![s]} '
                : '';
            parts.add('$name${vals[i].toStringAsFixed(1)}');
          }
        }
        return parts.join(' · ');
      }

      return AnimatedBuilder(
        animation: _flow,
        builder: (context, _) {
          final t = Curves.easeOutCubic
              .transform(_flow.value.clamp(0.0, 1.0));
          final shown = _lerped(_prev, widget.series, t);
          return GestureDetector(
            onLongPressStart: (d) => setState(
                () => _scrub = _idx(d.localPosition.dx, w, n)),
            onLongPressMoveUpdate: (d) => setState(
                () => _scrub = _idx(d.localPosition.dx, w, n)),
            onHorizontalDragUpdate: (d) => setState(
                () => _scrub = _idx(d.localPosition.dx, w, n)),
            onHorizontalDragEnd: (_) =>
                setState(() => _scrub = null),
            onLongPressEnd: (_) => setState(() => _scrub = null),
            child: SizedBox(
              height: widget.height,
              child: Stack(children: [
                CustomPaint(
                  size: Size.infinite,
                  painter: _AreaPainter(
                    series: shown,
                    colors: _colors,
                    scrub: _scrub,
                    compact: widget.compact,
                    live: widget.live && _scrub == null,
                  ),
                ),
                if (_scrub != null && !widget.compact)
                  Positioned(
                    left: (xFor(_scrub!) - 70)
                        .clamp(0.0, (w - 140).clamp(0.0, w)),
                    top: 4,
                    child: Container(
                      width: 140,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppTheme.elevated,
                        borderRadius: BorderRadius.circular(10),
                        border:
                            Border.all(color: AppTheme.border),
                        boxShadow: [
                          BoxShadow(
                              color: AppTheme.cardShadow,
                              blurRadius: 10,
                              offset: Offset(0, 2)),
                        ],
                      ),
                      child: Text(tip(_scrub!),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.ink,
                              fontFeatures: [
                                FontFeature.tabularFigures()
                              ],
                              fontFamilyFallback: [
                                'monospace'
                              ])),
                    ),
                  ),
              ]),
            ),
          );
        },
      );
    });
  }

  int _idx(double dx, double w, int n) {
    if (n <= 1) return 0;
    return (((dx - 4) / (w - 8)) * (n - 1)).round().clamp(0, n - 1);
  }
}

class _AreaPainter extends CustomPainter {
  final List<List<double>> series;
  final List<Color> colors;
  final int? scrub;
  final bool compact;
  final bool live;
  _AreaPainter(
      {required this.series,
      required this.colors,
      required this.scrub,
      required this.compact,
      this.live = false});

  @override
  void paint(Canvas canvas, Size size) {
    final all = series.expand((s) => s);
    final max = all.fold<double>(0, (a, b) => b > a ? b : a);
    final denom = (max <= 0 ? 1 : max * 1.12);
    final bottomPad = compact ? 2.0 : 18.0;
    final w = size.width;
    final h = size.height - bottomPad;

    if (!compact) {
      final grid = Paint()
        ..color = AppTheme.track
        ..strokeWidth = 1;
      for (var g = 1; g <= 3; g++) {
        final y = h * g / 4;
        canvas.drawLine(Offset(0, y), Offset(w, y), grid);
      }
    }

    for (var s = 0; s < series.length; s++) {
      final vals = series[s];
      if (vals.isEmpty) continue;
      final color = colors[s % colors.length];
      final n = vals.length;
      double x(int i) => n == 1 ? w / 2 : (w - 8) * i / (n - 1) + 4;
      double y(int i) =>
          h - 3 - (vals[i].clamp(0, denom) / denom) * (h - 8);
      final path = Path()..moveTo(x(0), y(0));
      for (var i = 1; i < n; i++) {
        final x0 = x(i - 1), y0 = y(i - 1), x1 = x(i), y1 = y(i);
        final mx = (x0 + x1) / 2;
        path.cubicTo(mx, y0, mx, y1, x1, y1);
      }
      final fill = Path.from(path)
        ..lineTo(x(n - 1), h)
        ..lineTo(x(0), h)
        ..close();
      canvas.drawPath(
          fill,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                color.withValues(alpha: s == 0 ? 0.4 : 0.22),
                color.withValues(alpha: 0.04),
              ],
            ).createShader(Rect.fromLTWH(0, 0, w, h)));
      canvas.drawPath(
          path,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = compact ? 1.4 : 1.8
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round);
      if (scrub != null && !compact && scrub! < n) {
        final cx = x(scrub!), cy = y(scrub!);
        canvas.drawLine(Offset(cx, 0), Offset(cx, h),
            Paint()..color = AppTheme.cursor..strokeWidth = 1);
        canvas.drawCircle(cx.isNaN ? Offset(0, 0) : Offset(cx, cy), 3.4,
            Paint()..color = color);
        canvas.drawCircle(
            Offset(cx, cy),
            3.4,
            Paint()
              ..color = AppTheme.bg
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.4);
      }
      // Hospital-monitor head: glowing dot riding the leading edge.
      // Hidden while scrubbing so the crosshair owns the focus.
      if (live && scrub == null) {
        final hx = x(n - 1), hy = y(n - 1);
        final head = Offset(hx, hy);
        canvas.drawCircle(
            head, 7, Paint()..color = color.withValues(alpha: 0.22));
        canvas.drawCircle(head, 3.2, Paint()..color = color);
        canvas.drawCircle(
            head, 1.4, Paint()..color = const Color(0xFFFFFFFF));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _AreaPainter old) =>
      old.series != series ||
      old.scrub != scrub ||
      old.live != live ||
      old.compact != compact;
}

/// Sticky day/section header for grouped sliver lists
/// (Alerts days, Rules metric groups, Settings sections).
class StickyLabel extends StatelessWidget {
  final String text;
  const StickyLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return SliverPersistentHeader(
        pinned: true, delegate: _StickyDelegate(text));
  }
}

class _StickyDelegate extends SliverPersistentHeaderDelegate {
  final String text;
  _StickyDelegate(this.text);

  @override
  double get minExtent => 34;
  @override
  double get maxExtent => 34;

  @override
  Widget build(context, shrinkOffset, overlapsContent) {
    // Child must fill the full extent: a shorter intrinsic height
    // makes layoutExtent exceed paintExtent and crashes layout.
    return Container(
      height: maxExtent,
      color: AppTheme.bg.withValues(alpha: 0.92),
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 4),
      alignment: Alignment.centerLeft,
      child: Text(text.toUpperCase(),
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
              color: AppTheme.sub)),
    );
  }

  @override
  bool shouldRebuild(covariant _StickyDelegate old) =>
      old.text != text;
}

// ---------- states ----------

/// All-caps micro section header (spec type hierarchy).
class SectionLabel extends StatelessWidget {
  final String text;
  final String? trailing;
  const SectionLabel(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(
        child: Text(text.toUpperCase(),
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
                color: AppTheme.sub)),
      ),
      if (trailing != null)
        Text(trailing!,
            style: TextStyle(fontSize: 11.5, color: AppTheme.sub)),
    ]);
  }
}

/// Teaching empty state (never just "no data").
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(children: [
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              color: AppTheme.primarySoft, shape: BoxShape.circle),
          child: Icon(icon, size: 26, color: AppTheme.accent),
        ),
        const SizedBox(height: 12),
        Text(title,
            style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14.5,
                color: AppTheme.ink)),
        const SizedBox(height: 4),
        Text(subtitle,
            textAlign: TextAlign.center,
            style:
                TextStyle(fontSize: 12.5, color: AppTheme.sub)),
        if (actionLabel != null && onAction != null) ...[
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () {
              _tick();
              onAction!();
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.ink,
              side: BorderSide(color: AppTheme.border),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: Text(actionLabel!),
          ),
        ],
        const SizedBox(height: 10),
      ]),
    );
  }
}

/// Prominent error card: full text + Copy + Retry ghost button.
/// Replaces every banner/dialog error in the app.
class ErrorCard extends StatelessWidget {
  final String text;
  final String? title;
  final VoidCallback? onRetry;
  final String retryLabel;
  final bool showCopy;
  const ErrorCard(
      {super.key,
      required this.text,
      this.title,
      this.onRetry,
      this.retryLabel = 'Retry',
      this.showCopy = true});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppTheme.dangerSoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.dangerBorder),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.error_outline,
              color: AppTheme.red, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(title ?? 'Something failed',
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: AppTheme.red)),
          ),
          if (showCopy)
            IconButton(
              icon: Icon(Icons.copy_rounded,
                  size: 16, color: AppTheme.red),
              tooltip: 'Copy error',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: text));
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Error copied')));
              },
            ),
        ]),
        SelectableText(text,
            style:
                TextStyle(fontSize: 12.5, color: AppTheme.ink)),
        if (onRetry != null) ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () {
              _tick();
              onRetry!();
            },
            icon: const Icon(Icons.refresh_rounded, size: 15),
            label: Text(retryLabel,
                style: const TextStyle(fontSize: 12.5)),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.red,
              side: BorderSide(color: AppTheme.dangerBorder),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ]),
    );
  }
}

/// Shimmer box (first-load skeletons, never spinners).
class ShimmerBox extends StatefulWidget {
  final double? width;
  final double height;
  final double radius;
  const ShimmerBox(
      {super.key, this.width, required this.height, this.radius = 10});

  @override
  State<ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<ShimmerBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1100));
    if (AppMotion.enabled) _c.repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: AppTheme.track.withValues(
              alpha: AppMotion.enabled
                  ? 0.55 + _c.value * 0.45
                  : 0.8),
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      ),
    );
  }
}

/// Card-shaped skeleton for first-load lists.
class SkeletonCard extends StatelessWidget {
  const SkeletonCard({super.key});
  @override
  Widget build(BuildContext context) {
    return const AppCard(
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
        ShimmerBox(width: 140, height: 14),
        SizedBox(height: 10),
        ShimmerBox(height: 8),
        SizedBox(height: 6),
        ShimmerBox(height: 8),
        SizedBox(height: 6),
        ShimmerBox(width: 200, height: 8),
      ]),
    );
  }
}

/// Shimmer chart skeleton for History first load.
class ChartSkeleton extends StatelessWidget {
  final double height;
  const ChartSkeleton({super.key, this.height = 190});
  @override
  Widget build(BuildContext context) {
    return Column(children: [
      const ShimmerBox(width: 120, height: 20),
      const SizedBox(height: 10),
      ShimmerBox(height: height),
    ]);
  }
}

// ---------- bottom nav ----------

class TabItem {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  const TabItem(this.icon, this.selectedIcon, this.label);
}

/// Persistent 4-tab bar: pill active indicator, outline → filled icon
/// morph, live badge on Alerts, long-press quick actions.
class AppTabBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;
  final ValueChanged<int>? onLongPress;
  final List<TabItem> items;
  final int badge;
  final int badgeTab;
  const AppTabBar({
    super.key,
    required this.index,
    required this.onTap,
    required this.items,
    this.onLongPress,
    this.badge = 0,
    this.badgeTab = 1,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.card,
        border: Border(top: BorderSide(color: AppTheme.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
              children: items.indexed.map((e) {
            final i = e.$1;
            final t = e.$2;
            final sel = i == index;
            return Expanded(
              child: GestureDetector(
                onTap: () {
                  if (i == index) return;
                  _tick();
                  onTap(i);
                },
                onLongPress: onLongPress == null
                    ? null
                    : () {
                        _tick();
                        onLongPress!(i);
                      },
                behavior: HitTestBehavior.opaque,
                child: AnimatedContainer(
                  duration: AppMotion.value,
                  padding:
                      const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: sel
                        ? AppTheme.accent.withValues(alpha: 0.16)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                      mainAxisSize: MainAxisSize.min, children: [
                    Stack(clipBehavior: Clip.none, children: [
                      Icon(sel ? t.selectedIcon : t.icon,
                          size: 22,
                          color: sel
                              ? AppTheme.accent
                              : AppTheme.sub),
                      if (i == badgeTab && badge > 0)
                        Positioned(
                          right: -9,
                          top: -5,
                          child: Container(
                            padding:
                                const EdgeInsets.symmetric(
                                    horizontal: 5,
                                    vertical: 1),
                            decoration: BoxDecoration(
                              color: AppTheme.red,
                              borderRadius:
                                  BorderRadius.circular(999),
                            ),
                            child: Text(
                                badge > 99 ? '99+' : '$badge',
                                style: const TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white)),
                          ),
                        ),
                    ]),
                    const SizedBox(height: 3),
                    Text(t.label,
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 11,
                            color: sel
                                ? AppTheme.accent
                                : AppTheme.sub)),
                  ]),
                ),
              ),
            );
          }).toList()),
        ),
      ),
    );
  }
}

// ---------- offline ----------

/// Thin top strip when the backend is unreachable.
class OfflineBanner extends StatelessWidget {
  final VoidCallback? onRetry;
  const OfflineBanner({super.key, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onRetry == null
          ? null
          : () {
              _tick();
              onRetry!();
            },
      child: Container(
        width: double.infinity,
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.warningSoft,
          border: Border(bottom: BorderSide(color: AppTheme.warningBorder)),
        ),
        child: Row(children: [
          Icon(Icons.cloud_off_outlined,
              size: 14, color: AppTheme.warningIcon),
          const SizedBox(width: 8),
          Expanded(
            child: Text('Offline — showing last known data',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.warningText)),
          ),
          if (onRetry != null)
            Text('Retry',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.warningText)),
        ]),
      ),
    );
  }
}

// ---------- sheets for every decision ----------

/// Frosted bottom sheet shell (every decision uses a sheet,
/// never a modal dialog — except destructive confirms, which also
/// use this sheet via [ConfirmSheet]).
Future<T?> showAppSheet<T>(BuildContext context,
    {required String title, required Widget child}) {
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: AppTheme.elevated,
    barrierColor: Colors.black.withValues(alpha: 0.6),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      side: BorderSide(color: AppTheme.border),
    ),
    isScrollControlled: true,
    builder: (_) => SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 10,
            bottom: MediaQuery.of(context).viewInsets.bottom + 20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                  color: AppTheme.track,
                  borderRadius: BorderRadius.circular(999))),
          const SizedBox(height: 12),
          Text(title,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.ink)),
          const SizedBox(height: 12),
          Flexible(child: SingleChildScrollView(child: child)),
        ]),
      ),
    ),
  );
}

/// Destructive confirm with count preview before commit.
class ConfirmSheet extends StatelessWidget {
  final String message;
  final String? countPreview;
  final String confirmLabel;
  final Future<String> Function() onConfirm;
  const ConfirmSheet({
    super.key,
    required this.message,
    this.countPreview,
    this.confirmLabel = 'Delete',
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text(message,
          textAlign: TextAlign.center,
          style:
              TextStyle(fontSize: 13.5, color: AppTheme.ink)),
      if (countPreview != null) ...[
        const SizedBox(height: 10),
        MiniChip(countPreview!, tint: AppTheme.amber, filled: true),
      ],
      const SizedBox(height: 14),
      Row(children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () => Navigator.pop(context),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.ink,
              side: BorderSide(color: AppTheme.border),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(vertical: 13),
            ),
            child: const Text('Cancel'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: FilledButton(
            onPressed: () async {
              _tick();
              try {
                final msg = await onConfirm();
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text(msg)));
                }
              } catch (e) {
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Failed: $e')));
                }
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(vertical: 13),
            ),
            child: Text(confirmLabel),
          ),
        ),
      ]),
    ]);
  }

  /// One-line helper: `ConfirmSheet.show(context, …)`.
  static void show(BuildContext context,
      {required String title,
      required String message,
      String? countPreview,
      String confirmLabel = 'Delete',
      required Future<String> Function() onConfirm}) {
    showAppSheet(context,
        title: title,
        child: ConfirmSheet(
            message: message,
            countPreview: countPreview,
            confirmLabel: confirmLabel,
            onConfirm: onConfirm));
  }
}

/// Quick Poll sheet: poll-all with per-server checkboxes + tick progress.
class QuickPollSheet extends StatefulWidget {
  final List<String> serverIds;
  final Future<String> Function(String id) onPoll;
  const QuickPollSheet(
      {super.key, required this.serverIds, required this.onPoll});

  @override
  State<QuickPollSheet> createState() => _QuickPollSheetState();

  static void show(BuildContext context,
      {required List<String> serverIds,
      required Future<String> Function(String id) onPoll}) {
    showAppSheet(context,
        title: 'Poll all servers?',
        child: QuickPollSheet(serverIds: serverIds, onPoll: onPoll));
  }
}

class _QuickPollSheetState extends State<QuickPollSheet> {
  late Set<String> _picked;
  bool _running = false;
  final Map<String, String> _done = {};

  @override
  void initState() {
    super.initState();
    _picked = widget.serverIds.toSet();
  }

  Future<void> _poll() async {
    setState(() {
      _running = true;
      _done.clear();
    });
    for (final id in widget.serverIds) {
      if (!_picked.contains(id)) continue;
      try {
        _done[id] = await widget.onPoll(id);
      } catch (e) {
        _done[id] = '$e';
      }
      if (mounted) setState(() {});
    }
    if (mounted) setState(() => _running = false);
  }

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      ...widget.serverIds.map((id) {
        final picked = _picked.contains(id);
        final result = _done[id];
        return CheckboxListTile(
          value: picked,
          onChanged: _running
              ? null
              : (v) => setState(() {
                    if (v == true) {
                      _picked.add(id);
                    } else {
                      _picked.remove(id);
                    }
                  }),
          title: Text(id,
              style: TextStyle(
                  fontWeight: FontWeight.w700, color: AppTheme.ink)),
          subtitle: result == null
              ? null
              : Text(result,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 11.5, color: AppTheme.sub)),
          secondary: result != null
              ? Icon(Icons.check_circle_rounded,
                  color: AppTheme.accent)
              : null,
          activeColor: AppTheme.accent,
          contentPadding: EdgeInsets.zero,
          dense: true,
        );
      }),
      const SizedBox(height: 8),
      SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: _running || _picked.isEmpty ? null : _poll,
          icon: _running
              ? const SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.bolt_rounded, size: 16),
          label: Text(_running
              ? 'Polling ${_done.length}/${_picked.length}…'
              : 'Poll ${_picked.length} server(s)'),
        ),
      ),
    ]);
  }
}

// ---------- command palette ----------

class CommandItem {
  final String title;
  final String subtitle;
  final IconData icon;
  final Future<void> Function() run;
  const CommandItem(
      {required this.title,
      required this.subtitle,
      required this.icon,
      required this.run});
}

/// Power-user escape hatch: fuzzy search servers, metrics, actions
/// (`poll web1`, `clear cache`, `history web1 cpu`).
class CommandPalette extends StatefulWidget {
  final List<CommandItem> items;
  const CommandPalette({super.key, required this.items});

  @override
  State<CommandPalette> createState() => _CommandPaletteState();

  static void show(BuildContext context, List<CommandItem> items) {
    showAppSheet(
        context, title: 'Command', child: CommandPalette(items: items));
  }
}

class _CommandPaletteState extends State<CommandPalette> {
  String _q = '';

  List<CommandItem> get _hits {
    final q = _q.trim().toLowerCase();
    if (q.isEmpty) return widget.items;
    // Fuzzy: every query char must appear in order.
    bool fuzzy(String s) {
      var j = 0;
      for (var i = 0; i < s.length && j < q.length; i++) {
        if (s[i] == q[j]) j++;
      }
      return j == q.length;
    }

    return widget.items
        .where((c) =>
            ('${c.title} ${c.subtitle}'.toLowerCase().contains(q)) ||
            fuzzy('${c.title} ${c.subtitle}'.toLowerCase()))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      TextField(
        autofocus: true,
        decoration: InputDecoration(
          hintText: 'poll web1 · clear cache · history web1 cpu',
          prefixIcon:
              Icon(Icons.search_rounded, size: 18, color: AppTheme.sub),
        ),
        onChanged: (t) => setState(() => _q = t),
      ),
      const SizedBox(height: 8),
      Flexible(
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: _hits.length,
          itemBuilder: (_, i) {
            final c = _hits[i];
            return ListTile(
              dense: true,
              leading: Icon(c.icon, size: 18, color: AppTheme.accent),
              title: Text(c.title,
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: AppTheme.ink)),
              subtitle: Text(c.subtitle,
                  style: TextStyle(
                      fontSize: 11.5, color: AppTheme.sub)),
              onTap: () async {
                _tick();
                Navigator.pop(context);
                await c.run();
              },
            );
          },
        ),
      ),
    ]);
  }
}
