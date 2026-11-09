// Recording UI stays hidden even when Plex returns scheduled airings.
// Premiere badges and program details remain available.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/media/ids.dart';
import 'package:plezy/media/live_tv_support.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_server_client.dart';
import 'package:plezy/media/media_library.dart';
import 'package:plezy/media/server_capabilities.dart';
import 'package:plezy/models/livetv_channel.dart';
import 'package:plezy/models/livetv_program.dart';
import 'package:plezy/models/media_grab_operation.dart';
import 'package:plezy/models/media_subscription.dart';
import 'package:plezy/providers/multi_server_provider.dart';
import 'package:plezy/screens/livetv/tabs/guide_tab.dart';
import 'package:plezy/services/multi_server_manager.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/focus/input_mode_tracker.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/multi_server_fixtures.dart';

const _episodeRatingKey = 'plex%3A%2F%2Fepisode%2F6a7fba88cb8a706b4d3047bb';

/// Reporter's scheduled grab from `/media/subscriptions/scheduled`.
const Map<String, dynamic> _scheduledGrabJson = {
  'mediaSubscriptionID': 1106,
  'mediaIndex': 0,
  'id': 'e97afe16706b598f31c62cf6a402daab8562fa64',
  'key': '/media/grabbers/operations/e97afe16706b598f31c62cf6a402daab8562fa64',
  'grabberIdentifier': 'tv.plex.grabbers.hdhomerun',
  'grabberProtocol': 'livetv',
  'deviceID': 1,
  'status': 'scheduled',
  'provider': 'tv.plex.providers.epg.cloud:2',
  'Metadata': {
    'ratingKey': _episodeRatingKey,
    'guid': 'plex://episode/6a7fba88cb8a706b4d3047bb',
    'key': '/tv.plex.providers.epg.cloud:2/metadata/$_episodeRatingKey',
    'type': 'episode',
    'title': "Motorway Cops: Catching Britain's Speeders",
  },
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('en'));
  setUp(() => LocaleSettings.setLocaleSync(AppLocale.en));

  Finder recordingDot() => find.byTooltip('Recording scheduled');

  Future<_Harness> pumpGuide(
    WidgetTester tester, {
    required Map<String, dynamic> Function(int beginsAt) gridJson,
    List<MediaGrabOperation> grabs = const [],
    List<MediaSubscription> mappingResult = const [],
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 720);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });

    final client = _DvrFakeClient(serverId: 'server-a', gridJson: gridJson)
      ..dvrSupport.grabs = grabs
      ..dvrSupport.mappingResult = mappingResult;
    final manager = MultiServerManager()..debugRegisterClientForTesting(client);
    final provider = testMultiServerProvider(manager)
      ..debugSetLiveTvServersForTesting([LiveTvServerInfo(serverId: 'server-a', dvrKey: 'dvr-a')]);
    addTearDown(provider.dispose);

    final channel = LiveTvChannel(
      key: 'channel-station-a',
      identifier: 'station-a',
      callSign: 'A',
      serverId: 'server-a',
      liveDvrKey: 'dvr-a',
    );

    await tester.pumpWidget(
      TranslationProvider(
        child: InputModeTracker(
          child: ChangeNotifierProvider<MultiServerProvider>.value(
            value: provider,
            child: MaterialApp(
              theme: monoTheme(MonoPalette.dark),
              home: Scaffold(body: GuideTab(channels: [channel])),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return _Harness(client: client);
  }

  Map<String, dynamic> subscribedEpisodeGrid(int beginsAt) => {
    'ratingKey': _episodeRatingKey,
    'guid': 'plex://episode/6a7fba88cb8a706b4d3047bb',
    'key': '/tv.plex.providers.epg.cloud:2/metadata/$_episodeRatingKey',
    'type': 'episode',
    'title': "Motorway Cops: Catching Britain's Speeders",
    'Media': [
      {'beginsAt': beginsAt, 'endsAt': beginsAt + 3600, 'channelIdentifier': 'station-a'},
    ],
  };

  testWidgets('scheduled airings have no recording badges or recording actions', (tester) async {
    final harness = await pumpGuide(
      tester,
      gridJson: (beginsAt) => {...subscribedEpisodeGrid(beginsAt), 'grandparentSubscriptionID': '1106'},
      grabs: [MediaGrabOperation.fromJson(_scheduledGrabJson)],
      mappingResult: const [MediaSubscription(key: '1106', title: 'All Episodes')],
    );

    expect(recordingDot(), findsNothing);
    expect(harness.client.dvrSupport.scheduledFetches, 0);
    expect(harness.client.dvrSupport.ruleFetches, 0);
    await tester.longPress(find.text("Motorway Cops: Catching Britain's Speeders"));
    await tester.pumpAndSettle();

    expect(find.text('Record'), findsNothing);
    expect(find.text('Manage recording'), findsNothing);
    final watchActions = find.text(t.liveTv.watchChannel).evaluate().length;
    final playActions = find.text(t.common.play).evaluate().length;
    expect(watchActions + playActions, 1);
    expect(harness.client.dvrSupport.mappingCalls, 0);
    expect(harness.client.dvrSupport.createdRequests, isEmpty);
    expect(harness.client.dvrSupport.deletedRules, isEmpty);
  });

  Map<String, dynamic> premiereGrid(int beginsAt) {
    final grid = subscribedEpisodeGrid(beginsAt);
    final airing = (grid['Media'] as List).single as Map<String, dynamic>;
    // PMS flags premieres per airing, on the Media entry.
    return {
      ...grid,
      'Media': [
        {...airing, 'premiere': '1'},
      ],
    };
  }

  testWidgets('an airing flagged as a premiere shows NEW in the guide and its sheet (issue #2186)', (tester) async {
    await pumpGuide(tester, gridJson: premiereGrid);
    expect(find.text(t.liveTv.premiereBadge), findsOneWidget);

    await tester.longPress(find.text("Motorway Cops: Catching Britain's Speeders"));
    await tester.pumpAndSettle();
    expect(find.text(t.liveTv.premiereBadge), findsNWidgets(2));
  });

  testWidgets('a repeat airing shows no NEW badge', (tester) async {
    await pumpGuide(tester, gridJson: subscribedEpisodeGrid);
    expect(find.text(t.liveTv.premiereBadge), findsNothing);
  });
}

final class _Harness {
  _Harness({required this.client});

  final _DvrFakeClient client;
}

final class _DvrFakeClient implements MediaServerClient {
  _DvrFakeClient({required String serverId, required Map<String, dynamic> Function(int beginsAt) gridJson})
    : serverId = ServerId(serverId),
      liveTvSupport = _FakeLiveTv(serverId: serverId, gridJson: gridJson);

  @override
  final ServerId serverId;
  final _FakeLiveTv liveTvSupport;

  _FakeDvr get dvrSupport => liveTvSupport.dvrSupport;

  @override
  LiveTvSupport get liveTv => liveTvSupport;

  @override
  String get serverName => serverId.value;

  @override
  MediaBackend get backend => MediaBackend.plex;

  @override
  ServerCapabilities get capabilities => const ServerCapabilities(liveTv: true, liveTvDvr: true);

  @override
  Future<List<MediaLibrary>> fetchLibraries() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FakeLiveTv implements LiveTvSupport {
  _FakeLiveTv({required this.serverId, required this.gridJson});

  final String serverId;
  final Map<String, dynamic> Function(int beginsAt) gridJson;
  final _FakeDvr dvrSupport = _FakeDvr();

  @override
  LiveTvDvrSupport? get dvr => dvrSupport;

  @override
  Future<List<LiveTvProgram>> fetchSchedule({DateTime? from, DateTime? to}) async {
    final beginsAt = from!.millisecondsSinceEpoch ~/ 1000 + 600;
    // Parse the way _parseLiveTvPrograms builds grid programs.
    return [
      LiveTvProgram.fromJson(gridJson(beginsAt)).copyWith(
        serverId: ServerId(serverId),
        serverName: serverId,
        providerIdentifier: 'tv.plex.providers.epg.cloud:2',
      ),
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FakeDvr implements LiveTvDvrSupport {
  List<MediaGrabOperation> grabs = const [];
  List<MediaSubscription> mappingResult = const [];
  final List<MediaSubscriptionCreateRequest> createdRequests = [];
  final List<String> deletedRules = [];
  int scheduledFetches = 0;
  int ruleFetches = 0;
  int mappingCalls = 0;

  @override
  Future<List<MediaGrabOperation>> fetchScheduledRecordings() async {
    scheduledFetches++;
    return grabs;
  }

  @override
  Future<List<MediaSubscription>> fetchRecordingRules({bool includeGrabs = true, bool includeStorage = true}) async {
    ruleFetches++;
    return const [];
  }

  @override
  Future<List<MediaSubscription>> fetchSubscriptionMapping({
    required String providerId,
    required List<String> ratingKeys,
    bool includeStorage = true,
  }) async {
    mappingCalls++;
    return mappingResult;
  }

  @override
  Future<void> deleteRecordingRule(String subscriptionId) async => deletedRules.add(subscriptionId);

  @override
  Future<List<SubscriptionTemplate>> getSubscriptionTemplate(String guid) async => [
    SubscriptionTemplate(
      subscriptions: [
        MediaSubscription(
          key: '',
          type: 4,
          targetLibrarySectionID: 1,
          title: 'All Episodes',
          airingsType: 'New Airings Only',
          selected: true,
        ),
      ],
    ),
  ];

  @override
  Future<MediaSubscription?> createRecordingRule(MediaSubscriptionCreateRequest request) async {
    createdRequests.add(request);
    return const MediaSubscription(key: '2011');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
