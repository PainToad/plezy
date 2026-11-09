import '../media/media_hub.dart';

const continueWatchingSectionKey = '_continue_watching_';

/// Stable per-source identity: titles and translated labels may change.
String homeSectionKey(MediaHub hub) => hub.isContinueWatchingHub
    ? continueWatchingSectionKey
    : '${hub.serverId ?? ''}:${hub.libraryId == null ? '' : '${hub.libraryId}:'}${hub.identifier ?? hub.id}';

/// Missing sections keep their saved slot; newly discovered rows append.
List<MediaHub> arrangeHomeSections(List<MediaHub> hubs, List<String> order, List<String> hidden) {
  final ranks = <String, int>{};
  for (final key in order) {
    ranks.putIfAbsent(key, () => ranks.length);
  }
  final indexed = [
    for (var i = 0; i < hubs.length; i++)
      if (!hidden.contains(homeSectionKey(hubs[i]))) (hub: hubs[i], index: i),
  ];
  indexed.sort((a, b) {
    final rankA = ranks[homeSectionKey(a.hub)] ?? order.length + a.index;
    final rankB = ranks[homeSectionKey(b.hub)] ?? order.length + b.index;
    final result = rankA.compareTo(rankB);
    return result != 0 ? result : a.index.compareTo(b.index);
  });
  return indexed.map((entry) => entry.hub).toList();
}
