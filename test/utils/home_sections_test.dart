import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/media_hub.dart';
import 'package:plezy/utils/home_sections.dart';

MediaHub hub(String id, {String server = 'one', String? title}) =>
    MediaHub(id: id, identifier: id, title: title ?? id, type: 'movie', serverId: server, items: const []);

void main() {
  test('one Music choice hides current and newly personalized music rows across servers', () {
    const recent = MediaHub(id: 'recent', title: 'Recently played', type: 'album', serverId: 'one', items: []);
    const dynamic = MediaHub(id: 'mix-new', title: 'A new mix', type: 'track', serverId: 'two', items: []);
    final movie = hub('latest');
    expect(arrangeHomeSections([recent, movie, dynamic], [], [musicSectionKey]), [movie]);
    expect(arrangeHomeSections([recent, movie, dynamic], [], []), [recent, movie, dynamic]);
    expect(homeSectionKey(recent), homeSectionKey(dynamic));
    expect(homeRowKey(recent), isNot(homeRowKey(dynamic)));
  });

  test('Music reorders as a group without changing the server order of its rows', () {
    const first = MediaHub(id: 'mix-1', title: 'First mix', type: 'artist', items: []);
    const second = MediaHub(id: 'mix-2', title: 'Second mix', type: 'album', items: []);
    final movie = hub('latest');
    expect(arrangeHomeSections([first, movie, second], [musicSectionKey, 'one:latest'], []), [first, second, movie]);
  });

  test('hidden rows are removed and saved ordering spans Continue Watching and library rows', () {
    final rows = [hub('continue_watching'), hub('latest'), hub('popular')];
    final arranged = arrangeHomeSections(
      rows,
      ['one:popular', continueWatchingSectionKey, 'one:latest'],
      ['one:latest'],
    );
    expect(arranged.map((row) => row.id), ['popular', 'continue_watching']);
  });

  test('new rows append and missing rows keep their rank when they return', () {
    final order = ['one:popular', 'one:latest'];
    expect(arrangeHomeSections([hub('latest'), hub('new')], order, []).map((row) => row.id), ['latest', 'new']);
    expect(arrangeHomeSections([hub('latest'), hub('new'), hub('popular')], order, []).map((row) => row.id), [
      'popular',
      'latest',
      'new',
    ]);
  });

  test('titles do not identify rows and different servers keep separate controls', () {
    final first = hub('latest', title: 'Latest movies');
    final second = hub('latest', server: 'two', title: 'Latest movies');
    expect(arrangeHomeSections([first, second], [], ['one:latest']), [second]);
    expect(homeSectionKey(hub('latest', title: 'Renamed')), homeSectionKey(first));
  });
}
