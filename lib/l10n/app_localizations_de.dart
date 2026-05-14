// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get toolbarSearchHint => 'Episoden suchen…';

  @override
  String get searchHint => 'Podcast suchen…';

  @override
  String get searchNoResults => 'Keine Ergebnisse gefunden.';

  @override
  String get sectionTrending => 'Trending diesen Monat';

  @override
  String get sectionRecommended => 'Empfehlungen für dich';

  @override
  String get sectionRecommendedSub => 'basierend auf deinen Abos';

  @override
  String get sectionSearchResults => 'Suchergebnisse';

  @override
  String get emptyFeedTitle => 'Noch keine Podcasts';

  @override
  String get emptyFeedSub => 'Tippe auf + um zu suchen und zu abonnieren';

  @override
  String get emptySearchTitle => 'Keine Ergebnisse';

  @override
  String get emptyPodcastsTitle => 'Noch keine Abonnements';

  @override
  String get subscribeDialogTitle => 'Abonnieren';

  @override
  String subscribed(String title) {
    return '$title abonniert';
  }

  @override
  String get downloaded => 'Heruntergeladen';

  @override
  String get downloading => 'Herunterladen';

  @override
  String get deleteDownload => 'Download löschen';

  @override
  String get shownotes => 'Shownotes';

  @override
  String get filterNew => 'Neu';

  @override
  String get filterListened => 'Gehört';

  @override
  String get filterPodcasts => 'Podcasts';

  @override
  String get filterDownloaded => 'Offline';

  @override
  String get filterAlphabetical => 'A–Z';

  @override
  String get filterOldest => 'Älteste zuerst';

  @override
  String get filterPlaying => 'Läuft';

  @override
  String get addRssFeed => 'RSS-Feed hinzufügen';

  @override
  String get openFeed => 'Feed öffnen';

  @override
  String get addByRssUrl => 'Per RSS-URL hinzufügen';

  @override
  String get subscribeToRss => 'RSS-Feed abonnieren';

  @override
  String get searchOnline => 'Online suchen';

  @override
  String get discoverTabTrending => 'Trends';

  @override
  String get discoverTabSuggestions => 'Vorschläge';

  @override
  String get aboutAntpod => 'Über AntPod';

  @override
  String get subscriptions => 'Abonnements';

  @override
  String get markUnplayed => 'Als ungehört markieren';

  @override
  String get markPlayed => 'Als gehört markieren';

  @override
  String get cancel => 'Abbrechen';

  @override
  String get shareEpisode => 'Episode teilen';

  @override
  String get sharePodcast => 'Podcast teilen';

  @override
  String get unsubscribe => 'Abonnement beenden';
}
