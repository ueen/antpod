import 'package:antpod/app_database.dart';
import 'package:antpod/feed_items.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';

EpisodesCompanion _item(String id, String title, DateTime date, int seconds,
        {String? url}) =>
    EpisodesCompanion.insert(
      id: id,
      podcastId: 'feed',
      podcastTitle: 'Podcast',
      podcastImageUrl: '',
      title: title,
      description: '',
      audioUrl: url ?? 'https://example.com/$id.mp3',
      durationSeconds: Value(seconds),
      publishDate: Value(date),
    );

List<String> _ids(List<EpisodesCompanion> items) =>
    [for (final e in distinctItems(items)) e.id.value];

void main() {
  group('distinctItems', () {
    test('one episode listed twice: the newer copy stays', () {
      // Open to Debate: two guids, same title, day and length.
      final items = [
        _item('old', 'Is The Two-Party System Making America Ungovernable?',
            DateTime.utc(2013, 10, 13, 1, 54), 962),
        _item('new', 'Is the two-party system making America ungovernable?',
            DateTime.utc(2013, 10, 13, 13, 42), 962),
        _item('other', 'Another', DateTime.utc(2013, 10, 6), 900),
      ];
      expect(_ids(items), ['new', 'other']);
      expect(_ids(items.reversed.toList()), ['other', 'new'],
          reason: 'the order of the feed makes no difference');
    });

    test('the same guid twice: once', () {
      final d = DateTime.utc(2026, 1, 1);
      expect(_ids([_item('a', 'A', d, 60), _item('a', 'A', d, 60)]), ['a']);
    });

    test('news under one title, of other lengths, all stay', () {
      final items = [
        for (var h = 6; h < 9; h++)
          _item('$h', 'Hourly news', DateTime.utc(2026, 1, 1, h), 300 + h * 5),
      ];
      expect(_ids(items), ['6', '7', '8']);
    });

    test('same title and audio under two guids: once', () {
      final items = [
        _item('a', 'A', DateTime.utc(2026, 1, 1), 60, url: 'https://x/a.mp3'),
        _item('b', 'A', DateTime.utc(2026, 3, 1), 0, url: 'https://x/a.mp3'),
      ];
      expect(_ids(items), ['b']);
    });
  });

  group('twinOf', () {
    final now = DateTime.utc(2026, 1, 1, 12);
    ItemFacts f(String id, String title, DateTime d, int s, [String? url]) =>
        itemFacts(_item(id, title, d, s, url: url));

    test('a re-upload: same title, day and about the length', () {
      final old = f('a', 'Kingdom Come 1', now, 3000);
      expect(twinOf(old, [f('b', 'kingdom come 1', now, 3100)]), 'b');
      expect(twinOf(old, [f('b', 'Kingdom Come 1', now, 2000)]), isNull,
          reason: 'too far off in length');
      expect(
          twinOf(old,
              [f('b', 'Kingdom Come 1', now.add(const Duration(days: 2)), 3000)]),
          isNull,
          reason: 'another day');
    });

    test('a shared placeholder audio is no match', () {
      final old = f('a', 'Locked 1', now, 0, 'https://x/locked.mp3');
      final items = [
        f('b', 'Locked 2', now, 0, 'https://x/locked.mp3'),
        f('c', 'Locked 3', now, 0, 'https://x/locked.mp3'),
      ];
      expect(twinOf(old, items), isNull);
    });
  });

  group('findHit: a search hit in its feed', () {
    final now = DateTime.utc(2026, 1, 1, 12);
    final items = [
      itemFacts(_item('g1', 'News', now, 300, url: 'https://x/1.mp3')),
      itemFacts(_item('g2', 'News', now.subtract(const Duration(days: 1)), 300,
          url: 'https://x/2.mp3')),
      itemFacts(_item('g3', 'The “Big” One — Part 1', now, 3000,
          url: 'https://x/3.mp3')),
    ];
    ItemFacts hit(
            {String id = '', String title = '', DateTime? date, String url = ''}) =>
        (id: id, title: titleKey(title), date: date, seconds: 0, url: url);

    test('by guid first, whatever the rest says', () {
      expect(findHit(hit(id: 'g2', title: 'Other', url: 'https://x/1.mp3'), items), 1);
    });

    test('else by audio, http or https', () {
      expect(findHit(hit(id: 'apple-1', url: 'http://x/3.mp3'), items), 2);
    });

    test('else by title, the one nearest in date', () {
      expect(findHit(hit(title: 'the "big" one - part 1'), items), 2);
      expect(
          findHit(hit(title: 'News', date: now.subtract(const Duration(hours: 20))),
              items),
          1);
      expect(findHit(hit(title: 'News', date: now), items), 0);
    });

    test('nothing alike, no match', () {
      expect(findHit(hit(id: 'x', title: 'Gone', url: 'https://y/z.mp3'), items),
          isNull);
      expect(findHit(hit(), [itemFacts(_item('e', '', now, 0, url: ''))]), isNull,
          reason: 'no title is no title match');
    });
  });

  group('parseFeedDate', () {
    test('RFC 822 as podcasters write it', () {
      expect(parseFeedDate('Mon, 03 Jun 2019 10:00:00 +0000'),
          DateTime.utc(2019, 6, 3, 10));
      expect(parseFeedDate('Di, 03 Okt 2023 10:00:00 MESZ'),
          DateTime.utc(2023, 10, 3, 8));
      expect(parseFeedDate('3 Dez. 2023 10:00 +0100'),
          DateTime.utc(2023, 12, 3, 9));
      expect(parseFeedDate('Wed, 1 May 24 18:30:00 EDT'),
          DateTime.utc(2024, 5, 1, 22, 30));
      expect(parseFeedDate('mardi, 12 févr. 2025 07:15:00 GMT'),
          DateTime.utc(2025, 2, 12, 7, 15));
      expect(parseFeedDate('12 September 2025'), DateTime.utc(2025, 9, 12));
    });

    test('ISO 8601', () {
      expect(parseFeedDate('2024-05-01T18:30:00+02:00'),
          DateTime.utc(2024, 5, 1, 16, 30));
    });

    test('nothing it can read: none', () {
      expect(parseFeedDate(''), isNull);
      expect(parseFeedDate('soon'), isNull);
      expect(parseFeedDate('03 Foo 2023 10:00:00'), isNull);
      expect(parseFeedDate('32 Jan 2023'), isNull);
    });
  });

  test('normalizePubDates rewrites what podcast_search would fail on', () {
    const xml = '<item><pubDate> Di, 03 Okt 2023 10:00:00 MESZ </pubDate></item>'
        '<item><pubDate><![CDATA[gestern]]></pubDate></item>';
    expect(
        normalizePubDates(xml),
        '<item><pubDate>Tue, 03 Oct 2023 08:00:00 +0000</pubDate></item>'
        '<item><pubDate></pubDate></item>');
  });
}
