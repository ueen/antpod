// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get toolbarSearchHint => 'Search episodes…';

  @override
  String get searchHint => 'Search podcasts…';

  @override
  String get searchNoResults => 'No results found.';

  @override
  String get sectionTrending => 'Trending this month';

  @override
  String get sectionRecommended => 'Recommended for you';

  @override
  String get sectionRecommendedSub => 'based on your subscriptions';

  @override
  String get sectionSearchResults => 'Search results';

  @override
  String get emptyFeedTitle => 'No podcasts yet';

  @override
  String get emptyFeedSub => 'Tap + to search and subscribe';

  @override
  String get emptySearchTitle => 'No results';

  @override
  String get emptyPodcastsTitle => 'No subscriptions yet';

  @override
  String get subscribeDialogTitle => 'Subscribe';

  @override
  String subscribed(String title) {
    return 'Subscribed to \"$title\"';
  }

  @override
  String get downloaded => 'Downloaded';

  @override
  String get downloading => 'Download';

  @override
  String get deleteDownload => 'Delete download';

  @override
  String get shownotes => 'Show notes';

  @override
  String get filterNew => 'New';

  @override
  String get filterListened => 'Listened';

  @override
  String get filterPodcasts => 'Podcasts';

  @override
  String get filterDownloaded => 'Downloaded';

  @override
  String get filterAlphabetical => 'A–Z';

  @override
  String get filterOldest => 'Oldest first';

  @override
  String get filterPlaying => 'Playing';

  @override
  String get addRssFeed => 'Add RSS feed';

  @override
  String get openFeed => 'Open feed';

  @override
  String get addByRssUrl => 'Add by RSS feed URL';

  @override
  String get subscribeToRss => 'Subscribe to RSS feed';

  @override
  String get searchOnline => 'Search online';

  @override
  String get discoverTabTrending => 'Trending';

  @override
  String get discoverTabSuggestions => 'Suggestions';

  @override
  String get aboutAntpod => 'About AntPod';

  @override
  String get subscriptions => 'Subscriptions';

  @override
  String get markUnplayed => 'Mark as unplayed';

  @override
  String get markPlayed => 'Mark as played';

  @override
  String get cancel => 'Cancel';

  @override
  String get shareEpisode => 'Share episode';

  @override
  String get sharePodcast => 'Share podcast';

  @override
  String get unsubscribe => 'Unsubscribe';

  @override
  String get filterRandom => 'Random';

  @override
  String get removeEpisode => 'Remove episode';

  @override
  String get exportFile => 'Export file';
}
