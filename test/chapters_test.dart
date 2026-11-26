import 'package:antpod/chapters.dart';
import 'package:antpod/file_chapters.dart';
import 'package:flutter_test/flutter_test.dart';

FileChapter _fc(int startMs, String title) =>
    (startMs: startMs, title: title, image: null);

List<String> _titles(List<PodcastChapter> c) => [for (final x in c) x.title];
List<double> _starts(List<PodcastChapter> c) =>
    [for (final x in c) x.startTimeSeconds];

void main() {
  group('mergeChapters', () {
    test('one titled chapter among untitled ones is no chapter list', () {
      // Talk ohne Gast: an editor's cue mark carried into the ID3 tag.
      final file = [
        _fc(1545000, 'Marker 1 - 1'),
        _fc(1545400, ''),
        _fc(1546000, ''),
        _fc(1600000, ''),
        _fc(1700000, ''),
      ];
      expect(mergeChapters(null, file), isEmpty);
    });

    test('two titled chapters are kept', () {
      final file = [_fc(0, 'Intro'), _fc(60000, ''), _fc(120000, 'Main')];
      expect(_titles(mergeChapters(null, file)), ['Intro', 'Main']);
    });

    test('a single feed chapter is no chapter list either', () {
      const feed = [PodcastChapter(title: 'Episode', startTimeSeconds: 0)];
      expect(mergeChapters(feed, null), isEmpty);
    });
  });

  group('notesChapters', () {
    test('bracketed times with a dash before the title', () {
      const notes = '<ul><li>(00:00) - Welcome to the Show</li>'
          '<li>(02:13) - The Story of Malls</li>'
          '<li>(18:56) - Discussing Chopping Mall</li></ul>';
      final c = notesChapters(notes, 6000);
      expect(_titles(c),
          ['Welcome to the Show', 'The Story of Malls', 'Discussing Chopping Mall']);
      expect(_starts(c), [0, 133, 1136]);
    });

    test('the chapters listed twice, as ranges and as starts', () {
      // Legion Podcasts (Pick Six Movies): time going back to 00:00 starts
      // the second list instead of discarding both.
      const notes = '<p>Intro text.</p>'
          '<p>00:00:00 – 00:02:12 – Welcome to the Show with Chad</p>'
          '<p>00:02:13 – 00:18:55 – The Story of <em>Chopping Mall</em></p>'
          '<p>00:18:56 – 01:41:54 – Discussing <em>Chopping Mall</em></p>'
          '<ul><li>(00:00) - Welcome to the Show with Chad</li>'
          '<li>(02:13) - The Story of Chopping Mall</li>'
          '<li>(18:56) - Discussing Chopping Mall</li></ul>';
      final c = notesChapters(notes, 6114);
      expect(_titles(c), [
        'Welcome to the Show with Chad',
        'The Story of Chopping Mall',
        'Discussing Chopping Mall',
      ]);
      expect(_starts(c), [0, 133, 1136]);
    });

    test('a range list alone loses its end times', () {
      const notes = '<p>00:00:00 – 00:02:12 – Welcome</p>'
          '<p>00:02:13 – 00:18:55 – Story</p>'
          '<p>00:18:56 – End – Discussion</p>'
          '<p>01:40:00 – Ende der Welt</p>';
      expect(_titles(notesChapters(notes, 0)),
          ['Welcome', 'Story', 'Discussion', 'Ende der Welt']);
    });

    test('any marks around the time are skipped, brackets of the title kept', () {
      const notes = '▶ 0:00 → Intro<br>'
          '[05:30] :: (Teil 2) Interview<br>'
          '• 1:02:03 | „Zitat“ am Schluss';
      final c = notesChapters(notes, 0);
      expect(_titles(c), ['Intro', '(Teil 2) Interview', '„Zitat“ am Schluss']);
      expect(_starts(c), [0, 330, 3723]);
    });

    test('times of day are no chapters', () {
      const notes = '20:15 Uhr Live<br>21:00h Pause<br>22:30 pm Ende<br>'
          '23:00 — Uhr Ende';
      expect(notesChapters(notes, 0), isEmpty);
    });

    test('fewer than three is no chapter list', () {
      const notes = '00:00 Intro<br>10:00 Main';
      expect(notesChapters(notes, 0), isEmpty);
    });

    test('a stray time before the list leaves the list', () {
      const notes = 'Recorded at 45:00 – no, this line has text first.<br>'
          '45:00 - the stray one<br>'
          '00:00 Intro<br>05:00 Main<br>40:00 Outro';
      expect(_titles(notesChapters(notes, 3000)), ['Intro', 'Main', 'Outro']);
    });

    test('a list running past the episode is no chapter list', () {
      const notes = '00:00 A<br>10:00 B<br>59:00 C';
      expect(notesChapters(notes, 1800), isEmpty);
    });
  });
}
