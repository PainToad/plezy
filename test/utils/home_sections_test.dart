import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/media_hub.dart';
import 'package:plezy/utils/home_sections.dart';

MediaHub hub(String id, {String server = 'one', String? title}) =>
    MediaHub(id: id, identifier: id, title: title ?? id, type: 'movie', serverId: server, items: const []);

void main() {
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
