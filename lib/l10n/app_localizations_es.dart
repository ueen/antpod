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
  String get sectionTrending => 'Tendencias este mes';

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
  String get filterPodcasts => 'Podcasts';

  @override
  String get filterDownloaded => 'Descargados';

  @override
  String get filterAlphabetical => 'A–Z';

  @override
  String get filterOldest => 'Más antiguos';

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
}
