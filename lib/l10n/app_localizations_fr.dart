// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get toolbarSearchHint => 'Rechercher des épisodes…';

  @override
  String get searchHint => 'Rechercher des podcasts…';

  @override
  String get searchNoResults => 'Aucun résultat trouvé.';

  @override
  String get sectionTrending => 'Tendances ce mois-ci';

  @override
  String get sectionRecommended => 'Recommandé pour vous';

  @override
  String get sectionRecommendedSub => 'basé sur vos abonnements';

  @override
  String get sectionSearchResults => 'Résultats de recherche';

  @override
  String get emptyFeedTitle => 'Aucun podcast pour l\'instant';

  @override
  String get emptyFeedSub => 'Appuyez sur + pour chercher et vous abonner';

  @override
  String get emptySearchTitle => 'Aucun résultat';

  @override
  String get emptyPodcastsTitle => 'Aucun abonnement pour l\'instant';

  @override
  String get subscribeDialogTitle => 'S\'abonner';

  @override
  String subscribed(String title) {
    return 'Abonné à \"$title\"';
  }

  @override
  String get downloaded => 'Téléchargé';

  @override
  String get downloading => 'Télécharger';

  @override
  String get deleteDownload => 'Supprimer le téléchargement';

  @override
  String get shownotes => 'Notes de l\'épisode';

  @override
  String get filterNew => 'Nouveau';

  @override
  String get filterListened => 'Écoutés';

  @override
  String get filterPodcasts => 'Podcasts';

  @override
  String get filterDownloaded => 'Téléchargés';

  @override
  String get filterAlphabetical => 'A–Z';

  @override
  String get filterOldest => 'Les plus anciens';
  @override
  String get filterRandom => 'Aléatoire';

  @override
  String get filterPlaying => 'En cours';

  @override
  String get addRssFeed => 'Ajouter un flux RSS';

  @override
  String get openFeed => 'Ouvrir le flux';

  @override
  String get addByRssUrl => 'Ajouter par URL RSS';

  @override
  String get subscribeToRss => 'S\'abonner au flux RSS';

  @override
  String get searchOnline => 'Rechercher en ligne';

  @override
  String get discoverTabTrending => 'Tendances';

  @override
  String get discoverTabSuggestions => 'Suggestions';

  @override
  String get aboutAntpod => 'À propos d\'AntPod';

  @override
  String get subscriptions => 'Abonnements';

  @override
  String get markUnplayed => 'Marquer comme non écouté';

  @override
  String get markPlayed => 'Marquer comme écouté';

  @override
  String get cancel => 'Annuler';

  @override
  String get shareEpisode => 'Partager l\'épisode';

  @override
  String get sharePodcast => 'Partager le podcast';

  @override
  String get unsubscribe => 'Se désabonner';
}
