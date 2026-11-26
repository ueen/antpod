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
  String get emptyFavoritesTitle => 'Pas encore de favoris';

  @override
  String get emptyFavoritesSub => 'Appuyez longuement sur un épisode ou touchez le cœur dans le lecteur';

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
  String get filterFavorites => 'Favoris';

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
  String get addFavorite => 'Ajouter aux favoris';

  @override
  String get removeFavorite => 'Retirer des favoris';

  @override
  String get sharePodcast => 'Partager le podcast';

  @override
  String get subscribe => 'S\'abonner';

  @override
  String get unsubscribe => 'Se désabonner';

  @override
  String get filterRandom => 'Aléatoire';

  @override
  String get removeEpisode => 'Supprimer l\'épisode';

  @override
  String get exportFile => 'Exporter le fichier';

  @override
  String get showAllDownloads => 'Afficher tous les téléchargements';

  @override
  String get showAllEpisodes => 'Afficher tous les épisodes';

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
  String favoritesKept(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count favoris sont gardés dans tous les cas',
      one: '1 favori est gardé dans tous les cas',
    );
    return '$_temp0';
  }

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
  String get feedNotLoading => 'Le flux ne se charge plus';

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

  @override
  String get trendsCountry => 'Pays des tendances';

  @override
  String get trendsCountrySearch => 'Rechercher un pays…';

  @override
  String get settingsPrivacy => 'Confidentialité';

  @override
  String get settingsAppleApiSub => 'Les tendances et la recherche d\'épisodes viennent d\'Apple. Si désactivé, la recherche trouve les podcasts via PodcastIndex seulement';

  @override
  String get trendsAppleOff => 'Apple Podcasts est désactivé';

  @override
  String get trendsAppleOffSub => 'Les tendances viennent d\'Apple Podcasts. En attendant, la recherche trouve les podcasts via PodcastIndex seulement.';

  @override
  String get trendsAppleOn => 'Activer';

  @override
  String get playbackError => 'Impossible de lire cet épisode';

  @override
  String get settings => 'Paramètres';

  @override
  String get settingsAppearance => 'Apparence';

  @override
  String get settingsMaterialYou => 'Material You';

  @override
  String get settingsMaterialYouSub => 'Les couleurs de votre fond d\'écran';

  @override
  String get settingsTheme => 'Thème';

  @override
  String get settingsThemeAdaptive => 'Adaptatif';

  @override
  String get settingsThemeLight => 'Clair';

  @override
  String get settingsThemeDark => 'Sombre';

  @override
  String get settingsLanguage => 'Langue';

  @override
  String get settingsPlayback => 'Lecture';

  @override
  String get settingsRewindOnResume => 'Reculer à la reprise';

  @override
  String get settingsRewindOnResumeSub => 'Recule de 3 secondes après une pause de 5 minutes ou plus';

  @override
  String get settingsMarkPlayedNearEnd => 'Écouté vers la fin';

  @override
  String get settingsMarkPlayedNearEndSub => 'Une pause dans les 100 dernières secondes marque l\'épisode comme écouté';

  @override
  String get settingsDownloads => 'Téléchargements';

  @override
  String get settingsDeletePlayed => 'Supprimer les téléchargements écoutés';

  @override
  String get settingsDeletePlayedSub => 'Deux jours après l\'écoute d\'un épisode ; les favoris sont gardés';

  @override
  String get settingsDownloadsFolder => 'Dossier des téléchargements';

  @override
  String get settingsDownloadsFolderSub => 'Les épisodes téléchargés dans l\'app Fichiers, sous AntPod';

  @override
  String get settingsDownloadsFolderFailed => 'Impossible d\'ouvrir l\'app Fichiers';

  @override
  String get settingsImportExport => 'Import et export';

  @override
  String get exportBackup => 'Exporter une sauvegarde';

  @override
  String get exportBackupSub => 'Abonnements, progression, favoris et paramètres';

  @override
  String get importBackup => 'Importer une sauvegarde';

  @override
  String get importBackupSub => 'S\'ajoute à l\'existant ; la progression la plus récente est gardée';

  @override
  String get exportOpml => 'Exporter les abonnements (OPML)';

  @override
  String get exportOpmlSub => 'Pour d\'autres apps de podcasts';

  @override
  String get importOpml => 'Importer des abonnements (OPML)';

  @override
  String get importOpmlSub => 'Depuis une autre app de podcasts';

  @override
  String importProgress(int done, int total) {
    return 'Chargement des flux : $done sur $total';
  }

  @override
  String importSubscribed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count podcasts ajoutés',
      one: '1 podcast ajouté',
      zero: 'Aucun nouveau podcast',
    );
    return '$_temp0';
  }

  @override
  String importEpisodes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count épisodes mis à jour',
      one: '1 épisode mis à jour',
    );
    return '$_temp0';
  }

  @override
  String importFailed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count flux n\'ont pas chargé, ils le feront à la prochaine actualisation',
      one: '1 flux n\'a pas chargé, il le fera à la prochaine actualisation',
    );
    return '$_temp0';
  }

  @override
  String get importNotBackup => 'Ce fichier n\'est pas une sauvegarde AntPod';

  @override
  String get importNewerBackup => 'Cette sauvegarde vient d\'un AntPod plus récent, mettez d\'abord l\'app à jour';

  @override
  String get importNotOpml => 'Ce fichier n\'est pas un fichier OPML';

  @override
  String get importUnreadable => 'Impossible de lire ce fichier';

  @override
  String get exportSaved => 'Enregistré';

  @override
  String get exportFailed => 'Impossible d\'enregistrer le fichier';
}
