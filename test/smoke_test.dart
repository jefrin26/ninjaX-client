import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:james_bond/main.dart';
import 'package:james_bond/model/backend_settings.dart';
import 'package:james_bond/model/ui_prefs.dart';
import 'package:james_bond/view-model/settings_view_model.dart';

/// Boots the real shell (dark-first) with empty prefs and walks every
/// tab. Backend is unreachable in CI, so this exercises the offline /
/// empty / error paths — all must render without exceptions.
void main() {
  testWidgets('shell boots, onboarding skips, all tabs render',
      (t) async {
    SharedPreferences.setMockInitialValues({});
    final settings = BackendSettings();
    await settings.load();
    final prefs = UiPrefs();
    await prefs.load();
    final settingsVm =
        SettingsViewModel(settings: settings, prefs: prefs);

    await t.pumpWidget(MainApp(
        settings: settings, prefs: prefs, settingsVm: settingsVm));
    await t.pump(); // first frame: shell builds, post-frame push fires
    await t.pump(const Duration(milliseconds: 500)); // route builds

    // Onboarding shows on first run — skip it.
    expect(find.text('Your fleet, at a glance.'), findsOneWidget);
    await t.tap(find.text('Skip for now'));
    await t.pump(const Duration(milliseconds: 500));

    // Servers (offline → error card, no crash).
    await t.pump(const Duration(seconds: 1));
    expect(find.text('Servers'), findsWidgets);

    // Alerts tab.
    await t.tap(find.text('Alerts').last);
    await t.pump(const Duration(milliseconds: 500));
    expect(find.text('Alerts'), findsWidgets);

    // Rules tab.
    await t.tap(find.text('Rules').last);
    await t.pump(const Duration(milliseconds: 500));

    // Settings tab — all sections render (scroll to build lazily).
    // NOTE: every tab owns a CustomScrollView (IndexedStack), so the
    // scrollable must be scoped to SettingsScreen explicitly.
    await t.tap(find.text('Settings').last);
    await t.pump(const Duration(milliseconds: 500));
    // The page scrollable is the vertical Scrollable ancestor of a
    // sticky header (text fields own their own Scrollables, so a
    // broad descendant search matches too many).
    final settingsScroll = find.ancestor(
        of: find.text('APPEARANCE'),
        matching: find.byWidgetPredicate((w) =>
            w is Scrollable &&
            w.axisDirection == AxisDirection.down));
    expect(find.text('CONNECTION'), findsOneWidget);
    expect(find.text('APPEARANCE'), findsOneWidget);
    await t.scrollUntilVisible(find.text('NOTIFICATIONS'), 400,
        scrollable: settingsScroll, maxScrolls: 20);
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('NOTIFICATIONS'), findsOneWidget);
    await t.scrollUntilVisible(find.text('ABOUT'), 400,
        scrollable: settingsScroll, maxScrolls: 20);
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('ABOUT'), findsOneWidget);

    settingsVm.dispose();
  });
}
