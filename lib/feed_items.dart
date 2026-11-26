import 'dart:math';

import 'app_database.dart';

// Feeds as they are, not as the spec has them: one episode under two guids,
// listed twice, dated in German or not at all.

/// What tells a feed's items apart when their guids don't.
typedef ItemFacts = ({
  String id,
  String title,
  DateTime? date,
  int seconds,
  String url,
});

ItemFacts itemFacts(EpisodesCompanion e) => (
      id: e.id.value,
      title: titleKey(e.title.value),
      date: e.publishDate.present ? e.publishDate.value : null,
      seconds: e.durationSeconds.present ? e.durationSeconds.value : 0,
      url: e.audioUrl.present ? e.audioUrl.value : '',
    );

ItemFacts rowFacts(Episode e) => (
      id: e.id,
      title: titleKey(e.title),
      date: e.publishDate,
      seconds: e.durationSeconds,
      url: e.audioUrl,
    );

/// A title as hosts change it: case, spaces, typographic quotes, dashes
/// and ellipses aside.
String titleKey(String title) => title
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r'\s+'), ' ')
    .replaceAll(RegExp('[‘’‚‛`´]'), "'")
    .replaceAll(RegExp('[“”„‟«»]'), '"')
    .replaceAll(RegExp('[‐‑‒–—―]'), '-')
    .replaceAll('…', '...');

/// Whether [a] and [b] are one episode under two guids: the same title
/// with the same audio, or from the same day and about as long. [strict]
/// for two items of one feed, which may well be two episodes (hourly news
/// under one title): then both lengths known and within two seconds.
bool sameEpisode(ItemFacts a, ItemFacts b, {bool strict = false}) {
  if (a.title != b.title) return false;
  if (a.url.isNotEmpty && a.url == b.url) return true;
  final da = a.date, db = b.date;
  if (da == null || db == null || !_sameDay(da, db)) return false;
  if (a.seconds <= 0 || b.seconds <= 0) return !strict;
  final diff = (a.seconds - b.seconds).abs();
  return diff <= (strict ? 2 : max(60, max(a.seconds, b.seconds) ~/ 10));
}

/// Whether two copies of one episode, [a] and [b] seconds long, carry the
/// same audio, so a position in one is the same moment in the other: a
/// re-upload, re-encoded, is a second or two off. An unknown length counts.
bool sameAudio(int a, int b) =>
    a <= 0 || b <= 0 || (a - b).abs() <= max(5, max(a, b) ~/ 100);

bool _sameDay(DateTime a, DateTime b) {
  final la = a.toLocal(), lb = b.toLocal();
  return (la.year == lb.year && la.month == lb.month && la.day == lb.day) ||
      a.difference(b).abs() < const Duration(hours: 1);
}

/// The id of what [old] is among [items] under another guid: the one with
/// its audio, unless a placeholder several share (locked premium items);
/// else the closest [sameEpisode], by date, then length.
String? twinOf(ItemFacts old, Iterable<ItemFacts> items) {
  if (old.url.isNotEmpty) {
    final same = items.where((i) => i.url == old.url && i.id != old.id);
    if (same.length == 1) return same.single.id;
  }
  ItemFacts? best;
  for (final i in items) {
    if (i.id == old.id || !sameEpisode(old, i)) continue;
    if (best == null || _gap(old, i) < _gap(old, best)) best = i;
  }
  return best?.id;
}

int _gap(ItemFacts a, ItemFacts b) {
  final dates = a.date == null || b.date == null
      ? 1 << 30
      : a.date!.difference(b.date!).inMinutes.abs();
  return dates * 100000 + (a.seconds - b.seconds).abs().clamp(0, 99999);
}

/// A feed's items, each episode once. Some list one twice: under one guid,
/// or two with the same title and audio, or the same title, day and length
/// (Open to Debate). The newest copy stays, the first of equals, so the
/// pick holds whatever the order.
List<EpisodesCompanion> distinctItems(List<EpisodesCompanion> items) {
  final facts = [for (final e in items) itemFacts(e)];
  final order = List.generate(items.length, (i) => i)
    ..sort((a, b) {
      final da = facts[a].date, db = facts[b].date;
      final byDate = (db?.millisecondsSinceEpoch ?? 0)
          .compareTo(da?.millisecondsSinceEpoch ?? 0);
      return byDate != 0 ? byDate : a.compareTo(b);
    });
  final keep = List.filled(items.length, false);
  final ids = <String>{};
  final byTitle = <String, List<ItemFacts>>{};
  for (final i in order) {
    final f = facts[i];
    final kin = byTitle.putIfAbsent(f.title, () => []);
    if (!ids.add(f.id) || kin.any((k) => sameEpisode(k, f, strict: true))) {
      continue;
    }
    kin.add(f);
    keep[i] = true;
  }
  return [
    for (var i = 0; i < items.length; i++)
      if (keep[i]) items[i],
  ];
}

// ── Dates ──────────────────────────────────────────────────────────────────

final _pubDate = RegExp(
    r'<pubDate>\s*(?:<!\[CDATA\[)?(.*?)(?:\]\]>)?\s*</pubDate>',
    dotAll: true);

/// The feed with each pubDate the way podcast_search reads it, or emptied:
/// it reads English RFC 822 dates with a zone it knows and ISO 8601 ones,
/// and a month or zone it doesn't ("Okt", "MESZ") fails the whole feed.
String normalizePubDates(String xml) => xml.replaceAllMapped(_pubDate, (m) {
      final d = parseFeedDate(m.group(1)!);
      return d == null ? '<pubDate></pubDate>' : '<pubDate>${_rfc822(d)}</pubDate>';
    });

/// A feed's date as podcasters write them: ISO 8601, or RFC 822 more or
/// less, the weekday, seconds or zone left out, months in English, German,
/// French, Spanish or Italian. A zone it doesn't know counts as UTC.
DateTime? parseFeedDate(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return null;
  final iso = DateTime.tryParse(s);
  if (iso != null) return iso.toUtc();
  final m = _rfc822Like.firstMatch(s);
  if (m == null) return null;
  final month = _month(m[2]!);
  if (month == null) return null;
  final day = int.parse(m[1]!);
  var year = int.parse(m[3]!);
  if (m[3]!.length == 2) year += year < 70 ? 2000 : 1900;
  final hour = int.parse(m[4] ?? '0');
  final minute = int.parse(m[5] ?? '0');
  final second = int.parse(m[6] ?? '0');
  if (day < 1 || day > 31 || hour > 23 || minute > 59 || second > 60) {
    return null;
  }
  return DateTime.utc(year, month, day, hour, minute, second)
      .subtract(_zoneOffset(m[7]!));
}

final _rfc822Like = RegExp(r'^(?:[^\d\s,]+\.?,?\s*)?'
    r'(\d{1,2})[\s.-]+([^\d\s.,-]+)\.?[\s,-]+(\d{4}|\d{2})'
    r'(?:[\sT,]+(\d{1,2})[:.](\d{2})(?:[:.](\d{2}))?(?:\.\d+)?)?'
    r'\s*(.*)$');

const _months = {
  'jan': 1, 'janv': 1, 'jän': 1, 'ene': 1, 'gen': 1,
  'feb': 2, 'fev': 2, 'fév': 2, 'févr': 2,
  'mar': 3, 'mär': 3, 'mrz': 3, 'mars': 3,
  'apr': 4, 'avr': 4, 'abr': 4,
  'may': 5, 'mai': 5, 'mag': 5,
  'jun': 6, 'juin': 6, 'giu': 6,
  'jul': 7, 'juil': 7, 'lug': 7,
  'aug': 8, 'aoû': 8, 'aou': 8, 'ago': 8,
  'sep': 9, 'set': 9,
  'oct': 10, 'okt': 10, 'ott': 10,
  'nov': 11,
  'dec': 12, 'dez': 12, 'déc': 12, 'dic': 12,
};

int? _month(String name) {
  final n = name.toLowerCase();
  if (n.length < 3) return null;
  return (n.length >= 4 ? _months[n.substring(0, 4)] : null) ??
      _months[n.substring(0, 3)];
}

const _zones = {
  'EST': -300, 'EDT': -240, 'CST': -360, 'CDT': -300, 'MST': -420,
  'MDT': -360, 'PST': -480, 'PDT': -420, 'AKST': -540, 'AKDT': -480,
  'HST': -600, 'AST': -240, 'ADT': -180, 'NST': -210, 'NDT': -150,
  'BST': 60, 'IST': 330, 'WET': 0, 'WEST': 60, 'CET': 60, 'CEST': 120,
  'MEZ': 60, 'MESZ': 120, 'EET': 120, 'EEST': 180, 'MSK': 180,
  'JST': 540, 'KST': 540, 'AWST': 480, 'ACST': 570, 'ACDT': 630,
  'AEST': 600, 'AEDT': 660, 'NZST': 720, 'NZDT': 780,
};

Duration _zoneOffset(String zone) {
  final hhmm = RegExp(r'([+-])(\d\d):?(\d\d)').firstMatch(zone);
  final hh = hhmm ?? RegExp(r'([+-])(\d{1,2})\b').firstMatch(zone);
  if (hh != null) {
    final hours = int.parse(hh[2]!);
    final minutes = hhmm == null ? 0 : int.parse(hhmm[3]!);
    if (hours > 14 || minutes > 59) return Duration.zero;
    final sign = hh[1] == '-' ? -1 : 1;
    return Duration(minutes: sign * (hours * 60 + minutes));
  }
  final name = RegExp(r'^[A-Za-z]+').firstMatch(zone.trim())?[0];
  return Duration(minutes: _zones[name?.toUpperCase()] ?? 0);
}

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _monthNames = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _rfc822(DateTime d) {
  final u = d.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${_weekdays[u.weekday - 1]}, ${two(u.day)} ${_monthNames[u.month - 1]} '
      '${u.year.toString().padLeft(4, '0')} '
      '${two(u.hour)}:${two(u.minute)}:${two(u.second)} +0000';
}
