// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Italian (`it`).
class AppLocalizationsIt extends AppLocalizations {
  AppLocalizationsIt([String locale = 'it']) : super(locale);

  @override
  String get toolbarSearchHint => 'Cerca episodi…';

  @override
  String get searchHint => 'Cerca podcast…';

  @override
  String get searchNoResults => 'Nessun risultato.';

  @override
  String get emptyFeedTitle => 'Ancora nessun podcast';

  @override
  String get emptyFeedSub => 'Tocca + per cercare e iscriverti';

  @override
  String get emptySearchTitle => 'Nessun risultato';

  @override
  String get emptyFavoritesTitle => 'Ancora nessun preferito';

  @override
  String get emptyFavoritesSub => 'Tieni premuto un episodio o tocca il cuore nel lettore';

  @override
  String get emptyPodcastsTitle => 'Ancora nessuna iscrizione';

  @override
  String get downloaded => 'Scaricato';

  @override
  String get downloading => 'Scarica';

  @override
  String get deleteDownload => 'Elimina download';

  @override
  String get shownotes => 'Note dell\'episodio';

  @override
  String get filterNew => 'Nuovi';

  @override
  String get filterListened => 'Ascoltati';

  @override
  String get filterPodcasts => 'Podcast';

  @override
  String get filterDownloaded => 'Scaricati';

  @override
  String get filterFavorites => 'Preferiti';

  @override
  String get filterAlphabetical => 'A–Z';

  @override
  String get filterOldest => 'Meno recenti';

  @override
  String get filterPlaying => 'Iniziati';

  @override
  String get addRssFeed => 'Aggiungi feed RSS';

  @override
  String get openFeed => 'Apri feed';

  @override
  String get addByRssUrl => 'Aggiungi tramite URL RSS';

  @override
  String get subscribeToRss => 'Iscriviti al feed RSS';

  @override
  String get searchOnline => 'Cerca online';

  @override
  String get aboutAntpod => 'Info su AntPod';

  @override
  String get markUnplayed => 'Segna come non ascoltato';

  @override
  String get markPlayed => 'Segna come ascoltato';

  @override
  String get cancel => 'Annulla';

  @override
  String get shareEpisode => 'Condividi episodio';

  @override
  String get addFavorite => 'Aggiungi ai preferiti';

  @override
  String get removeFavorite => 'Rimuovi dai preferiti';

  @override
  String get sharePodcast => 'Condividi podcast';

  @override
  String get subscribe => 'Iscriviti';

  @override
  String get unsubscribe => 'Annulla iscrizione';

  @override
  String get filterRandom => 'Casuale';

  @override
  String get removeEpisode => 'Rimuovi episodio';

  @override
  String get exportFile => 'Esporta file';

  @override
  String get showAllDownloads => 'Mostra tutti i download';

  @override
  String get showAllEpisodes => 'Mostra tutti gli episodi';

  @override
  String get downloadNow => 'Scarica ora';

  @override
  String get saveForWifi => 'Salva per il WiFi';

  @override
  String get cancelWifiQueue => 'Annulla coda WiFi';

  @override
  String get showMarkedForDownload => 'Mostra quelli da scaricare';

  @override
  String get noWifi => 'Nessun WiFi';

  @override
  String get onMobileData => 'Stai usando i dati mobili';

  @override
  String get noConnection => 'Nessuna connessione';

  @override
  String get offlineSub => 'Sei offline';

  @override
  String get unsubscribeConfirm => 'Vuoi davvero annullare l\'iscrizione?';

  @override
  String foundDownloaded(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Trovati $count episodi scaricati',
      one: 'Trovato 1 episodio scaricato',
    );
    return '$_temp0';
  }

  @override
  String foundStarted(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Trovati $count episodi iniziati',
      one: 'Trovato 1 episodio iniziato',
    );
    return '$_temp0';
  }

  @override
  String get foundStartedAndDownloaded => 'Trovati episodi iniziati e scaricati';

  @override
  String favoritesKept(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count preferiti restano in ogni caso',
      one: '1 preferito resta in ogni caso',
    );
    return '$_temp0';
  }

  @override
  String get unsubscribeDeleteAll => 'Annulla iscrizione ed elimina';

  @override
  String get unsubscribeFinishEpisodes => 'Finisci di ascoltare';

  @override
  String get stopNewEpisodes => 'Non caricare nuovi episodi';

  @override
  String get newEpisodesStopped => 'Non carica nuovi episodi';

  @override
  String get finishingEpisodes => 'Finisci di ascoltare';

  @override
  String get feedNotLoading => 'Il feed non si carica da un po\'';

  @override
  String downloadingEpisodes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Download di $count episodi',
      one: 'Download di 1 episodio',
    );
    return '$_temp0';
  }

  @override
  String get downloadNotificationChannel => 'Download';

  @override
  String get aboutText => 'Il formicaio dei tuoi podcast — ogni episodio portato a casa, instancabilmente. Un\'agile esploratrice nata dallo spirito del grande, vecchio AntennaPod.';

  @override
  String get tooltipFilter => 'Filtra';

  @override
  String get tooltipSearch => 'Cerca';

  @override
  String get tooltipDiscover => 'Scopri';

  @override
  String get tooltipGuide => 'Guida';

  @override
  String get trendingError => 'Impossibile caricare le tendenze';

  @override
  String get trendingEmpty => 'Nessuna tendenza disponibile.';

  @override
  String get trendsCountry => 'Paese delle tendenze';

  @override
  String get trendsCountrySearch => 'Cerca un paese…';

  @override
  String get settingsPrivacy => 'Privacy';

  @override
  String get settingsAppleApiSub => 'Tendenze e ricerca di episodi usano Apple. Se disattivato, la ricerca trova i podcast solo tramite PodcastIndex';

  @override
  String get trendsAppleOff => 'Apple Podcasts è disattivato';

  @override
  String get trendsAppleOffSub => 'Le tendenze vengono da Apple Podcasts. Intanto la ricerca trova i podcast solo tramite PodcastIndex.';

  @override
  String get trendsAppleOn => 'Attiva';

  @override
  String get playbackError => 'Impossibile riprodurre questo episodio';

  @override
  String get settings => 'Impostazioni';

  @override
  String get settingsAppearance => 'Aspetto';

  @override
  String get settingsMaterialYou => 'Material You';

  @override
  String get settingsMaterialYouSub => 'I colori del tuo sfondo';

  @override
  String get settingsTheme => 'Tema';

  @override
  String get settingsThemeAdaptive => 'Adattivo';

  @override
  String get settingsThemeLight => 'Chiaro';

  @override
  String get settingsThemeDark => 'Scuro';

  @override
  String get settingsLanguage => 'Lingua';

  @override
  String get settingsPlayback => 'Riproduzione';

  @override
  String get settingsRewindOnResume => 'Riavvolgi alla ripresa';

  @override
  String get settingsRewindOnResumeSub => 'Torna indietro di 3 secondi dopo una pausa di 5 minuti o più';

  @override
  String get settingsMarkPlayedNearEnd => 'Ascoltato verso la fine';

  @override
  String get settingsMarkPlayedNearEndSub => 'Una pausa negli ultimi 100 secondi segna l\'episodio come ascoltato';

  @override
  String get settingsDownloads => 'Download';

  @override
  String get settingsDeletePlayed => 'Elimina i download ascoltati';

  @override
  String get settingsDeletePlayedSub => 'Due giorni dopo l\'ascolto di un episodio; i preferiti restano';

  @override
  String get settingsDownloadsFolder => 'Cartella dei download';

  @override
  String get settingsDownloadsFolderSub => 'Gli episodi scaricati nell\'app File, sotto AntPod';

  @override
  String get settingsDownloadsFolderFailed => 'Impossibile aprire l\'app File';

  @override
  String get settingsImportExport => 'Importa ed esporta';

  @override
  String get exportBackup => 'Esporta backup';

  @override
  String get exportBackupSub => 'Iscrizioni, avanzamento, preferiti e impostazioni';

  @override
  String get importBackup => 'Importa backup';

  @override
  String get importBackupSub => 'Si aggiunge a ciò che c\'è; resta l\'avanzamento più recente';

  @override
  String get exportOpml => 'Esporta iscrizioni (OPML)';

  @override
  String get exportOpmlSub => 'Per altre app di podcast';

  @override
  String get importOpml => 'Importa iscrizioni (OPML)';

  @override
  String get importOpmlSub => 'Da un\'altra app di podcast';

  @override
  String importProgress(int done, int total) {
    return 'Caricamento dei feed: $done di $total';
  }

  @override
  String importSubscribed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count podcast aggiunti',
      one: '1 podcast aggiunto',
      zero: 'Nessun nuovo podcast',
    );
    return '$_temp0';
  }

  @override
  String importEpisodes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count episodi aggiornati',
      one: '1 episodio aggiornato',
    );
    return '$_temp0';
  }

  @override
  String importFailed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count feed non si sono caricati, lo faranno al prossimo aggiornamento',
      one: '1 feed non si è caricato, lo farà al prossimo aggiornamento',
    );
    return '$_temp0';
  }

  @override
  String get importNotBackup => 'Questo file non è un backup di AntPod';

  @override
  String get importNewerBackup => 'Questo backup viene da un AntPod più recente, aggiorna prima l\'app';

  @override
  String get importNotOpml => 'Questo file non è un file OPML';

  @override
  String get importUnreadable => 'Impossibile leggere questo file';

  @override
  String get exportSaved => 'Salvato';

  @override
  String get exportFailed => 'Impossibile salvare il file';

  @override
  String get offFeed => 'fuori feed';
}
