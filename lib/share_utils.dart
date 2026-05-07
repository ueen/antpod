import 'app_database.dart';
import 'podcast_service.dart';

class ShareUtils {
  static const _base = 'https://antpod.eu/open';

  static String podcastUrl(Podcast podcast) => _podcastParams(
        feedUrl: podcast.feedUrl,
        title: podcast.title,
        imageUrl: podcast.imageUrl,
      );

  static String podcastResultUrl(PodcastResult result) => _podcastParams(
        feedUrl: result.feedUrl,
        title: result.title,
        imageUrl: result.imageUrl,
        podcastIndexId: result.id,
      );

  static String episodeUrl(Episode episode) {
    final params = <String, String>{
      'feed': episode.podcastId,
      'guid': episode.id,
      'title': episode.title,
      'podcast': episode.podcastTitle,
      'cover': episode.podcastImageUrl,
      'audio': episode.audioUrl,
      if (episode.durationSeconds > 0)
        'duration': episode.durationSeconds.toString(),
    };
    return '$_base?${_encode(params)}';
  }

  static String _podcastParams({
    required String feedUrl,
    required String title,
    required String imageUrl,
    String podcastIndexId = '',
  }) {
    final params = <String, String>{
      'feed': feedUrl,
      'title': title,
      'cover': imageUrl,
      if (podcastIndexId.isNotEmpty && _isNumeric(podcastIndexId))
        'id': podcastIndexId,
    };
    return '$_base?${_encode(params)}';
  }

  static bool _isNumeric(String s) => int.tryParse(s) != null;

  static String _encode(Map<String, String> params) => params.entries
      .map((e) =>
          '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
      .join('&');
}
