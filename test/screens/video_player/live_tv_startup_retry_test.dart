import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/screens/video_player/live_tv_startup_retry.dart';

void main() {
  test('keeps making serial attempts beyond the playback fallback limit', () async {
    final retry = LiveTvStartupRetry(delay: Duration.zero);
    var attempts = 0;
    var releases = 0;
    var inFlight = false;
    final ready = await retry.run(
      start: () async {
        expect(inFlight, isFalse);
        inFlight = true;
        expect(releases, attempts);
        attempts++;
        if (attempts == 12) return true;
        if (attempts.isOdd) throw TimeoutException('Plex tune timed out');
        return false;
      },
      isCurrent: () => true,
      beforeRetry: () async {
        releases++;
        inFlight = false;
      },
      onError: (_, _) {},
    );
    expect(ready, isTrue);
    expect(attempts, 12);
    expect(releases, 11);
  });

  test('cancelling during a tune ignores its late success', () async {
    final retry = LiveTvStartupRetry(delay: Duration.zero);
    final tune = Completer<bool>();
    var attempts = 0;
    final result = retry.run(
      start: () {
        attempts++;
        return tune.future;
      },
      isCurrent: () => true,
      beforeRetry: () async => fail('cancelled tune must not clean up the replacement'),
      onError: (_, _) => fail('cancelled tune must not report an error'),
    );
    retry.cancel();
    tune.complete(true);
    expect(await result, isFalse);
    expect(attempts, 1);
  });

  test('cancelling the retry delay completes immediately without another request', () async {
    final retry = LiveTvStartupRetry(delay: const Duration(hours: 1));
    final released = Completer<void>();
    var attempts = 0;
    final result = retry.run(
      start: () async {
        attempts++;
        return false;
      },
      isCurrent: () => true,
      beforeRetry: () async => released.complete(),
      onError: (_, _) => fail('unexpected error'),
    );
    await released.future;
    await pumpEventQueue();
    retry.cancel();
    expect(await result, isFalse);
    expect(attempts, 1);
  });

  test('a superseded request does not report or clean up a late failure', () async {
    final retry = LiveTvStartupRetry(delay: Duration.zero);
    var current = true;
    expect(
      await retry.run(
        start: () async {
          current = false;
          throw TimeoutException('old tune');
        },
        isCurrent: () => current,
        beforeRetry: () async => fail('old request must not stop the replacement'),
        onError: (_, _) => fail('old request must not report an error'),
      ),
      isFalse,
    );
  });
}
