// lib/podcast_service.dart
//
// Podcast directories and feeds.
//
//   PodcastIndex /search/byterm        → podcast search
//   PodcastIndex /podcasts/trending    → trending fallback (30-day window)
//   PodcastIndex /…/byfeedurl          → episode search hits as their feed has them
//   Apple charts + lookup              → trending by country
//   Apple search (podcastEpisode)      → episode search: the hits only, not
//                                        Apple's ids or audio
//   RSS (podcast_search)               → feeds themselves, parsed off-isolate
//                                        (plus their Podlove chapters)

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:drift/drift.dart' show Value;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:podcast_search/podcast_search.dart' as ps;
import 'app_database.dart';
import 'chapters.dart';
import 'feed_items.dart';

// ── Zugangsdaten ──────────────────────────────────────────────────────────────

const _apiKey    = 'WVABNRFZXMR56UKS7488';
const _apiSecret = 'Yrb2fXKRtwFRkzcj4XNZBKmBhVbg8Uz5ZvMj5Prd';

const _baseUrl = 'https://api.podcastindex.org/api/1.0';
const _userAgent = 'AntPod/1.0';

// ── Auth-Header ───────────────────────────────────────────────────────────────

Map<String, String> _authHeaders() {
  final ts = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
  final hash = sha1
      .convert(utf8.encode('$_apiKey$_apiSecret$ts'))
      .toString();
  return {
    'User-Agent': _userAgent,
    'X-Auth-Key': _apiKey,
    'X-Auth-Date': ts,
    'Authorization': hash,
  };
}

// ── Search result model ───────────────────────────────────────────────────────

class PodcastResult {
  final String id;
  final String title;
  final String author;
  final String description;
  final String imageUrl;
  final String feedUrl;
  final List<String> categories;

  const PodcastResult({
    required this.id,
    required this.title,
    required this.author,
    required this.description,
    required this.imageUrl,
    required this.feedUrl,
    this.categories = const [],
  });

  /// A feed known by its URL and whatever a link or an episode tells about it.
  const PodcastResult.feed(this.feedUrl, {this.title = '', this.imageUrl = ''})
      : id = feedUrl, author = '', description = '', categories = const [];

  PodcastResult.fromPodcast(Podcast p)
      : this(id: p.feedUrl, title: p.title, author: p.author,
            description: p.description, imageUrl: p.imageUrl, feedUrl: p.feedUrl);

  /// The podcast an episode belongs to (its podcastId is the feed URL).
  PodcastResult.fromEpisode(Episode e)
      : this.feed(e.podcastId, title: e.podcastTitle, imageUrl: e.podcastImageUrl);

  PodcastResult copyWith({
    String? id, String? title, String? description, String? imageUrl, String? feedUrl,
  }) =>
      PodcastResult(
        id: id ?? this.id,
        title: title ?? this.title,
        author: author,
        description: description ?? this.description,
        imageUrl: imageUrl ?? this.imageUrl,
        feedUrl: feedUrl ?? this.feedUrl,
        categories: categories,
      );

  factory PodcastResult.fromAppleJson(Map<String, dynamic> j) {
    final genre = j['primaryGenreName'] as String?;
    return PodcastResult(
      id: j['feedUrl'] ?? '',
      title: j['collectionName'] ?? '',
      author: j['artistName'] ?? '',
      description: '',
      imageUrl: j['artworkUrl600'] ?? j['artworkUrl100'] ?? '',
      feedUrl: j['feedUrl'] ?? '',
      categories: genre != null ? [genre] : [],
    );
  }

  factory PodcastResult.fromJson(Map<String, dynamic> j) {
    // categories: Map<String,String> {"1":"Arts","2":"Music"} or null
    final cats = <String>[];
    final rawCats = j['categories'];
    if (rawCats is Map) {
      cats.addAll(rawCats.values.map((v) => v.toString()));
    }
    return PodcastResult(
      id: j['id']?.toString() ?? '',
      title: j['title'] ?? '',
      author: j['author'] ?? '',
      description: j['description'] ?? '',
      imageUrl: j['artwork'] ?? j['image'] ?? '',
      feedUrl: j['url'] ?? '',
      categories: cats,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'author': author,
    'description': description,
    'artwork': imageUrl,
    'url': feedUrl,
    'categories': {for (int i = 0; i < categories.length; i++) '$i': categories[i]},
  };

  PodcastsCompanion toCompanion() => PodcastsCompanion(
        id: Value(feedUrl),
        title: Value(title),
        description: Value(description),
        imageUrl: Value(imageUrl),
        feedUrl: Value(feedUrl),
        author: Value(author),
        isSubscribed: const Value(true),
      );
}

// ── Service ───────────────────────────────────────────────────────────────────

/// A parsed RSS feed: podcast metadata plus its episodes as DB companions.
typedef FeedData = ({ps.Podcast podcast, List<EpisodesCompanion> episodes});

/// What tells a feed's next refresh whether it changed: the server's ETag and
/// Last-Modified headers, and a hash of the body for servers without them.
typedef FeedValidators = ({String? etag, String? lastModified, String? hash});

/// A fetched feed: [data] is null when it hasn't changed since [validators]
/// were stored; [validators] are the ones to store now. [url] is where the
/// feed lives now: the one asked for, unless it moved for good (a permanent
/// redirect, or its itunes:new-feed-url).
typedef FeedFetch = ({FeedData? data, FeedValidators validators, String url});

class PodcastService {
  static const _apiTimeout = Duration(seconds: 15);

  /// GET with a timeout: a stalled connection (captive portal, dead mobile
  /// link) would otherwise hold a spinner until the OS gives up, minutes on.
  static Future<http.Response> _get(Uri uri, {Map<String, String>? headers}) =>
      http.get(uri, headers: headers).timeout(_apiTimeout);

  /// The body as a JSON object. JSON is UTF-8 whatever the content type says.
  static Map<String, dynamic> _json(http.Response res) =>
      jsonDecode(utf8.decode(res.bodyBytes, allowMalformed: true))
          as Map<String, dynamic>;

  // ── Search ─────────────────────────────────────────────────────────────────

  static Future<List<PodcastResult>> search(String query, {int offset = 0}) async {
    try {
      final uri = Uri.parse('$_baseUrl/search/byterm')
          .replace(queryParameters: {'q': query, 'max': '20', 'offset': '$offset'});
      final res = await _get(uri, headers: _authHeaders());
      if (res.statusCode != 200) return [];
      final feeds = _json(res)['feeds'] as List? ?? [];
      return feeds
          .map((f) => PodcastResult.fromJson(f as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[podcast] search error: $e');
      return [];
    }
  }

  /// Episode search. Apple's search finds them, by keyword, but its ids and
  /// audio (a preview, at times a clip) aren't kept: each hit is looked up in
  /// its feed, as PodcastIndex has it, else the feed itself, and found there
  /// by guid, audio or title ([findHit]). A hit found in neither is left out.
  /// In Apple's order, each episode once, under its feed's guid.
  static Future<List<EpisodesCompanion>> searchEpisodes(String query,
      {String country = 'us'}) async {
    final hits = await _appleEpisodeHits(query, country: country);
    final found = List<EpisodesCompanion?>.filled(hits.length, null);
    final byFeed = <String, List<int>>{};
    for (var i = 0; i < hits.length; i++) {
      (byFeed[hits[i].feed] ??= []).add(i);
    }
    await Future.wait(byFeed.entries.map((f) async {
      var open = f.value;
      void look(List<EpisodesCompanion> items) {
        final facts = items.map(itemFacts).toList();
        open = open.where((i) {
          final j = findHit(hits[i].facts, facts);
          if (j != null) found[i] = items[j];
          return j == null;
        }).toList();
      }

      look(await _piEpisodes(f.key));
      if (open.isEmpty) return;
      // Not in PodcastIndex, or older than its latest: the feed has them all.
      look((await loadFeed(f.key)
                  .timeout(const Duration(seconds: 12), onTimeout: () => null))
              ?.episodes ??
          const []);
    }));
    final seen = <(String, String)>{};
    return [
      for (final e in found)
        if (e != null && seen.add((e.podcastId.value, e.id.value))) e,
    ];
  }

  /// Apple's episode search hits: in which feed, and what tells the episode
  /// apart there (its guid, audio, title, date and length).
  static Future<List<({String feed, ItemFacts facts})>> _appleEpisodeHits(
      String query, {String country = 'us'}) async {
    try {
      final uri = Uri.parse('https://itunes.apple.com/search').replace(
        queryParameters: {'term': query, 'media': 'podcast', 'entity': 'podcastEpisode',
                          'limit': '10', 'country': country},
      );
      final res = await _get(uri);
      if (res.statusCode != 200) return [];
      final results = _json(res)['results'] as List? ?? [];
      return [
        for (final r in results.whereType<Map<String, dynamic>>())
          if ((r['feedUrl'] as String? ?? '').trim() case final feed
              when feed.isNotEmpty)
            (
              feed: feed,
              facts: (
                id: (r['episodeGuid'] as String? ?? '').trim(),
                title: titleKey(r['trackName'] as String? ?? ''),
                date: DateTime.tryParse(r['releaseDate'] as String? ?? ''),
                seconds: (r['trackTimeMillis'] as num? ?? 0) ~/ 1000,
                url: (r['episodeUrl'] as String? ?? '').trim(),
              ),
            ),
      ];
    } catch (e) {
      debugPrint('[podcast] episode search error: $e');
      return [];
    }
  }

  /// [feedUrl]'s latest episodes as PodcastIndex has them; none when it
  /// doesn't know the feed.
  static Future<List<EpisodesCompanion>> _piEpisodes(String feedUrl) async {
    Future<http.Response> get(String path, Map<String, String> query) => _get(
        Uri.parse('$_baseUrl/$path').replace(queryParameters: query),
        headers: _authHeaders());
    try {
      final (pod, eps) = await (
        get('podcasts/byfeedurl', {'url': feedUrl}),
        get('episodes/byfeedurl', {'url': feedUrl, 'max': '100'}),
      ).wait;
      if (pod.statusCode != 200 || eps.statusCode != 200) return [];
      final feed = _json(pod)['feed'];
      if (feed is! Map<String, dynamic>) return [];
      final items = _json(eps)['items'] as List? ?? [];
      return [
        for (final m in items.whereType<Map<String, dynamic>>())
          if (piEpisode(m, feedUrl: feedUrl, podcast: feed) case final e?) e,
      ];
    } catch (e) {
      debugPrint('[podcast] PI episodes error: $e');
      return [];
    }
  }

  /// A PodcastIndex episode item [m] of the PodcastIndex [podcast] (asked
  /// for by [feedUrl]) as the feed has it: under its guid (guid-less, as the
  /// feed names it, see [fetchFeed]), the podcast's title and cover. Null
  /// without audio, or when the podcast has no title.
  static EpisodesCompanion? piEpisode(Map<String, dynamic> m,
      {required String feedUrl, required Map<String, dynamic> podcast}) {
    String str(Object? v) => v is String ? v.trim() : '';
    final podcastTitle = str(podcast['title']);
    final audio = str(m['enclosureUrl']);
    if (podcastTitle.isEmpty || audio.isEmpty) return null;
    final feed = str(m['feedUrl']).isNotEmpty ? str(m['feedUrl']) : feedUrl;
    final title = m['title'] is String ? m['title'] as String : '';
    final guid = str(m['guid']);
    final cover = [m['feedImage'], podcast['artwork'], podcast['image']]
        .map(str)
        .firstWhere((s) => s.isNotEmpty, orElse: () => '');
    final published = m['datePublished'];
    final chapters = str(m['chaptersUrl']);
    final image = str(m['image']);
    return EpisodesCompanion(
      id: Value(guid.isNotEmpty ? guid : '${feed}_$title'),
      podcastId: Value(feed),
      podcastTitle: Value(podcastTitle),
      podcastImageUrl: Value(cover),
      imageUrl: Value(image.isEmpty ? null : image),
      title: Value(title.trim()),
      description: Value(m['description'] is String ? m['description'] as String : ''),
      audioUrl: Value(audio),
      durationSeconds: Value(m['duration'] is num ? (m['duration'] as num).toInt() : 0),
      publishDate: published is num && published > 0
          ? Value(DateTime.fromMillisecondsSinceEpoch(published.toInt() * 1000,
              isUtc: true))
          : const Value.absent(),
      chaptersUrl: Value(chapters.isEmpty ? null : chapters),
    );
  }

  // Apple Charts top podcasts for a country, resolved to feedUrl via iTunes lookup.
  static Future<List<PodcastResult>> appleCharts(String country, {int limit = 20}) async {
    try {
      // Use the canonical URL directly (the marketing tools URL issues a 301 redirect)
      final chartsUri = Uri.parse(
        'https://rss.marketingtools.apple.com/api/v2/${country.toLowerCase()}/podcasts/top/$limit/podcasts.json',
      );
      final chartsRes = await _get(chartsUri);
      if (chartsRes.statusCode != 200) return [];
      final feed = _json(chartsRes)['feed'] as Map<String, dynamic>?;
      final results = feed?['results'] as List? ?? [];
      if (results.isEmpty) return [];
      final ids = results.map((r) => r['id'].toString()).join(',');
      final lookupUri = Uri.parse('https://itunes.apple.com/lookup')
          .replace(queryParameters: {'id': ids, 'entity': 'podcast'});
      final lookupRes = await _get(lookupUri);
      if (lookupRes.statusCode != 200) return [];
      final lookupResults = _json(lookupRes)['results'] as List? ?? [];
      // Preserve chart order: build a map from id → lookup result, then re-order.
      final byId = <String, Map<String, dynamic>>{};
      for (final r in lookupResults) {
        final id = r['collectionId']?.toString() ?? '';
        if (id.isNotEmpty) byId[id] = r as Map<String, dynamic>;
      }
      return results
          .map((r) => byId[r['id'].toString()])
          .whereType<Map<String, dynamic>>()
          .map(PodcastResult.fromAppleJson)
          .where((p) => p.feedUrl.isNotEmpty)
          .toList();
    } catch (e) {
      debugPrint('[podcast] Apple charts error: $e');
      return [];
    }
  }

  // ── Trending ───────────────────────────────────────────────────────────────
  // PodcastIndex /podcasts/trending — 30-day window for consistent popularity
  // (not viral spikes). Regionalized via `lang`: passing "de,en" returns
  // primarily German podcasts with English ones filling the remainder.

  static Future<List<PodcastResult>> trending({
    int max = 10,
    String lang = 'en',
  }) async {
    final since = DateTime.now().millisecondsSinceEpoch ~/ 1000 - 2592000;
    final params = <String, String>{
      'max': '$max',
      'lang': lang,
      'since': '$since', // 30-day window
    };

    final uri =
        Uri.parse('$_baseUrl/podcasts/trending').replace(queryParameters: params);
    final res = await _get(uri, headers: _authHeaders());
    if (res.statusCode != 200) {
      throw Exception('API ${res.statusCode}: ${res.reasonPhrase}');
    }
    final feeds = _json(res)['feeds'] as List? ?? [];
    return feeds
        .take(max)
        .map((f) => PodcastResult.fromJson(f as Map<String, dynamic>))
        .toList();
  }

  // ── RSS feeds ─────────────────────────────────────────────────────────────

  /// The feed at [feedUrl], parsed; null when it doesn't load.
  static Future<FeedData?> loadFeed(String feedUrl) async =>
      (await fetchFeed(feedUrl))?.data;

  /// Bump when parsing changes (fields read, chapters, ids): stored hashes
  /// stop matching, so every feed is parsed again on its next refresh.
  static const _parseVersion = 4;

  /// The feed at [feedUrl], parsed by podcast_search, which leaves out
  /// Podlove Simple Chapters: so the XML is fetched here and those read from
  /// it too (chapters.dart). Null when it doesn't load.
  ///
  /// With the [known] validators of the last parse it's a refresh: the server
  /// is asked for the feed only if it changed, and a body that hashes the
  /// same isn't parsed either. Both come back with null data.
  ///
  /// A feed that names a new home (itunes:new-feed-url) is loaded from there,
  /// unless that doesn't load or points back. Guid-less items keep ids made
  /// from [feedUrl], the URL asked for.
  static Future<FeedFetch?> fetchFeed(String feedUrl,
      {FeedValidators known = (etag: null, lastModified: null, hash: null)}) async {
    try {
      final tempDir = await getTemporaryDirectory()
          .then((d) => d.path, onError: (_) => Directory.systemTemp.path);
      // Run HTTP fetch + XML parse on a background isolate so the main thread
      // is never blocked by RssFeed.parse() on large feeds.
      return await Isolate.run(() async {
        // Validators from another parse version describe a different result.
        final current = known.hash?.startsWith('$_parseVersion:') ?? false;
        var res = await _fetchFeed(feedUrl, current ? known : null);
        if (res == null) return null;
        var body = res.body;
        if (body == null) {
          // 304: the stored parse still holds. A server may renew its tags.
          return (data: null, validators: (
            etag: res.etag ?? known.etag,
            lastModified: res.lastModified ?? known.lastModified,
            hash: known.hash,
          ), url: res.url);
        }
        // Moved: the old feed often stays up, frozen, with the new URL in it.
        final here = {AppDatabase.normFeed(feedUrl), AppDatabase.normFeed(res.url)};
        final next = newFeedUrl(_head(body));
        if (next != null && !here.contains(AppDatabase.normFeed(next))) {
          final there = await _fetchFeed(next, null).catchError((_) => null);
          final back = there?.body == null ? null : newFeedUrl(_head(there!.body!));
          if (there?.body != null &&
              !here.contains(AppDatabase.normFeed(there!.url)) &&
              (back == null || !here.contains(AppDatabase.normFeed(back)))) {
            res = there;
            body = there.body!;
          }
        }
        final validators = (
          etag: res.etag,
          lastModified: res.lastModified,
          hash: '$_parseVersion:${sha256.convert(body)}',
        );
        if (current && validators.hash == known.hash) {
          return (data: null, validators: validators, url: res.url);
        }
        final xml = normalizePubDates(utf8.decode(body, allowMalformed: true));
        // podcast_search parses from a string only via a file.
        final file = File('$tempDir/feed-${feedUrl.hashCode}-'
            '${DateTime.now().microsecondsSinceEpoch}.xml');
        final ps.Podcast podcast;
        try {
          await file.writeAsString(xml);
          podcast = await ps.Feed.loadFeedFile(file: file.path);
        } finally {
          file.delete().ignore();
        }
        // One episode per item, in order, so they pair up by position.
        List<String?>? podlove;
        if (xml.contains('<psc:chapter')) {
          final items = _item.allMatches(xml).toList();
          if (items.length == podcast.episodes.length) {
            podlove = [for (final m in items) podloveChaptersUri(m.group(0)!)];
          }
        }
        var index = 0;
        final episodes = podcast.episodes.map((ep) {
          final i = index++;
          final pcUrl = ep.chapters?.url;
          final chapUrl =
              pcUrl != null && pcUrl.isNotEmpty ? pcUrl : podlove?[i];
          final image = ep.imageUrl?.trim() ?? '';
          return EpisodesCompanion(
            id: Value(ep.guid.isNotEmpty ? ep.guid : '${feedUrl}_${ep.title}'),
            podcastId: Value(feedUrl),
            podcastTitle: Value(podcast.title ?? ''),
            podcastImageUrl: Value(podcast.image ?? ''),
            imageUrl: Value(image.isEmpty ? null : image),
            title: Value(ep.title),
            description: Value(ep.description),
            audioUrl: Value(ep.contentUrl ?? ''),
            durationSeconds: Value((ep.duration ?? Duration.zero).inSeconds),
            // Undated: first seen (the column's default), and kept after.
            publishDate: ep.publicationDate == null
                ? const Value.absent()
                : Value(ep.publicationDate!),
            chaptersUrl: Value(chapUrl),
          );
        }).toList();
        return (
          data: (podcast: podcast, episodes: distinctItems(episodes)),
          validators: validators,
          url: res.url,
        );
      });
    } catch (e) {
      debugPrint('[podcast] feed load error: $e');
      return null;
    }
  }

  static final _item = RegExp(r'<item[\s>][\s\S]*?</item>');

  /// The start of a feed's body, where its channel's tags are.
  static String _head(Uint8List body) => utf8.decode(
      body.length > 65536 ? Uint8List.sublistView(body, 0, 65536) : body,
      allowMalformed: true);

  static final _newFeedUrl = RegExp(
      r'<itunes:new-feed-url\s*>\s*(?:<!\[CDATA\[)?\s*([^<\s\]]+)\s*(?:\]\]>)?\s*</itunes:new-feed-url\s*>',
      caseSensitive: false);

  /// The URL a feed says it moved to: its channel's itunes:new-feed-url
  /// (before the first item, as an item's can't be), if http(s).
  static String? newFeedUrl(String xml) {
    final first = xml.indexOf(RegExp(r'<item[\s>]'));
    final channel = first < 0 ? xml : xml.substring(0, first);
    final m = _newFeedUrl.firstMatch(channel);
    if (m == null) return null;
    final url = m[1]!.replaceAll('&amp;', '&');
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasAuthority) return null;
    return uri.scheme == 'http' || uri.scheme == 'https' ? url : null;
  }

  /// The feed's body with its validator headers, a null body when the
  /// [conditional] request found it not modified, or null if the server
  /// didn't send it. Redirects are followed, up to 5; [url] comes back as
  /// where they led if each one was permanent (301, 308), so a feed that
  /// moved is asked for at its new home from then on.
  static Future<({Uint8List? body, String? etag, String? lastModified, String url})?>
      _fetchFeed(String url, FeedValidators? conditional) async {
    const timeout = Duration(seconds: 20);
    final client = http.Client();
    try {
      var uri = Uri.parse(url);
      var moved = url;
      var permanent = true;
      for (var hops = 0;; hops++) {
        final req = http.Request('GET', uri)
          ..followRedirects = false
          ..headers['User-Agent'] = _userAgent;
        if (conditional?.etag case final etag?) {
          req.headers['If-None-Match'] = etag;
        }
        if (conditional?.lastModified case final modified?) {
          req.headers['If-Modified-Since'] = modified;
        }
        final res = await client.send(req).timeout(timeout);
        final location = res.headers['location'];
        if (const {301, 302, 303, 307, 308}.contains(res.statusCode) &&
            location != null) {
          res.stream.listen(null).cancel().ignore();
          final to = uri.resolve(location);
          if (hops == 5 || !to.isScheme('http') && !to.isScheme('https')) {
            return null;
          }
          uri = to;
          permanent &= res.statusCode == 301 || res.statusCode == 308;
          if (permanent) moved = '$uri';
          continue;
        }
        final etag = res.headers['etag'];
        final lastModified = res.headers['last-modified'];
        final notModified = res.statusCode == 304 && conditional != null;
        if (notModified || res.statusCode < 200 || res.statusCode >= 300) {
          res.stream.listen(null).cancel().ignore();
          return notModified
              ? (body: null, etag: etag, lastModified: lastModified, url: moved)
              : null;
        }
        final body = await http.ByteStream(res.stream.timeout(timeout)).toBytes();
        return (body: body, etag: etag, lastModified: lastModified, url: moved);
      }
    } finally {
      client.close();
    }
  }
}
