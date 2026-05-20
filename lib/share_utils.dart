import 'app_database.dart';
import 'podcast_service.dart';

class ShareUtils {
  static const _base = 'https://antpod.eu/open';

  static String podcastUrl(Podcast podcast) =>
      '$_base?feed=${Uri.encodeQueryComponent(podcast.feedUrl)}';

  static String podcastResultUrl(PodcastResult result) =>
      '$_base?feed=${Uri.encodeQueryComponent(result.feedUrl)}';

  static String episodeUrl(Episode episode) =>
      '$_base?feed=${Uri.encodeQueryComponent(episode.podcastId)}'
      '&guid=${Uri.encodeQueryComponent(episode.id)}';
}
