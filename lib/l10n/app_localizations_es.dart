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
  String get sectionTrending => 'Tendencias esta semana';

  @override
  String get sectionRecommended => 'Recomendado para ti';

  @override
  String get sectionRecommendedSub => 'basado en tus suscripciones';

  @override
  String get sectionSearchResults => 'Resultados de búsqueda';

  @override
  String get emptyFeedTitle => 'Aún no hay podcasts';

  @override
  String get emptyFeedSub => 'Toca + para buscar y suscribirte';

  @override
  String get emptySearchTitle => 'Sin resultados';

  @override
  String get emptyPodcastsTitle => 'Aún no hay suscripciones';

  @override
  String get subscribeDialogTitle => 'Suscribirse';

  @override
  String subscribed(String title) {
    return 'Suscrito a \"$title\"';
  }

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
  String get filterPodcast => 'Podcast';

  @override
  String get filterPodcasts => 'Podcasts';

  @override
  String get filterDownloaded => 'Descargados';

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
  String get discoverTabTrending => 'Tendencias';

  @override
  String get discoverTabSuggestions => 'Sugerencias';

  @override
  String get aboutAntpod => 'Sobre AntPod';

  @override
  String get subscriptions => 'Suscripciones';

  @override
  String get markUnplayed => 'Marcar como no escuchado';

  @override
  String get markPlayed => 'Marcar como escuchado';

  @override
  String get cancel => 'Cancelar';

  @override
  String get shareEpisode => 'Compartir episodio';

  @override
  String get sharePodcast => 'Compartir podcast';

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
  String get unsubscribeDeleteAll => 'Cancelar suscripción y borrar todo';

  @override
  String get unsubscribeKeepEpisodes => 'Cancelar suscripción, conservar episodios';

  @override
  String get unsubscribeKeepHint => 'Los episodios descargados y empezados se quedan hasta escucharlos';

  @override
  String get pauseSync => 'Pausar sincronización';

  @override
  String get resumeSync => 'Reanudar sincronización';

  @override
  String get syncPaused => 'Sincronización en pausa';

  @override
  String get pauseSyncHint => 'Conserva los episodios, sin buscar nuevos';

  @override
  String get unsubscribeStopsPlayback => 'Se detendrá la reproducción de este podcast.';

  @override
  String unsubscribeDeletesDownloads(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Se borrarán $count episodios descargados.',
      one: 'Se borrará 1 episodio descargado.',
    );
    return '$_temp0';
  }
}
