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
  String get emptyFeedTitle => 'No podcasts yet';

  @override
  String get emptyFeedSub => 'Tap + to search and subscribe';

  @override
  String get emptySearchTitle => 'No results';

  @override
  String get emptyFavoritesTitle => 'No favourites yet';

  @override
  String get emptyFavoritesSub => 'Long-press an episode, or tap the heart in the player';

  @override
  String get emptyPodcastsTitle => 'No subscriptions yet';

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
  String get filterFavorites => 'Favourites';

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
  String get addByRssUrl => 'Add by RSS URL';

  @override
  String get subscribeToRss => 'Subscribe to RSS feed';

  @override
  String get searchOnline => 'Search online';

  @override
  String get aboutAntpod => 'About AntPod';

  @override
  String get markUnplayed => 'Mark as unplayed';

  @override
  String get markPlayed => 'Mark as played';

  @override
  String get cancel => 'Cancel';

  @override
  String get shareEpisode => 'Share episode';

  @override
  String get addFavorite => 'Add to favourites';

  @override
  String get removeFavorite => 'Remove from favourites';

  @override
  String get sharePodcast => 'Share podcast';

  @override
  String get subscribe => 'Subscribe';

  @override
  String get unsubscribe => 'Unsubscribe';

  @override
  String get filterRandom => 'Random';

  @override
  String get removeEpisode => 'Remove episode';

  @override
  String get exportFile => 'Export file';

  @override
  String get showAllDownloads => 'Show all downloads';

  @override
  String get downloadNow => 'Download now';

  @override
  String get saveForWifi => 'Save for WiFi';

  @override
  String get cancelWifiQueue => 'Cancel WiFi queue';

  @override
  String get showMarkedForDownload => 'Show marked for download';

  @override
  String get noWifi => 'No WiFi';

  @override
  String get onMobileData => 'You\'re on mobile data';

  @override
  String get noConnection => 'No connection';

  @override
  String get offlineSub => 'You\'re offline';

  @override
  String get unsubscribeConfirm => 'Sure you want to unsubscribe?';

  @override
  String foundDownloaded(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count downloaded episodes found',
      one: '1 downloaded episode found',
    );
    return '$_temp0';
  }

  @override
  String foundStarted(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count started episodes found',
      one: '1 started episode found',
    );
    return '$_temp0';
  }

  @override
  String get foundStartedAndDownloaded => 'Started and downloaded episodes found';

  @override
  String favoritesKept(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count favourites stay either way',
      one: '1 favourite stays either way',
    );
    return '$_temp0';
  }

  @override
  String get unsubscribeDeleteAll => 'Unsubscribe & delete';

  @override
  String get unsubscribeFinishEpisodes => 'Finish episodes';

  @override
  String get stopNewEpisodes => 'Don\'t load new episodes';

  @override
  String get newEpisodesStopped => 'Not loading new episodes';

  @override
  String get finishingEpisodes => 'Finishing episodes';

  @override
  String get feedNotLoading => 'Feed hasn\'t loaded lately';

  @override
  String downloadingEpisodes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Downloading $count episodes',
      one: 'Downloading 1 episode',
    );
    return '$_temp0';
  }

  @override
  String get downloadNotificationChannel => 'Downloads';

  @override
  String get aboutText => 'The anthill for your podcasts — every episode carried home to the hill tirelessly. A nimble scout hatched from the spirit of the grand old AntennaPod.';

  @override
  String get tooltipFilter => 'Filter';

  @override
  String get tooltipSearch => 'Search';

  @override
  String get tooltipDiscover => 'Discover';

  @override
  String get tooltipGuide => 'Guide';

  @override
  String get trendingError => 'Could not load trending podcasts';

  @override
  String get trendingEmpty => 'No trending podcasts available.';

  @override
  String get trendsCountry => 'Trends country';

  @override
  String get trendsCountrySearch => 'Search countries…';

  @override
  String get settingsNetwork => 'Network';

  @override
  String get settingsAppleApiSub => 'Trends and episode search come from Apple. Off, search finds podcasts through PodcastIndex only';

  @override
  String get trendsAppleOff => 'Apple Podcasts is off';

  @override
  String get trendsAppleOffSub => 'The trends come from Apple Podcasts. Meanwhile, search finds podcasts through PodcastIndex only.';

  @override
  String get trendsAppleOn => 'Turn on';

  @override
  String get playbackError => 'Couldn\'t play this episode';

  @override
  String get settings => 'Settings';

  @override
  String get settingsAppearance => 'Appearance';

  @override
  String get settingsMaterialYou => 'Material You';

  @override
  String get settingsMaterialYouSub => 'Colours from your wallpaper; otherwise AntPod stays ant coloured';

  @override
  String get settingsTheme => 'Theme';

  @override
  String get settingsThemeSystem => 'System';

  @override
  String get settingsThemeLight => 'Light';

  @override
  String get settingsThemeDark => 'Dark';

  @override
  String get settingsPlayback => 'Playback';

  @override
  String get settingsRewindOnResume => 'Rewind on resume';

  @override
  String get settingsRewindOnResumeSub => 'Back 10 seconds after a pause of 5 minutes or more, to pick up the thread';

  @override
  String get settingsMarkPlayedNearEnd => 'Played in the last minute';

  @override
  String get settingsMarkPlayedNearEndSub => 'Pausing in an episode\'s last 60 seconds marks it as played, so outros don\'t leave it half done';

  @override
  String get settingsDownloads => 'Downloads';

  @override
  String get settingsDeletePlayed => 'Delete played downloads';

  @override
  String get settingsDeletePlayedSub => 'Two days after an episode is played; favourites are kept';

  @override
  String get settingsDownloadsFolder => 'Downloads folder';

  @override
  String get settingsDownloadsFolderSub => 'The downloaded episodes in the Files app, under AntPod';

  @override
  String get settingsDownloadsFolderFailed => 'Couldn\'t open the Files app';

  @override
  String get settingsImportExport => 'Import & export';

  @override
  String get exportBackup => 'Export backup';

  @override
  String get exportBackupSub => 'Subscriptions, play state, favourites and settings, for a new phone';

  @override
  String get importBackup => 'Import backup';

  @override
  String get importBackupSub => 'Adds to what\'s here; the newer play state wins';

  @override
  String get exportOpml => 'Export subscriptions (OPML)';

  @override
  String get exportOpmlSub => 'For other podcast apps';

  @override
  String get importOpml => 'Import subscriptions (OPML)';

  @override
  String get importOpmlSub => 'From another podcast app';

  @override
  String importProgress(int done, int total) {
    return 'Loading feeds: $done of $total';
  }

  @override
  String importSubscribed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count podcasts added',
      one: '1 podcast added',
      zero: 'No new podcasts',
    );
    return '$_temp0';
  }

  @override
  String importEpisodes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count episodes updated',
      one: '1 episode updated',
    );
    return '$_temp0';
  }

  @override
  String importFailed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count feeds didn\'t load, they will on the next refresh',
      one: '1 feed didn\'t load, it will on the next refresh',
    );
    return '$_temp0';
  }

  @override
  String get importNotBackup => 'This file isn\'t an AntPod backup';

  @override
  String get importNewerBackup => 'This backup is from a newer AntPod, update the app first';

  @override
  String get importNotOpml => 'This file isn\'t an OPML file';

  @override
  String get importUnreadable => 'Couldn\'t read this file';

  @override
  String get exportSaved => 'Saved';

  @override
  String get exportFailed => 'Couldn\'t save the file';
}
