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
  String get playbackError => 'No se pudo reproducir el episodio';
}
