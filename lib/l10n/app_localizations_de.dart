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
  String get emptyFeedTitle => 'Noch keine Podcasts';

  @override
  String get emptyFeedSub => 'Tippe auf + um zu suchen und zu abonnieren';

  @override
  String get emptySearchTitle => 'Keine Ergebnisse';

  @override
  String get emptyFavoritesTitle => 'Noch keine Favoriten';

  @override
  String get emptyFavoritesSub => 'Episode lange drücken oder im Player aufs Herz tippen';

  @override
  String get emptyPodcastsTitle => 'Noch keine Abonnements';

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
  String get filterFavorites => 'Favoriten';

  @override
  String get filterAlphabetical => 'A–Z';

  @override
  String get filterOldest => 'Älteste zuerst';

  @override
  String get filterPlaying => 'Angefangen';

  @override
  String get addRssFeed => 'RSS-Feed hinzufügen';

  @override
  String get openFeed => 'Feed öffnen';

  @override
  String get addByRssUrl => 'RSS-URL hinzufügen';

  @override
  String get subscribeToRss => 'RSS-Feed abonnieren';

  @override
  String get searchOnline => 'Online suchen';

  @override
  String get aboutAntpod => 'Über AntPod';

  @override
  String get markUnplayed => 'Als ungehört markieren';

  @override
  String get markPlayed => 'Als gehört markieren';

  @override
  String get cancel => 'Abbrechen';

  @override
  String get shareEpisode => 'Episode teilen';

  @override
  String get addFavorite => 'Zu Favoriten hinzufügen';

  @override
  String get removeFavorite => 'Aus Favoriten entfernen';

  @override
  String get sharePodcast => 'Podcast teilen';

  @override
  String get subscribe => 'Abonnieren';

  @override
  String get unsubscribe => 'Abo beenden';

  @override
  String get filterRandom => 'Zufällig';

  @override
  String get removeEpisode => 'Episode entfernen';

  @override
  String get exportFile => 'Datei exportieren';

  @override
  String get showAllDownloads => 'Alle Downloads anzeigen';

  @override
  String get showAllEpisodes => 'Alle Folgen anzeigen';

  @override
  String get downloadNow => 'Jetzt herunterladen';

  @override
  String get saveForWifi => 'Im WLAN herunterladen';

  @override
  String get cancelWifiQueue => 'WLAN-Download abbrechen';

  @override
  String get showMarkedForDownload => 'Für WLAN vorgemerkte anzeigen';

  @override
  String get noWifi => 'Kein WLAN';

  @override
  String get onMobileData => 'Du bist im Mobilfunknetz';

  @override
  String get noConnection => 'Keine Verbindung';

  @override
  String get offlineSub => 'Du bist offline';

  @override
  String get unsubscribeConfirm => 'Abo wirklich beenden?';

  @override
  String foundDownloaded(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count heruntergeladene Folgen gefunden',
      one: '1 heruntergeladene Folge gefunden',
    );
    return '$_temp0';
  }

  @override
  String foundStarted(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count angefangene Folgen gefunden',
      one: '1 angefangene Folge gefunden',
    );
    return '$_temp0';
  }

  @override
  String get foundStartedAndDownloaded => 'Angefangene und heruntergeladene Folgen gefunden';

  @override
  String favoritesKept(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Favoriten bleiben so oder so',
      one: '1 Favorit bleibt so oder so',
    );
    return '$_temp0';
  }

  @override
  String get unsubscribeDeleteAll => 'Abo beenden & löschen';

  @override
  String get unsubscribeFinishEpisodes => 'Zu Ende hören';

  @override
  String get stopNewEpisodes => 'Keine neuen Folgen laden';

  @override
  String get newEpisodesStopped => 'Lädt keine neuen Folgen';

  @override
  String get finishingEpisodes => 'Zu Ende hören';

  @override
  String get feedNotLoading => 'Feed lädt derzeit nicht';

  @override
  String downloadingEpisodes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Folgen werden geladen',
      one: '1 Folge wird geladen',
    );
    return '$_temp0';
  }

  @override
  String get downloadNotificationChannel => 'Downloads';

  @override
  String get aboutText => 'Der Ameisenhaufen für deine Podcasts – jede Folge, unermüdlich heimgetragen. Eine flinke Kundschafterin, geschlüpft aus dem Geist des ehrwürdigen AntennaPod.';

  @override
  String get tooltipFilter => 'Filter';

  @override
  String get tooltipSearch => 'Suchen';

  @override
  String get tooltipDiscover => 'Entdecken';

  @override
  String get tooltipGuide => 'Anleitung';

  @override
  String get trendingError => 'Trends konnten nicht geladen werden';

  @override
  String get trendingEmpty => 'Gerade keine Trends verfügbar.';

  @override
  String get trendsCountry => 'Land für Trends';

  @override
  String get trendsCountrySearch => 'Land suchen…';

  @override
  String get settingsPrivacy => 'Datenschutz';

  @override
  String get settingsAppleApiSub => 'Trends und Folgensuche kommen von Apple. Ausgeschaltet findet die Suche Podcasts nur über PodcastIndex';

  @override
  String get trendsAppleOff => 'Apple Podcasts ist aus';

  @override
  String get trendsAppleOffSub => 'Die Trends kommen von Apple Podcasts. Solange es aus ist, findet die Suche Podcasts nur über PodcastIndex.';

  @override
  String get trendsAppleOn => 'Einschalten';

  @override
  String get playbackError => 'Episode konnte nicht abgespielt werden';

  @override
  String get settings => 'Einstellungen';

  @override
  String get settingsAppearance => 'Darstellung';

  @override
  String get settingsMaterialYou => 'Material You';

  @override
  String get settingsMaterialYouSub => 'Farben vom Hintergrundbild';

  @override
  String get settingsTheme => 'Design';

  @override
  String get settingsThemeAdaptive => 'Adaptiv';

  @override
  String get settingsThemeLight => 'Hell';

  @override
  String get settingsThemeDark => 'Dunkel';

  @override
  String get settingsLanguage => 'Sprache';

  @override
  String get settingsPlayback => 'Wiedergabe';

  @override
  String get settingsRewindOnResume => 'Beim Fortsetzen zurückspulen';

  @override
  String get settingsRewindOnResumeSub => 'Geht nach einer Pause ab 5 Minuten 3 Sekunden zurück';

  @override
  String get settingsMarkPlayedNearEnd => 'Gegen Ende gehört';

  @override
  String get settingsMarkPlayedNearEndSub => 'Pausieren in den letzten 100 Sekunden markiert die Folge als gehört';

  @override
  String get settingsDownloads => 'Downloads';

  @override
  String get settingsDeletePlayed => 'Gehörte Downloads löschen';

  @override
  String get settingsDeletePlayedSub => 'Zwei Tage nachdem eine Folge gehört wurde; Favoriten bleiben';

  @override
  String get settingsDownloadsFolder => 'Download-Ordner';

  @override
  String get settingsDownloadsFolderSub => 'Die heruntergeladenen Folgen in der Dateien-App, unter AntPod';

  @override
  String get settingsDownloadsFolderFailed => 'Die Dateien-App ließ sich nicht öffnen';

  @override
  String get settingsImportExport => 'Import & Export';

  @override
  String get exportBackup => 'Backup exportieren';

  @override
  String get exportBackupSub => 'Abos, Wiedergabestand, Favoriten und Einstellungen';

  @override
  String get importBackup => 'Backup importieren';

  @override
  String get importBackupSub => 'Ergänzt, was da ist; der neuere Wiedergabestand bleibt';

  @override
  String get exportOpml => 'Abos exportieren (OPML)';

  @override
  String get exportOpmlSub => 'Für andere Podcast-Apps';

  @override
  String get importOpml => 'Abos importieren (OPML)';

  @override
  String get importOpmlSub => 'Aus einer anderen Podcast-App';

  @override
  String importProgress(int done, int total) {
    return 'Feeds laden: $done von $total';
  }

  @override
  String importSubscribed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Podcasts hinzugefügt',
      one: '1 Podcast hinzugefügt',
      zero: 'Keine neuen Podcasts',
    );
    return '$_temp0';
  }

  @override
  String importEpisodes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Folgen aktualisiert',
      one: '1 Folge aktualisiert',
    );
    return '$_temp0';
  }

  @override
  String importFailed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Feeds haben nicht geladen, sie laden beim nächsten Aktualisieren',
      one: '1 Feed hat nicht geladen, er lädt beim nächsten Aktualisieren',
    );
    return '$_temp0';
  }

  @override
  String get importNotBackup => 'Diese Datei ist kein AntPod-Backup';

  @override
  String get importNewerBackup => 'Dieses Backup stammt von einem neueren AntPod, bitte zuerst die App aktualisieren';

  @override
  String get importNotOpml => 'Diese Datei ist keine OPML-Datei';

  @override
  String get importUnreadable => 'Die Datei ließ sich nicht lesen';

  @override
  String get exportSaved => 'Gespeichert';

  @override
  String get exportFailed => 'Die Datei ließ sich nicht speichern';
}
