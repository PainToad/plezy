import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/connection/connection_registry.dart';
import 'package:plezy/database/app_database.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/navigation/navigation_tabs.dart';
import 'package:plezy/profiles/active_profile_provider.dart';
import 'package:plezy/profiles/plex_home_service.dart';
import 'package:plezy/profiles/profile_connection_registry.dart';
import 'package:plezy/profiles/profile_registry.dart';
import 'package:plezy/screens/settings/general_settings_screen.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/utils/platform_detector.dart';
import 'package:plezy/widgets/focusable_list_tile.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/prefs.dart';

void main() {
  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    TvDetectionService.debugReset();
    await TvDetectionService.getInstance();
    addTearDown(TvDetectionService.debugReset);
    await SettingsService.getInstance();
    LocaleSettings.setLocaleSync(AppLocale.en);
  });

  Future<({AppDatabase database, PlexHomeService plexHome, ActiveProfileProvider activeProfile})> pumpGeneralScreen(
    WidgetTester tester, {
    TargetPlatform? platform,
    double width = 1000,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 1400);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final database = AppDatabase.forTesting(NativeDatabase.memory());
    final connections = ConnectionRegistry(database);
    final profileConnections = ProfileConnectionRegistry(database);
    final profiles = ProfileRegistry(database);
    final plexHome = PlexHomeService(
      connections: connections,
      profileConnections: profileConnections,
      plexHomeUserFetcher: (_) async => const [],
    );
    // Never initialized: zero profiles, so hasMultipleProfiles stays false.
    final activeProfile = ActiveProfileProvider(
      registry: profiles,
      plexHome: plexHome,
      connections: connections,
      profileConnections: profileConnections,
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<ActiveProfileProvider>.value(
        value: activeProfile,
        child: MaterialApp(
          theme: monoTheme(MonoPalette.dark).copyWith(platform: platform),
          home: const GeneralSettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (database: database, plexHome: plexHome, activeProfile: activeProfile);
  }

  Future<void> disposeHarness(
    WidgetTester tester,
    ({AppDatabase database, PlexHomeService plexHome, ActiveProfileProvider activeProfile}) harness,
  ) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    harness.activeProfile.dispose();
    await harness.plexHome.dispose();
    await harness.database.close();
  }

  testWidgets('shows language and startup tiles, hides the profile prompt for a single profile', (tester) async {
    final harness = await pumpGeneralScreen(tester);

    expect(find.text(t.settings.language), findsOneWidget);
    expect(find.text(t.settings.startupSection), findsOneWidget);
    // Only meaningful with several profiles; a lone profile has nothing to pick.
    expect(find.text(t.settings.requireProfileSelectionOnOpen), findsNothing);
    // The test host is a desktop OS, so the window group applies.
    expect(find.text(t.settings.startInFullscreen), findsOneWidget);

    await disposeHarness(tester, harness);
  });

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    for (final width in [390.0, 1024.0]) {
      testWidgets('interface mode switches both ways on $platform at width $width', (tester) async {
        final harness = await pumpGeneralScreen(tester, platform: platform, width: width);
        expect(find.text('Automatic'), findsOneWidget);
        await tester.tap(find.text('Interface mode'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('TV').last);
        await tester.pumpAndSettle();
        expect(SettingsService.instance.read(SettingsService.forceTvMode), isTrue);
        expect(SettingsService.instance.prefs.getBool(SettingsService.forceTvMode.key), isTrue);
        expect(PlatformDetector.isTV(), isTrue);
        expect(PlatformDetector.isTVDevice(), isFalse);

        // The control remains reachable in the TV layout, without a restart.
        await tester.tap(find.text('Interface mode'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Automatic').last);
        await tester.pumpAndSettle();
        expect(SettingsService.instance.read(SettingsService.forceTvMode), isFalse);
        expect(PlatformDetector.isTV(), isFalse);
        await disposeHarness(tester, harness);
      });
    }
  }

  testWidgets('TV hardware only shows a locked TV interface mode', (tester) async {
    TvDetectionService.debugSetAppleTVOverride(true);
    final harness = await pumpGeneralScreen(tester);
    final tile = find.widgetWithText(FocusableListTile, 'Interface mode');
    expect(tester.widget<FocusableListTile>(tile).enabled, isFalse);
    expect(find.text('TV (required on this device)'), findsOneWidget);
    expect(SettingsService.instance.read(SettingsService.forceTvMode), isFalse);
    expect(PlatformDetector.isTV(), isTrue);
    await tester.tap(find.text('Interface mode'));
    await tester.pumpAndSettle();
    expect(find.text('Automatic'), findsNothing);
    expect(PlatformDetector.isTV(), isTrue);
    await disposeHarness(tester, harness);
  });

  testWidgets('changes the persisted startup section', (tester) async {
    final harness = await pumpGeneralScreen(tester);

    await tester.tap(find.text(t.settings.startupSection));
    await tester.pumpAndSettle();
    final librariesLabel = allNavigationTabs.firstWhere((tab) => tab.id == NavigationTabId.libraries).getLabel();
    await tester.tap(find.text(librariesLabel).last);
    await tester.pumpAndSettle();

    final settings = SettingsService.instance;
    expect(settings.read(SettingsService.startupSection), NavigationTabId.libraries);
    expect(settings.prefs.getString(SettingsService.startupSection.key), 'libraries');

    await disposeHarness(tester, harness);
  });
}
