import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:james_bond/model/ui_prefs.dart';
import 'package:james_bond/view-model/settings_view_model.dart';
import 'app_theme.dart';
import 'widgets/ui.dart';

/// VIEW LAYER — Settings, calm and grouped (spec §6).
/// Composed ONLY from widgets in `widgets/ui.dart`.
class SettingsScreen extends StatefulWidget {
  final SettingsViewModel vm;
  const SettingsScreen({super.key, required this.vm});

  @override
  State<SettingsScreen> createState() => SettingsScreenState();
}

class SettingsScreenState extends State<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController hostCtrl;
  late final TextEditingController portCtrl;

  SettingsViewModel get vm => widget.vm;

  static const _pollOptions = [1, 5, 15, 30, 60, 300];
  static const _pollLabels = ['1s', '5s', '15s', '30s', '1m', '5m'];
  static const _notifRules = [
    'host-down',
    'cpu-high',
    'mem-high',
    'disk-high',
    'load-high'
  ];

  @override
  void initState() {
    super.initState();
    hostCtrl = TextEditingController(text: vm.host);
    portCtrl = TextEditingController(text: vm.port.toString());
  }

  @override
  void dispose() {
    hostCtrl.dispose();
    portCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: vm,
      builder: (context, _) {
        final preview = vm.previewUrl(hostCtrl.text, portCtrl.text);
        final ok = vm.testResult?.startsWith('OK') ?? false;
        final pollIdx =
            _pollOptions.indexOf(vm.pollSec).clamp(0, 5);
        final themeIdx = {'light': 0, 'dark': 1, 'system': 2}[vm.theme] ?? 0;
        return CustomScrollView(slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: AppTheme.bg,
            title: Text('Settings',
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.ink)),
            bottom: PreferredSize(
              preferredSize: Size.fromHeight(1),
              child: SizedBox(
                  height: 1,
                  child: ColoredBox(color: AppTheme.border)),
            ),
          ),
          // ---- Connection ----
          const StickyLabel('Connection'),
          SliverToBoxAdapter(
            child: Padding(
              padding:
                  const EdgeInsets.fromLTRB(16, 2, 16, 0),
              child: AppCard(
                child: Form(
                  key: _formKey,
                  onChanged: () => setState(() {}),
                  child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Expanded(
                            flex: 3,
                            child: TextFormField(
                              controller: hostCtrl,
                              decoration:
                                  InputDecoration(
                                labelText: 'Backend host',
                                hintText:
                                    'localhost or 192.168.1.5',
                                prefixIcon: Icon(
                                    Icons.dns_outlined,
                                    size: 18,
                                    color: AppTheme.sub),
                              ),
                              keyboardType:
                                  TextInputType.url,
                              autocorrect: false,
                              validator: vm.validateHost,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextFormField(
                              controller: portCtrl,
                              decoration:
                                  InputDecoration(
                                labelText: 'Port',
                                prefixIcon: Icon(
                                    Icons.settings_ethernet,
                                    size: 18,
                                    color: AppTheme.sub),
                              ),
                              keyboardType:
                                  TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter
                                    .digitsOnly
                              ],
                              validator: vm.validatePort,
                            ),
                          ),
                        ]),
                        const SizedBox(height: 10),
                        SelectableText(preview,
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 12.5,
                                color: AppTheme.ink,
                                fontFamilyFallback: [
                                  'monospace'
                                ])),
                        if (vm.testResult != null) ...[
                          const SizedBox(height: 8),
                          Row(children: [
                            Icon(
                                ok
                                    ? Icons.check_circle_rounded
                                    : Icons.error_outline_rounded,
                                size: 15,
                                color: ok
                                    ? AppTheme.green
                                    : AppTheme.red),
                            const SizedBox(width: 6),
                            Expanded(
                              child: SelectableText(
                                  vm.testResult!,
                                  maxLines: 2,
                                  style: TextStyle(
                                      fontSize: 11.5,
                                      color: ok
                                          ? AppTheme.green
                                          : AppTheme.red)),
                            ),
                          ]),
                        ],
                        const SizedBox(height: 10),
                        Row(children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: vm.testing
                                  ? null
                                  : () {
                                      if (!_formKey
                                          .currentState!
                                          .validate()) {
                                        return;
                                      }
                                      vm.testConnection(
                                          hostCtrl.text,
                                          portCtrl.text);
                                    },
                              icon: const Icon(
                                  Icons.wifi_find_rounded,
                                  size: 16),
                              label: Text(vm.testing
                                  ? 'Testing…'
                                  : 'Test'),
                              style: OutlinedButton
                                  .styleFrom(
                                foregroundColor:
                                    AppTheme.ink,
                                side: BorderSide(
                                    color: AppTheme.border),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: vm.saving
                                  ? null
                                  : () async {
                                      if (!_formKey
                                          .currentState!
                                          .validate()) {
                                        return;
                                      }
                                      final port =
                                          int.tryParse(portCtrl
                                              .text
                                              .trim())!;
                                      final msg =
                                          await vm.save(
                                              hostCtrl.text,
                                              port);
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(
                                                context)
                                            .showSnackBar(SnackBar(
                                                content: Text(
                                                    msg)));
                                      }
                                    },
                              icon: const Icon(
                                  Icons.save_outlined,
                                  size: 16),
                              label: Text(vm.saving
                                  ? 'Saving…'
                                  : 'Save'),
                            ),
                          ),
                        ]),
                        const SizedBox(height: 10),
                        const SectionLabel(
                            'Polling interval'),
                        const SizedBox(height: 6),
                        FilterChips(
                          segmented: true,
                          options: _pollLabels
                              .map(ChipOption.new)
                              .toList(),
                          selected: pollIdx,
                          onSelected: (i) => vm
                              .setPollSec(_pollOptions[i]),
                        ),
                        const SizedBox(height: 10),
                        Row(children: [
                          const Expanded(
                              child: SectionLabel(
                                  'Timeout')),
                          Text('${vm.timeoutSec}s',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight:
                                      FontWeight.w700,
                                  color: AppTheme.ink,
                                  fontFeatures: [
                                    FontFeature
                                        .tabularFigures()
                                  ],
                                  fontFamilyFallback: [
                                    'monospace'
                                  ])),
                        ]),
                        Slider(
                          value: vm.timeoutSec
                              .toDouble()
                              .clamp(5, 60),
                          min: 5,
                          max: 60,
                          divisions: 11,
                          activeColor: AppTheme.accent,
                          onChanged: (v) =>
                              vm.setTimeoutSec(
                                  v.round()),
                        ),
                      ]),
                ),
              ),
            ),
          ),
          // ---- Appearance ----
          const StickyLabel('Appearance'),
          SliverToBoxAdapter(
            child: Padding(
              padding:
                  const EdgeInsets.fromLTRB(16, 2, 16, 0),
              child: AppCard(
                child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      const SectionLabel('Theme'),
                      const SizedBox(height: 6),
                      FilterChips(
                        segmented: true,
                        options: const [
                          ChipOption('Light'),
                          ChipOption('Dark'),
                          ChipOption('System'),
                        ],
                        selected: themeIdx,
                        onSelected: (i) => vm.setTheme(
                            ['light', 'dark', 'system'][i]),
                      ),
                      const SizedBox(height: 12),
                      const SectionLabel('Accent color'),
                      const SizedBox(height: 8),
                      Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            ...UiPrefs.swatches.map((c) {
                              final sel = vm.accent
                                      .toARGB32() ==
                                  c.toARGB32();
                              return GestureDetector(
                                onTap: () =>
                                    vm.setAccent(c),
                                child: AnimatedContainer(
                                  duration:
                                      AppMotion.value,
                                  width: 34,
                                  height: 34,
                                  decoration:
                                      BoxDecoration(
                                    color: c,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        color: sel
                                            ? AppTheme.ink
                                            : Colors
                                                .transparent,
                                        width: 2),
                                    boxShadow: [
                                      if (sel)
                                        BoxShadow(
                                            color: c.withValues(
                                                alpha:
                                                    0.5),
                                            blurRadius:
                                                10),
                                    ],
                                  ),
                                  child: sel
                                      ? Icon(
                                          Icons.check_rounded,
                                          size: 17,
                                          color: AppTheme
                                              .onAccent)
                                      : null,
                                ),
                              );
                            }),
                            GestureDetector(
                              onTap: () => vm.setAccent(
                                  UiPrefs.defaultAccent),
                              child: Container(
                                width: 34,
                                height: 34,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: AppTheme.border),
                                  gradient:
                                      LinearGradient(
                                          colors: [
                                        AppTheme.blue,
                                        AppTheme.accent,
                                        AppTheme.amber,
                                      ]),
                                ),
                                child: const Text('✦',
                                    style: TextStyle(
                                        fontSize: 14,
                                        color: Colors
                                            .white)),
                              ),
                            ),
                          ]),
                      Text(
                          'Dynamic (Material You) falls back to teal on devices without dynamic color.',
                          style: TextStyle(
                              fontSize: 11,
                              color: AppTheme.sub)),
                      const SizedBox(height: 12),
                      _switchRow(
                          'Animations',
                          '120–200ms eased motion',
                          vm.anims,
                          vm.setAnims),
                      _switchRow(
                          'Compact mode',
                          'Denser cards',
                          vm.compact,
                          vm.setCompact),
                    ]),
              ),
            ),
          ),
          // ---- Notifications ----
          const StickyLabel('Notifications'),
          SliverToBoxAdapter(
            child: Padding(
              padding:
                  const EdgeInsets.fromLTRB(16, 2, 16, 0),
              child: AppCard(
                child: Column(children: [
                  _switchRow(
                      'Master toggle',
                      'In-app alert badges + ticks',
                      vm.notifMaster,
                      vm.setNotifMaster),
                  Divider(
                      color: AppTheme.border,
                      height: 20),
                  ..._notifRules.map((r) => Padding(
                        padding:
                            const EdgeInsets.only(bottom: 4),
                        child: Row(children: [
                          MiniChip(r,
                              tint: r == 'host-down'
                                  ? AppTheme.red
                                  : AppTheme.amber,
                              filled: true),
                          const Spacer(),
                          Switch(
                            value: vm.notifRules
                                .contains(r),
                            activeThumbColor:
                                AppTheme.accent,
                            onChanged: vm.notifMaster
                                ? (v) => vm
                                    .toggleNotifRule(r, v)
                                : null,
                          ),
                        ]),
                      )),
                ]),
              ),
            ),
          ),
          // ---- About ----
          const StickyLabel('About'),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                  16, 2, 16, 26),
              child: AppCard(
                child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Text('NinjaX 0.1.0',
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13.5,
                              color: AppTheme.ink)),
                      const SizedBox(height: 2),
                      Text(
                          'Backend ${vm.activeBaseUrl} · made with care.',
                          style: TextStyle(
                              fontSize: 11.5,
                              color: AppTheme.sub)),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () {
                            final diag =
                                'NinjaX 0.1.0\nbackend: ${vm.activeBaseUrl}\ntheme: ${vm.theme}\naccent: ${vm.accent}\npoll: ${vm.pollSec}s\ntimeout: ${vm.timeoutSec}s';
                            Clipboard.setData(
                                ClipboardData(
                                    text: diag));
                            ScaffoldMessenger.of(
                                    context)
                                .showSnackBar(
                                    const SnackBar(
                                        content: Text(
                                            'Diagnostics copied')));
                          },
                          icon: const Icon(
                              Icons.ios_share_rounded,
                              size: 16),
                          label: const Text(
                              'Copy diagnostics'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor:
                                AppTheme.ink,
                            side: BorderSide(
                                color: AppTheme.border),
                            shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(
                                        12)),
                            padding:
                                const EdgeInsets.symmetric(
                                    vertical: 12),
                          ),
                        ),
                      ),
                    ]),
              ),
            ),
          ),
          ],
        );
      },
    );
  }

  Widget _switchRow(String title, String sub, bool value,
      ValueChanged<bool> onChanged) {
    return Row(children: [
      Expanded(
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13.5,
                      color: AppTheme.ink)),
              Text(sub,
                  style: TextStyle(
                      fontSize: 11.5, color: AppTheme.sub)),
            ]),
      ),
      Switch(
          value: value,
          activeThumbColor: AppTheme.accent,
          onChanged: onChanged),
    ]);
  }
}
