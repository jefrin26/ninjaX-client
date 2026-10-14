import 'package:flutter/material.dart';
import 'package:james_bond/view-model/settings_view_model.dart';
import 'app_theme.dart';
import 'widgets/ui.dart';

/// First-run onboarding (spec §7): 3 slides in 15 seconds, then a
/// single Backend URL field → Connect → health check → Home.
class OnboardingScreen extends StatefulWidget {
  final SettingsViewModel vm;
  const OnboardingScreen({super.key, required this.vm});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _page = PageController();
  int _slide = 0;
  late final TextEditingController _hostCtrl;
  late final TextEditingController _portCtrl;
  bool _ok = false;

  @override
  void initState() {
    super.initState();
    _hostCtrl = TextEditingController(text: widget.vm.host);
    _portCtrl = TextEditingController(text: '${widget.vm.port}');
    widget.vm.addListener(_sync);
  }

  void _sync() {
    if (!mounted) return;
    final ok = (widget.vm.testResult ?? '').startsWith('OK');
    if (ok != _ok) setState(() => _ok = ok);
    setState(() {});
  }

  @override
  void dispose() {
    widget.vm.removeListener(_sync);
    _page.dispose();
    _hostCtrl.dispose();
    _portCtrl.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    await widget.vm.testConnection(_hostCtrl.text, _portCtrl.text);
    if (!mounted) return;
    if ((widget.vm.testResult ?? '').startsWith('OK')) {
      final port = int.tryParse(_portCtrl.text.trim()) ?? widget.vm.port;
      await widget.vm.save(_hostCtrl.text, port);
      await widget.vm.prefs.markOnboardSeen();
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: SafeArea(
        child: Column(children: [
          const SizedBox(height: 18),
          const LiveDot(),
          const SizedBox(height: 6),
          Expanded(
            child: PageView(
              controller: _page,
              onPageChanged: (i) => setState(() => _slide = i),
              children: const [
                _Slide(
                  title: 'Your fleet, at a glance.',
                  subtitle:
                      'Every server on one calm canvas. Glanceable in under 2 seconds.',
                  child: _SlideServers(),
                ),
                _Slide(
                  title: 'Live metrics, zero noise.',
                  subtitle:
                      'CPU, memory, disk and network as the hero. Nulls and down hosts handled gracefully.',
                  child: _SlideGauge(),
                ),
                _Slide(
                  title: 'Alerts that matter.',
                  subtitle:
                      'Threshold breaches and host-down events slide in — nothing else.',
                  child: _SlideAlert(),
                ),
              ],
            ),
          ),
          Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(3, (i) {
                final sel = i == _slide;
                return AnimatedContainer(
                  duration: AppMotion.value,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: sel ? 22 : 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: sel ? AppTheme.accent : AppTheme.track,
                    borderRadius: BorderRadius.circular(999),
                  ),
                );
              })),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: AppCard(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionLabel('Backend URL'),
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: _hostCtrl,
                          decoration: const InputDecoration(
                              hintText: 'hostname or IP'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _portCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                              hintText: 'port'),
                        ),
                      ),
                    ]),
                    if (widget.vm.testResult != null) ...[
                      const SizedBox(height: 8),
                      Text(widget.vm.testResult!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 11.5,
                              color: _ok
                                  ? AppTheme.green
                                  : AppTheme.red)),
                    ],
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed:
                            widget.vm.testing ? null : _connect,
                        icon: _ok
                            ? const Icon(Icons.celebration_rounded,
                                size: 16)
                            : const Icon(Icons.bolt_rounded,
                                size: 16),
                        label: Text(widget.vm.testing
                            ? 'Connecting…'
                            : 'Connect'),
                      ),
                    ),
                    Center(
                      child: TextButton(
                        onPressed: () async {
                          await widget.vm.prefs.markOnboardSeen();
                          if (context.mounted) {
                            Navigator.of(context).pop();
                          }
                        },
                        child: Text('Skip for now',
                            style: TextStyle(
                                fontSize: 12,
                                color: AppTheme.sub)),
                      ),
                    ),
                  ]),
            ),
          ),
        ]),
      ),
    );
  }
}

class _Slide extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;
  const _Slide(
      {required this.title, required this.subtitle, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Column(children: [
        const SizedBox(height: 10),
        child,
        const SizedBox(height: 18),
        Text(title,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
                color: AppTheme.ink)),
        const SizedBox(height: 6),
        Text(subtitle,
            textAlign: TextAlign.center,
            style:
                TextStyle(fontSize: 13.5, color: AppTheme.sub)),
      ]),
    );
  }
}

/// Slide 1: animated server cards (reuses AppCard + StatusBadge).
class _SlideServers extends StatelessWidget {
  const _SlideServers();
  @override
  Widget build(BuildContext context) {
    return Column(children: [
      AppCard(
          rail: AppTheme.green,
          child: Row(children: [
            Text('web1',
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppTheme.ink)),
            Spacer(),
            StatusBadge('ok'),
          ])),
      SizedBox(height: 8),
      AppCard(
          rail: AppTheme.red,
          child: Row(children: [
            Text('db1',
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppTheme.ink)),
            Spacer(),
            StatusBadge('down'),
          ])),
    ]);
  }
}

/// Slide 2: radial gauge sweeping (reuses RadialGauge + HeroNumber).
class _SlideGauge extends StatelessWidget {
  const _SlideGauge();
  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Center(
        child: RadialGauge(
          percent: 42.3,
          size: 130,
          center: HeroNumber(42.3,
              decimals: 1, style: AppTheme.heroNumber),
        ),
      ),
    );
  }
}

/// Slide 3: alert row sliding in (reuses AppCard + MeterBar tick).
class _SlideAlert extends StatelessWidget {
  const _SlideAlert();
  @override
  Widget build(BuildContext context) {
    return AppCard(
      rail: AppTheme.amber,
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('web1',
              style: TextStyle(
                  fontWeight: FontWeight.w700, color: AppTheme.ink)),
          SizedBox(width: 6),
          MiniChip('cpu-high', tint: AppTheme.amber, filled: true),
        ]),
        SizedBox(height: 6),
        Text('CPU usage above threshold',
            style: TextStyle(fontSize: 13, color: AppTheme.ink)),
        SizedBox(height: 8),
        MeterBar(percent: 95.2, threshold: 90),
        SizedBox(height: 4),
        Text('95.2 > 90',
            style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: AppTheme.amber,
                fontFeatures: [FontFeature.tabularFigures()],
                fontFamilyFallback: ['monospace'])),
      ]),
    );
  }
}
