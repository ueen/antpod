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
  String get emptyFeedTitle => 'Aucun podcast pour l\'instant';

  @override
  String get emptyFeedSub => 'Appuyez sur + pour chercher et vous abonner';

  @override
  String get emptySearchTitle => 'Aucun résultat';

  @override
  String get emptyPodcastsTitle => 'Aucun abonnement pour l\'instant';

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
  String get filterPlaying => 'Commencé';

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
  String get aboutAntpod => 'À propos d\'AntPod';

  @override
  String get markUnplayed => 'Marquer comme non écouté';

  @override
  String get markPlayed => 'Marquer comme écouté';

  @override
  String get cancel => 'Annuler';

  @override
  String get shareEpisode => 'Partager l\'épisode';

  @override
  String get filterRandom => 'Aléatoire';

  @override
  String get removeEpisode => 'Supprimer l\'épisode';

  @override
  String get exportFile => 'Exporter le fichier';

  @override
  String get showAllDownloads => 'Afficher tous les téléchargements';

  @override
  String get downloadNow => 'Télécharger maintenant';

  @override
  String get saveForWifi => 'Enregistrer pour le WiFi';

  @override
  String get cancelWifiQueue => 'Annuler la file WiFi';

  @override
  String get showMarkedForDownload => 'Afficher les marqués pour téléchargement';

  @override
  String get noWifi => 'Pas de WiFi';

  @override
  String get onMobileData => 'Vous êtes sur les données mobiles';

  @override
  String get noConnection => 'Pas de connexion';

  @override
  String get offlineSub => 'Vous êtes hors ligne';

  @override
  String get unsubscribeConfirm => 'Vraiment se désabonner ?';

  @override
  String foundDownloaded(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count épisodes téléchargés trouvés',
      one: '1 épisode téléchargé trouvé',
    );
    return '$_temp0';
  }

  @override
  String foundStarted(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count épisodes commencés trouvés',
      one: '1 épisode commencé trouvé',
    );
    return '$_temp0';
  }

  @override
  String get foundStartedAndDownloaded => 'Épisodes commencés et téléchargés trouvés';

  @override
  String get unsubscribeDeleteAll => 'Se désabonner et supprimer';

  @override
  String get unsubscribeFinishEpisodes => 'Finir d\'écouter';

  @override
  String get stopNewEpisodes => 'Ne plus charger d\'épisodes';

  @override
  String get newEpisodesStopped => 'Nouveaux épisodes non chargés';

  @override
  String get finishingEpisodes => 'Finir d\'écouter';

  @override
  String downloadingEpisodes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Téléchargement de $count épisodes',
      one: 'Téléchargement d\'1 épisode',
    );
    return '$_temp0';
  }

  @override
  String get downloadNotificationChannel => 'Téléchargements';

  @override
  String get aboutText => 'La fourmilière de vos podcasts — chaque épisode y est porté sans relâche. Une éclaireuse agile, éclose de l\'esprit du vénérable AntennaPod.';

  @override
  String get tooltipFilter => 'Filtrer';

  @override
  String get tooltipSearch => 'Rechercher';

  @override
  String get tooltipDiscover => 'Découvrir';

  @override
  String get tooltipGuide => 'Guide';

  @override
  String get trendingError => 'Impossible de charger les tendances';

  @override
  String get trendingEmpty => 'Aucune tendance disponible.';
}
