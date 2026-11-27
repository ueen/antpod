import 'dart:io';

import 'package:antpod/app_database.dart';
import 'package:antpod/feed_sync.dart';
import 'package:antpod/podcast_service.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

String _rss(List<String> guids, {String head = ''}) => '''<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd">
<channel>
<title>Test</title>$head
<description>About</description>
<itunes:image href="https://example.com/cover.jpg"/>
${[for (final g in guids) '<item><title>Episode $g</title><guid>$g</guid>'
    '<enclosure url="https://example.com/$g.mp3" type="audio/mpeg" length="1"/>'
    '<pubDate>Mon, 05 Jan 2026 10:00:00 GMT</pubDate></item>'].join('\n')}
</channel>
</rss>''';

/// A feed the test server serves.
class _Feed {
  String body;
  int status;
  /// Answers If-None-Match with 304, like a well-behaved server.
  bool conditional;
  int requests = 0;
  int notModified = 0;
  /// Redirects with [status] to this path instead.
  final String? to;
  _Feed(this.body, {this.status = 200, this.conditional = true}) : to = null;
  _Feed.redirect(this.to, this.status) : body = '', conditional = false;
  String get etag => '"${body.hashCode}"';
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late HttpServer server;
  final feeds = <String, _Feed>{};
  String url(String path) => 'http://127.0.0.1:${server.port}/$path';

  setUpAll(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) {
      final feed = feeds[req.uri.path.substring(1)];
      final res = req.response;
      if (feed == null) {
        res.statusCode = 404;
      } else {
        feed.requests++;
        if (feed.to case final to?) {
          res.statusCode = feed.status;
          res.headers.set('location', '/$to');
        } else if (feed.conditional &&
            req.headers.value('if-none-match') == feed.etag) {
          feed.notModified++;
          res.statusCode = 304;
        } else {
          res.statusCode = feed.status;
          if (feed.conditional) res.headers.set('etag', feed.etag);
          res.write(feed.body);
        }
      }
      res.close();
    });
  });
  tearDownAll(() => server.close(force: true));
  setUp(feeds.clear);

  group('fetchFeed', () {
    test('an unchanged feed answers 304 and is not parsed', () async {
      feeds['a'] = _Feed(_rss(['1', '2']));
      final first = (await PodcastService.fetchFeed(url('a')))!;
      expect(first.data!.episodes, hasLength(2));
      expect(first.validators.etag, feeds['a']!.etag);

      final again = (await PodcastService.fetchFeed(url('a'), known: first.validators))!;
      expect(feeds['a']!.notModified, 1);
      expect(again.data, isNull);
      expect(again.validators, first.validators);
    });

    test('a server without validators: the same body is not parsed', () async {
      feeds['a'] = _Feed(_rss(['1']), conditional: false);
      final first = (await PodcastService.fetchFeed(url('a')))!;
      expect(first.validators.etag, isNull);
      final again = (await PodcastService.fetchFeed(url('a'), known: first.validators))!;
      expect(again.data, isNull);

      feeds['a']!.body = _rss(['1', '2']);
      final changed = (await PodcastService.fetchFeed(url('a'), known: first.validators))!;
      expect(changed.data!.episodes, hasLength(2));
      expect(changed.validators.hash, isNot(first.validators.hash));
    });

    test('a hash from another parse version fetches and parses in full', () async {
      feeds['a'] = _Feed(_rss(['1']));
      final first = (await PodcastService.fetchFeed(url('a')))!;
      final stale = (
        etag: first.validators.etag,
        lastModified: null,
        hash: '0:${first.validators.hash!.split(':').last}',
      );
      final again = (await PodcastService.fetchFeed(url('a'), known: stale))!;
      expect(feeds['a']!.notModified, 0, reason: 'no If-None-Match sent');
      expect(again.data!.episodes, hasLength(1));
    });

    test('an episode\'s own cover is kept; without one, the podcast\'s shows',
        () async {
      feeds['a'] = _Feed(_rss(['1', '2']).replaceFirst('<guid>1</guid>',
          '<guid>1</guid><itunes:image href=" https://example.com/1.jpg "/>'));
      final eps = (await PodcastService.fetchFeed(url('a')))!.data!.episodes;
      expect([for (final e in eps) e.imageUrl.value],
          ['https://example.com/1.jpg', null]);
      expect(eps.map((e) => e.podcastImageUrl.value).toSet(),
          {'https://example.com/cover.jpg'});
    });

    test('an error status is a failed load', () async {
      feeds['a'] = _Feed('', status: 500);
      expect(await PodcastService.fetchFeed(url('a')), isNull);
    });

    test('permanent redirects move it; a temporary one on the way stops there',
        () async {
      feeds['new'] = _Feed(_rss(['1']));
      feeds['a'] = _Feed.redirect('b', 301);
      feeds['b'] = _Feed.redirect('new', 308);
      var f = (await PodcastService.fetchFeed(url('a')))!;
      expect(f.data!.episodes.single.id.value, '1');
      expect(f.url, url('new'));

      feeds['b'] = _Feed.redirect('new', 302);
      f = (await PodcastService.fetchFeed(url('a')))!;
      expect(f.data!.episodes, hasLength(1));
      expect(f.url, url('b'), reason: 'b may send it elsewhere tomorrow');

      feeds['a'] = _Feed.redirect('new', 307);
      expect((await PodcastService.fetchFeed(url('a')))!.url, url('a'));
    });

    test('a redirect loop is a failed load', () async {
      feeds['a'] = _Feed.redirect('b', 301);
      feeds['b'] = _Feed.redirect('a', 301);
      expect(await PodcastService.fetchFeed(url('a')), isNull);
    });

    test('a feed naming a new home is loaded from there', () async {
      feeds['old'] = _Feed(_rss(['1'],
          head: '<itunes:new-feed-url>${url('new')}</itunes:new-feed-url>'));
      feeds['new'] = _Feed(_rss(['1', '2']));
      final f = (await PodcastService.fetchFeed(url('old')))!;
      expect(f.data!.episodes, hasLength(2));
      expect(f.url, url('new'));
      expect(f.validators.etag, feeds['new']!.etag);
    });

    test('a new home that points back or doesn\'t load: stays', () async {
      feeds['old'] = _Feed(_rss(['1'],
          head: '<itunes:new-feed-url>${url('new')}</itunes:new-feed-url>'));
      feeds['new'] = _Feed(_rss(['1', '2'],
          head: '<itunes:new-feed-url>${url('old')}</itunes:new-feed-url>'));
      var f = (await PodcastService.fetchFeed(url('old')))!;
      expect(f.data!.episodes, hasLength(1));
      expect(f.url, url('old'));

      feeds['new'] = _Feed('', status: 404);
      f = (await PodcastService.fetchFeed(url('old')))!;
      expect(f.data!.episodes, hasLength(1));
      expect(f.url, url('old'));
    });
  });

  group('piEpisode: a PodcastIndex item as its feed has it', () {
    const podcast = {'title': ' The Show ', 'artwork': 'https://x/art.jpg'};

    test('under its guid, its feed and the podcast\'s title', () {
      final e = PodcastService.piEpisode({
        'guid': ' abc ',
        'title': 'Ep 1',
        'enclosureUrl': 'https://x/1.mp3',
        'duration': 1800,
        'datePublished': 1767225600,
        'feedUrl': 'https://pi.example/feed',
        'chaptersUrl': '',
        'image': 'https://x/ep1.jpg',
      }, feedUrl: 'https://apple.example/feed', podcast: podcast)!;
      expect(e.id.value, 'abc');
      expect(e.podcastId.value, 'https://pi.example/feed');
      expect(e.podcastTitle.value, 'The Show');
      expect(e.podcastImageUrl.value, 'https://x/art.jpg');
      expect(e.imageUrl.value, 'https://x/ep1.jpg');
      expect(e.durationSeconds.value, 1800);
      expect(e.publishDate.value, DateTime.utc(2026, 1, 1));
      expect(e.chaptersUrl.value, isNull);
    });

    test('guid-less, the id its feed gives it; no audio or title, none', () {
      final e = PodcastService.piEpisode(
          {'title': 'Ep 2', 'enclosureUrl': 'https://x/2.mp3', 'duration': null},
          feedUrl: 'https://f', podcast: podcast)!;
      expect(e.id.value, 'https://f_Ep 2');
      expect(e.durationSeconds.value, 0);
      expect(e.publishDate.present, isFalse);
      expect(
          PodcastService.piEpisode({'guid': 'a'}, feedUrl: 'f', podcast: podcast),
          isNull);
      expect(
          PodcastService.piEpisode({'guid': 'a', 'enclosureUrl': 'https://x'},
              feedUrl: 'f', podcast: const {}),
          isNull);
    });
  });

  group('newFeedUrl', () {
    test('reads the channel\'s tag, CDATA or escaped', () {
      expect(PodcastService.newFeedUrl(
              '<channel><itunes:new-feed-url> https://a.example/f?x=1&amp;y=2 '
              '</itunes:new-feed-url><item></item>'),
          'https://a.example/f?x=1&y=2');
      expect(PodcastService.newFeedUrl(
              '<itunes:new-feed-url><![CDATA[http://b.example/rss]]></itunes:new-feed-url>'),
          'http://b.example/rss');
    });

    test('not an item\'s, nor a URL that isn\'t http(s)', () {
      expect(PodcastService.newFeedUrl(
              '<channel><item><itunes:new-feed-url>https://a.example/f'
              '</itunes:new-feed-url></item>'),
          isNull);
      expect(PodcastService.newFeedUrl(
              '<itunes:new-feed-url>javascript:x</itunes:new-feed-url>'),
          isNull);
      expect(PodcastService.newFeedUrl('<itunes:new-feed-url></itunes:new-feed-url>'),
          isNull);
    });
  });

  group('refreshAll', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
    tearDown(() => db.close());

    Future<void> subscribe(String path) => db.insertPodcast(PodcastsCompanion.insert(
        id: url(path), title: path, description: '', imageUrl: '',
        feedUrl: url(path), author: ''));
    Future<Podcast> pod(String path) => db.getPodcast(url(path)).then((p) => p!);
    Future<int> episodeCount() =>
        db.select(db.episodes).get().then((e) => e.length);

    test('loads every feed, then skips the unchanged ones', () async {
      for (var i = 0; i < 15; i++) {
        feeds['f$i'] = _Feed(_rss(['$i-a', '$i-b']));
        await subscribe('f$i');
      }
      await FeedSync.refreshAll(db);
      expect(await episodeCount(), 30);
      final p = await pod('f3');
      expect(p.imageUrl, 'https://example.com/cover.jpg');
      expect(p.feedEtag, feeds['f3']!.etag);
      expect(p.feedHash, matches(r'^\d+:[0-9a-f]+$'), reason: 'version:hash');

      await FeedSync.refreshAll(db);
      expect(feeds.values.every((f) => f.requests == 2 && f.notModified == 1),
          isTrue, reason: 'all feeds still refreshed, all answered 304');

      feeds['f3']!.body = _rss(['3-a', '3-b', '3-c']);
      await FeedSync.refreshAll(db);
      expect(await episodeCount(), 31);
    });

    test('counts failures only while other feeds load', () async {
      feeds['ok'] = _Feed(_rss(['1']));
      feeds['bad'] = _Feed('', status: 500);
      await subscribe('ok');
      await subscribe('bad');

      await FeedSync.refreshAll(db);
      expect((await pod('bad')).feedFailures, 1);
      expect((await pod('ok')).feedFailures, 0);

      // Nothing loads: offline, not the feed's fault.
      feeds['ok']!.status = 500;
      feeds['ok']!.body = '';
      await FeedSync.refreshAll(db);
      expect((await pod('bad')).feedFailures, 1);

      // Back: a load clears the count.
      feeds['bad'] = _Feed(_rss(['2']));
      await FeedSync.refreshAll(db);
      expect((await pod('bad')).feedFailures, 0);
    });

    test('a feed that moved is refreshed at its new home, its episodes kept',
        () async {
      feeds['a'] = _Feed(_rss(['1', '2']));
      await subscribe('a');
      await FeedSync.refreshAll(db);
      expect(await episodeCount(), 2);

      feeds['new'] = _Feed(_rss(['1', '2', '3']));
      feeds['a'] = _Feed.redirect('new', 301);
      await FeedSync.refreshAll(db);
      final p = await pod('a');
      expect(p.feedUrl, url('new'));
      expect(await episodeCount(), 3);

      await FeedSync.refreshAll(db);
      expect(feeds['a']!.requests, 1, reason: 'the redirect, not asked again');
      expect(feeds['new']!.notModified, 1);
      final eps = await db.select(db.episodes).get();
      expect(eps.map((e) => e.podcastId).toSet(), {url('a')});
    });

    test('a paused feed is not refreshed', () async {
      feeds['a'] = _Feed(_rss(['1']));
      await subscribe('a');
      await db.setPodcastSyncPaused(url('a'), true);
      await FeedSync.refreshAll(db);
      expect(feeds['a']!.requests, 0);
    });
  });
}
