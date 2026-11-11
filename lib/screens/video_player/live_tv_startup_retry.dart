import 'dart:async';

/// Serial startup attempts for a channel whose upstream cache is still filling.
/// A dispatched load is not success: [start] must wait for a rendered frame.
class LiveTvStartupRetry<Session> {
  LiveTvStartupRetry({this.delay = const Duration(seconds: 2)});

  final Duration delay;
  final Completer<void> _cancelled = Completer<void>();

  /// The tune and URL belong to this channel request, not to each mpv load.
  Session? session;
  String? streamUrl;
  int? offsetSeconds;
  bool startPositionResolved = false;

  void clearSession() {
    session = null;
    streamUrl = null;
    offsetSeconds = null;
    startPositionResolved = false;
  }

  bool get isCancelled => _cancelled.isCompleted;

  void cancel() {
    if (!isCancelled) _cancelled.complete();
  }

  Future<bool> run({
    required Future<bool> Function() start,
    required bool Function() isCurrent,
    required Future<void> Function() beforeRetry,
    required void Function(Object error, StackTrace stackTrace) onError,
  }) async {
    bool current() => !isCancelled && isCurrent();
    while (current()) {
      try {
        final ready = await start();
        if (!current()) return false;
        if (ready) return true;
      } catch (error, stackTrace) {
        if (!current()) return false;
        onError(error, stackTrace);
      }
      if (!current()) return false;
      await beforeRetry();
      if (!current()) return false;
      final waited = Completer<void>();
      final timer = Timer(delay, waited.complete);
      try {
        await Future.any<void>([waited.future, _cancelled.future]);
      } finally {
        timer.cancel();
      }
    }
    return false;
  }
}
