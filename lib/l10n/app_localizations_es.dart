// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get toolbarSearchHint => 'Buscar episodios…';

  @override
  String get searchHint => 'Buscar podcasts…';

  @override
  String get searchNoResults => 'No se encontraron resultados.';

  @override
  String get emptyFeedTitle => 'Aún no hay podcasts';

  @override
  String get emptyFeedSub => 'Toca + para buscar y suscribirte';

  @override
  String get emptySearchTitle => 'Sin resultados';

  @override
  String get emptyFavoritesTitle => 'Aún no hay favoritos';

  @override
  String get emptyFavoritesSub => 'Mantén pulsado un episodio o toca el corazón en el reproductor';

  @override
  String get emptyPodcastsTitle => 'Aún no hay suscripciones';

  @override
  String get downloaded => 'Descargado';

  @override
  String get downloading => 'Descargar';

  @override
  String get deleteDownload => 'Eliminar descarga';

  @override
  String get shownotes => 'Notas del episodio';

  @override
  String get filterNew => 'Nuevo';

  @override
  String get filterListened => 'Escuchados';

  @override
  String get filterPodcasts => 'Podcasts';

  @override
  String get filterDownloaded => 'Descargados';

  @override
  String get filterFavorites => 'Favoritos';

  @override
  String get filterAlphabetical => 'A–Z';

  @override
  String get filterOldest => 'Más antiguos';

  @override
  String get filterPlaying => 'Empezado';

  @override
  String get addRssFeed => 'Añadir feed RSS';

  @override
  String get openFeed => 'Abrir feed';

  @override
  String get addByRssUrl => 'Añadir por URL RSS';

  @override
  String get subscribeToRss => 'Suscribirse al feed RSS';

  @override
  String get searchOnline => 'Buscar en línea';

  @override
  String get aboutAntpod => 'Sobre AntPod';

  @override
  String get markUnplayed => 'Marcar como no escuchado';

  @override
  String get markPlayed => 'Marcar como escuchado';

  @override
  String get cancel => 'Cancelar';

  @override
  String get shareEpisode => 'Compartir episodio';

  @override
  String get addFavorite => 'Añadir a favoritos';

  @override
  String get removeFavorite => 'Quitar de favoritos';

  @override
  String get sharePodcast => 'Compartir podcast';

  @override
  String get subscribe => 'Suscribirse';

  @override
  String get unsubscribe => 'Cancelar suscripción';

  @override
  String get filterRandom => 'Aleatorio';

  @override
  String get removeEpisode => 'Eliminar episodio';

  @override
  String get exportFile => 'Exportar archivo';

  @override
  String get showAllDownloads => 'Mostrar todas las descargas';

  @override
  String get downloadNow => 'Descargar ahora';

  @override
  String get saveForWifi => 'Guardar para WiFi';

  @override
  String get cancelWifiQueue => 'Cancelar cola WiFi';

  @override
  String get showMarkedForDownload => 'Mostrar marcados para descarga';

  @override
  String get noWifi => 'Sin WiFi';

  @override
  String get onMobileData => 'Estás usando datos móviles';

  @override
  String get noConnection => 'Sin conexión';

  @override
  String get offlineSub => 'Estás sin conexión';

  @override
  String get unsubscribeConfirm => '¿Seguro que quieres cancelar la suscripción?';

  @override
  String foundDownloaded(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count episodios descargados encontrados',
      one: '1 episodio descargado encontrado',
    );
    return '$_temp0';
  }

  @override
  String foundStarted(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count episodios empezados encontrados',
      one: '1 episodio empezado encontrado',
    );
    return '$_temp0';
  }

  @override
  String get foundStartedAndDownloaded => 'Episodios empezados y descargados encontrados';

  @override
  String favoritesKept(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count favoritos se quedan en cualquier caso',
      one: '1 favorito se queda en cualquier caso',
    );
    return '$_temp0';
  }

  @override
  String get unsubscribeDeleteAll => 'Cancelar suscripción y borrar';

  @override
  String get unsubscribeFinishEpisodes => 'Terminar de escuchar';

  @override
  String get stopNewEpisodes => 'No cargar episodios nuevos';

  @override
  String get newEpisodesStopped => 'No se cargan episodios nuevos';

  @override
  String get finishingEpisodes => 'Terminar de escuchar';

  @override
  String get feedNotLoading => 'El feed no se carga';

  @override
  String downloadingEpisodes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Descargando $count episodios',
      one: 'Descargando 1 episodio',
    );
    return '$_temp0';
  }

  @override
  String get downloadNotificationChannel => 'Descargas';

  @override
  String get aboutText => 'El hormiguero de tus podcasts: cada episodio, acarreado sin descanso hasta casa. Una exploradora ágil, nacida del espíritu del venerable AntennaPod.';

  @override
  String get tooltipFilter => 'Filtrar';

  @override
  String get tooltipSearch => 'Buscar';

  @override
  String get tooltipDiscover => 'Descubrir';

  @override
  String get tooltipGuide => 'Guía';

  @override
  String get trendingError => 'No se pudieron cargar las tendencias';

  @override
  String get trendingEmpty => 'No hay tendencias disponibles.';

  @override
  String get trendsCountry => 'País de tendencias';

  @override
  String get trendsCountrySearch => 'Buscar país…';

  @override
  String get playbackError => 'No se pudo reproducir el episodio';

  @override
  String get settings => 'Ajustes';

  @override
  String get settingsAppearance => 'Apariencia';

  @override
  String get settingsMaterialYou => 'Material You';

  @override
  String get settingsMaterialYouSub => 'Los colores de tu fondo de pantalla; si no, AntPod sigue color hormiga';

  @override
  String get settingsTheme => 'Tema';

  @override
  String get settingsThemeSystem => 'Sistema';

  @override
  String get settingsThemeLight => 'Claro';

  @override
  String get settingsThemeDark => 'Oscuro';

  @override
  String get settingsPlayback => 'Reproducción';

  @override
  String get settingsRewindOnResume => 'Retroceder al reanudar';

  @override
  String get settingsRewindOnResumeSub => 'Retrocede 10 segundos tras una pausa de 5 minutos o más, para retomar el hilo';

  @override
  String get settingsMarkPlayedNearEnd => 'Escuchado en el último minuto';

  @override
  String get settingsMarkPlayedNearEndSub => 'Pausar en los últimos 60 segundos marca el episodio como escuchado, para que las despedidas no lo dejen a medias';

  @override
  String get settingsDownloads => 'Descargas';

  @override
  String get settingsDeletePlayed => 'Borrar descargas escuchadas';

  @override
  String get settingsDeletePlayedSub => 'Dos días después de escuchar un episodio; los favoritos se quedan';

  @override
  String get settingsDownloadsFolder => 'Carpeta de descargas';

  @override
  String get settingsDownloadsFolderSub => 'Los episodios descargados en la app Archivos, en AntPod';

  @override
  String get settingsDownloadsFolderFailed => 'No se pudo abrir la app Archivos';

  @override
  String get settingsImportExport => 'Importar y exportar';

  @override
  String get exportBackup => 'Exportar copia de seguridad';

  @override
  String get exportBackupSub => 'Suscripciones, progreso, favoritos y ajustes, para un móvil nuevo';

  @override
  String get importBackup => 'Importar copia de seguridad';

  @override
  String get importBackupSub => 'Se suma a lo que hay; gana el progreso más reciente';

  @override
  String get exportOpml => 'Exportar suscripciones (OPML)';

  @override
  String get exportOpmlSub => 'Para otras apps de podcasts';

  @override
  String get importOpml => 'Importar suscripciones (OPML)';

  @override
  String get importOpmlSub => 'Desde otra app de podcasts';

  @override
  String importProgress(int done, int total) {
    return 'Cargando feeds: $done de $total';
  }

  @override
  String importSubscribed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count podcasts añadidos',
      one: '1 podcast añadido',
      zero: 'Ningún podcast nuevo',
    );
    return '$_temp0';
  }

  @override
  String importEpisodes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count episodios actualizados',
      one: '1 episodio actualizado',
    );
    return '$_temp0';
  }

  @override
  String importFailed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count feeds no cargaron, lo harán en la próxima actualización',
      one: '1 feed no cargó, lo hará en la próxima actualización',
    );
    return '$_temp0';
  }

  @override
  String get importNotBackup => 'Este archivo no es una copia de seguridad de AntPod';

  @override
  String get importNewerBackup => 'Esta copia es de un AntPod más reciente, actualiza la app primero';

  @override
  String get importNotOpml => 'Este archivo no es un archivo OPML';

  @override
  String get importUnreadable => 'No se pudo leer el archivo';

  @override
  String get exportSaved => 'Guardado';

  @override
  String get exportFailed => 'No se pudo guardar el archivo';
}
