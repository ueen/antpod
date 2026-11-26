// lib/trends_country.dart
//
// The country Apple's charts (the Discover page's trends) come from, and the
// sheet that picks it.
import 'package:flutter/material.dart';

import 'l10n/app_localizations.dart';

/// Apple Podcasts storefronts offered for the trends, by ISO code, each in
/// its own language (no translations to keep up).
const trendsCountries = {
  'ae': 'الإمارات', 'ar': 'Argentina', 'at': 'Österreich', 'au': 'Australia',
  'be': 'Belgique', 'bg': 'България', 'br': 'Brasil', 'ca': 'Canada',
  'ch': 'Schweiz', 'cl': 'Chile', 'cn': '中国', 'co': 'Colombia',
  'cz': 'Česko', 'de': 'Deutschland', 'dk': 'Danmark', 'ee': 'Eesti',
  'eg': 'مصر', 'es': 'España', 'fi': 'Suomi', 'fr': 'France',
  'gb': 'United Kingdom', 'gr': 'Ελλάδα', 'hk': '香港', 'hr': 'Hrvatska',
  'hu': 'Magyarország', 'id': 'Indonesia', 'ie': 'Ireland', 'il': 'ישראל',
  'in': 'India', 'is': 'Ísland', 'it': 'Italia', 'jp': '日本',
  'ke': 'Kenya', 'kr': '대한민국', 'lt': 'Lietuva', 'lu': 'Luxembourg',
  'lv': 'Latvija', 'mx': 'México', 'my': 'Malaysia', 'ng': 'Nigeria',
  'nl': 'Nederland', 'no': 'Norge', 'nz': 'New Zealand', 'pe': 'Perú',
  'ph': 'Philippines', 'pl': 'Polska', 'pt': 'Portugal', 'ro': 'România',
  'sa': 'السعودية', 'se': 'Sverige', 'sg': 'Singapore', 'si': 'Slovenija',
  'sk': 'Slovensko', 'th': 'ไทย', 'tr': 'Türkiye', 'tw': '台灣',
  'ua': 'Україна', 'us': 'United States', 'vn': 'Việt Nam',
  'za': 'South Africa',
};

/// The device's country/region, from its locale settings (the app's own
/// locale has the language only); without one, the country its language is
/// mostly spoken in. The trends default to it, and episode search uses it.
String deviceCountry([List<Locale>? locales]) {
  locales ??= WidgetsBinding.instance.platformDispatcher.locales;
  for (final locale in locales) {
    final country = locale.countryCode?.toLowerCase();
    if (country != null && country.length == 2) return country;
  }
  final language = locales.isEmpty ? null : locales.first.languageCode;
  return const {'en': 'us', 'de': 'de', 'fr': 'fr', 'es': 'es'}[language] ?? 'us';
}

/// The country's flag: its code in regional indicator letters.
String countryFlag(String code) => String.fromCharCodes(
    code.toUpperCase().codeUnits.map((c) => 0x1F1E6 + c - 0x41));

/// Sorts Latin names by their first letter's base (Österreich among the O's),
/// other scripts after them.
String _sortKey(String name) => const {'Ö': 'O', 'Í': 'I', 'Č': 'C'}[name[0]] ?? name[0];

/// Other names each country goes by, in the app's languages (English,
/// German, French, Spanish) where they differ from its own: the search finds
/// Deutschland by "Germany", "Allemagne" or "Alemania" too.
const _aliases = {
  'ae': 'United Arab Emirates UAE Vereinigte Arabische Emirate Émirats arabes unis Emiratos Árabes Unidos',
  'ar': 'Argentinien Argentine',
  'at': 'Austria Autriche',
  'au': 'Australien Australie',
  'be': 'Belgium Belgien Bélgica België',
  'bg': 'Bulgaria Bulgarien Bulgarie',
  'br': 'Brazil Brasilien Brésil',
  'ca': 'Kanada Canadá',
  'ch': 'Switzerland Suisse Suiza Svizzera',
  'cl': 'Chili',
  'cn': 'China Chine',
  'co': 'Kolumbien Colombie',
  'cz': 'Czechia Czech Republic Tschechien Tchéquie Chequia',
  'de': 'Germany Allemagne Alemania',
  'dk': 'Denmark Dänemark Danemark Dinamarca',
  'ee': 'Estonia Estland Estonie',
  'eg': 'Egypt Ägypten Égypte Egipto',
  'es': 'Spain Spanien Espagne',
  'fi': 'Finland Finnland Finlande Finlandia',
  'fr': 'Frankreich Francia',
  'gb': 'Great Britain UK England Großbritannien Vereinigtes Königreich Royaume-Uni Reino Unido',
  'gr': 'Greece Griechenland Grèce Grecia',
  'hk': 'Hong Kong Hongkong',
  'hr': 'Croatia Kroatien Croatie Croacia',
  'hu': 'Hungary Ungarn Hongrie Hungría',
  'id': 'Indonesien Indonésie',
  'ie': 'Irland Irlande Irlanda',
  'il': 'Israel Israël',
  'in': 'Indien Inde',
  'is': 'Iceland Island Islande Islandia',
  'it': 'Italy Italien Italie',
  'jp': 'Japan Japon Japón',
  'ke': 'Kenia',
  'kr': 'South Korea Südkorea Corée du Sud Corea del Sur',
  'lt': 'Lithuania Litauen Lituanie Lituania',
  'lu': 'Luxemburg Luxemburgo',
  'lv': 'Latvia Lettland Lettonie Letonia',
  'mx': 'Mexico Mexiko Mexique',
  'my': 'Malaysie Malasia',
  'ng': 'Nigéria',
  'nl': 'Netherlands Holland Niederlande Pays-Bas Países Bajos',
  'no': 'Norway Norwegen Norvège Noruega',
  'nz': 'Neuseeland Nouvelle-Zélande Nueva Zelanda',
  'pe': 'Peru Pérou',
  'ph': 'Philippinen Filipinas',
  'pl': 'Poland Polen Pologne Polonia',
  'ro': 'Romania Rumänien Roumanie Rumania',
  'sa': 'Saudi Arabia Saudi-Arabien Arabie saoudite Arabia Saudita',
  'se': 'Sweden Schweden Suède Suecia',
  'sg': 'Singapur Singapour',
  'si': 'Slovenia Slowenien Slovénie Eslovenia',
  'sk': 'Slovakia Slowakei Slovaquie Eslovaquia',
  'th': 'Thailand Thaïlande Tailandia',
  'tr': 'Turkey Türkei Turquie Turquía',
  'tw': 'Taiwan Taïwan Taiwán',
  'ua': 'Ukraine Ucrania',
  'us': 'USA America Vereinigte Staaten États-Unis Estados Unidos',
  'vn': 'Vietnam',
  'za': 'Südafrika Afrique du Sud Sudáfrica',
};

const _plain = {
  'á': 'a', 'à': 'a', 'â': 'a', 'ä': 'a', 'ã': 'a', 'å': 'a', 'ă': 'a', 'ā': 'a', 'ą': 'a',
  'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e', 'ė': 'e', 'ē': 'e', 'ę': 'e',
  'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i', 'ī': 'i', 'ı': 'i',
  'ó': 'o', 'ò': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o', 'ø': 'o', 'ő': 'o',
  'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u', 'ū': 'u', 'ű': 'u',
  'ñ': 'n', 'ņ': 'n', 'ç': 'c', 'č': 'c', 'š': 's', 'ș': 's', 'ş': 's',
  'ž': 'z', 'ý': 'y', 'ł': 'l', 'ļ': 'l', 'ķ': 'k', 'ģ': 'g', 'ğ': 'g',
  'ț': 't', 'ţ': 't', 'ß': 'ss', '-': ' ', '.': '',
};

/// Lowercase, without accents, hyphens as spaces: "Österreich" → "osterreich".
String _fold(String s) =>
    s.toLowerCase().split('').map((c) => _plain[c] ?? c).join();

/// Whether [query] starts a word of the country's own name or of one of its
/// other names, or is its code. Accents and case don't matter.
bool trendsCountryMatches(String code, String query) {
  final q = _fold(query.trim());
  if (q.isEmpty || q == code) return true;
  return ' ${_fold('${trendsCountries[code] ?? ''} ${_aliases[code] ?? ''}')}'
      .contains(' $q');
}

/// The sheet: a search field, then the current country first and the rest
/// by name. Returns the picked code, null when dismissed.
Future<String?> showTrendsCountrySheet(BuildContext context, String current) =>
    showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
      builder: (_) => _CountrySheet(current: current),
    );

class _CountrySheet extends StatefulWidget {
  const _CountrySheet({required this.current});

  final String current;

  @override
  State<_CountrySheet> createState() => _CountrySheetState();
}

class _CountrySheetState extends State<_CountrySheet> {
  final _sheetCtrl = DraggableScrollableController();
  final _queryCtrl = TextEditingController();
  final _focus = FocusNode();
  late final List<String> _codes;

  @override
  void initState() {
    super.initState();
    final others = trendsCountries.keys.where((c) => c != widget.current).toList()
      ..sort((a, b) {
        final na = trendsCountries[a]!, nb = trendsCountries[b]!;
        final byKey = _sortKey(na).compareTo(_sortKey(nb));
        return byKey != 0 ? byKey : na.compareTo(nb);
      });
    _codes = [widget.current, ...others];
    // Searching opens the sheet all the way: the matches stay in view above
    // the keyboard.
    _focus.addListener(() {
      if (_focus.hasFocus && _sheetCtrl.isAttached && _sheetCtrl.size < 1) {
        _sheetCtrl.animateTo(1,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOutCubic);
      }
    });
  }

  @override
  void dispose() {
    _sheetCtrl.dispose();
    _queryCtrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final matches =
        _codes.where((c) => trendsCountryMatches(c, _queryCtrl.text)).toList();

    final header = ColoredBox(
      // The sheet's own color: the list scrolls under it.
      color: cs.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 4),
              width: 32, height: 4,
              decoration: BoxDecoration(
                color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
            child: Text(l10n.trendsCountry,
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              key: const ValueKey('country-search'),
              controller: _queryCtrl,
              focusNode: _focus,
              textInputAction: TextInputAction.search,
              onChanged: (_) => setState(() {}),
              // Enter takes the first match.
              onSubmitted: (q) {
                final first = _codes.where((c) => trendsCountryMatches(c, q)).firstOrNull;
                if (first != null) Navigator.pop(context, first);
              },
              decoration: InputDecoration(
                hintText: l10n.trendsCountrySearch,
                hintStyle: TextStyle(color: cs.onSurfaceVariant),
                prefixIcon: Icon(Icons.search_rounded, color: cs.primary),
                suffixIcon: _queryCtrl.text.isEmpty
                    ? null
                    : IconButton(
                        icon: Icon(Icons.clear_rounded, size: 20, color: cs.primary),
                        onPressed: () => setState(_queryCtrl.clear),
                      ),
                filled: true,
                fillColor: cs.surfaceContainerHighest,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(28),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
        ],
      ),
    );

    return DraggableScrollableSheet(
      controller: _sheetCtrl,
      expand: false,
      initialChildSize: 0.6,
      minChildSize: 0.3,
      snap: true,
      snapSizes: const [0.6],
      builder: (ctx, controller) => CustomScrollView(
        controller: controller,
        slivers: [
          // In the scroll view, so dragging it moves the sheet too; pinned,
          // so the search stays at hand.
          PinnedHeaderSliver(child: header),
          if (matches.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Center(
                  child: Text(l10n.searchNoResults,
                      style: TextStyle(color: cs.onSurfaceVariant)),
                ),
              ),
            ),
          SliverPadding(
            padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(context).bottom +
                    MediaQuery.paddingOf(context).bottom + 16),
            sliver: SliverList.builder(
              itemCount: matches.length,
              itemBuilder: (_, i) => _tile(cs, matches[i]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tile(ColorScheme cs, String code) {
    final current = code == widget.current;
    return ListTile(
      key: ValueKey('country-$code'),
      contentPadding: const EdgeInsets.symmetric(horizontal: 24),
      leading: Text(countryFlag(code), style: const TextStyle(fontSize: 22)),
      title: Text(trendsCountries[code] ?? code.toUpperCase(),
          style: TextStyle(
              fontWeight: current ? FontWeight.w700 : FontWeight.w500,
              color: current ? cs.primary : null)),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(code.toUpperCase(),
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                color: cs.onSurfaceVariant)),
        const SizedBox(width: 12),
        // Same width either way: the codes stay in one column.
        Icon(Icons.check_rounded, size: 20,
            color: current ? cs.primary : Colors.transparent),
      ]),
      onTap: () => Navigator.pop(context, code),
    );
  }
}
