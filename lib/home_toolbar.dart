// lib/home_toolbar.dart
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'feed_state.dart';
import 'l10n/app_localizations.dart';

/// The home screen's top bar: logo (or back arrow on a podcast page), filter,
/// search and add; while searching, the search field instead.
class HomeToolbar extends StatelessWidget {
  /// On a podcast page (subscribed or preview): back arrow instead of logo.
  final bool inPodcast;
  /// Searching podcasts to add rather than episodes (changes the hint).
  final bool discoverSearch;
  /// Searching episodes: the filter button sits next to the search field.
  final bool episodeSearch;
  final bool searchOpen;
  final TextEditingController searchCtrl;
  final FilterState filter;
  final bool filterChipsVisible;
  final AppLocalizations l10n;
  final ColorScheme cs;
  final VoidCallback onBack;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final VoidCallback onSearchOpen;
  final VoidCallback onPlusPressed;
  final VoidCallback onFilterToggle;
  final VoidCallback onLogoTap;
  final VoidCallback onInfoPressed;

  const HomeToolbar({
    super.key,
    required this.inPodcast, required this.discoverSearch,
    required this.episodeSearch, required this.searchOpen, required this.searchCtrl,
    required this.filter, required this.filterChipsVisible,
    required this.l10n, required this.cs,
    required this.onBack, required this.onSearchChanged, required this.onClearSearch,
    required this.onSearchOpen, required this.onPlusPressed,
    required this.onFilterToggle, required this.onLogoTap,
    required this.onInfoPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: cs.outlineVariant, width: 0.5))),
      child: searchOpen ? _searchRow() : _defaultRow(),
    );
  }

  Widget _searchRow() {
    return Row(
      children: [
        IconButton(icon: Icon(Icons.arrow_back_rounded, color: cs.primary), onPressed: onBack),
        Expanded(
          child: TextField(
            controller: searchCtrl, autofocus: true,
            onChanged: onSearchChanged,
            decoration: InputDecoration(
              hintText: discoverSearch
                  ? l10n.searchHint : l10n.toolbarSearchHint,
              border: InputBorder.none,
              hintStyle: TextStyle(color: cs.onSurfaceVariant),
            ),
          ),
        ),
        if (searchCtrl.text.isNotEmpty)
          IconButton(icon: Icon(Icons.clear_rounded, size: 20, color: cs.primary),
              onPressed: onClearSearch),
        if (episodeSearch) _filterButton(),
      ],
    );
  }

  /// Toggles the filter chips; a dot shows while any filter is on.
  Widget _filterButton() => Stack(
        clipBehavior: Clip.none,
        children: [
          // Open chips show as a tinted circle behind the icon.
          IconButton(
            icon: Icon(Icons.tune_rounded, color: cs.primary),
            style: IconButton.styleFrom(
                backgroundColor: filterChipsVisible
                    ? cs.primary.withValues(alpha: 0.12)
                    : Colors.transparent),
            onPressed: onFilterToggle,
            tooltip: l10n.tooltipFilter,
          ),
          if (filter.hasAny)
            Positioned(right: 8, top: 8, child: Container(
              width: 8, height: 8,
              decoration: BoxDecoration(color: cs.primary, shape: BoxShape.circle),
            )),
        ],
      );

  Widget _defaultRow() {
    return Row(
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: inPodcast
              ? IconButton(
                  key: const ValueKey('back'),
                  icon: Icon(Icons.arrow_back_rounded, color: cs.primary),
                  onPressed: onBack)
              : Row(
                  key: const ValueKey('brand'),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(width: 10),
                    GestureDetector(
                      onTap: onLogoTap,
                      child: ClipOval(child: SvgPicture.asset('antpodlogo.svg', width: 28, height: 28)),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: onLogoTap,
                      child: Text('AntPod', style: TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 20,
                        color: cs.onSurface, letterSpacing: -0.5)),
                    ),
                    // The glyph's circle fills 20/24 of the icon: size 22
                    // draws it ~18 px, 2/3 of the 28 px logo. The button's
                    // ripple circles the icon; the padding around it still
                    // takes taps, for a 65×56 tap area (the bar's height).
                    // Shifted left so the glyph sits 8 px from the wordmark,
                    // the same gap as between logo and wordmark.
                    Transform.translate(
                      offset: const Offset(-4, 0),
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: onInfoPressed,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(1, 8, 24, 8),
                          child: IconButton(
                            onPressed: onInfoPressed,
                            tooltip: l10n.tooltipGuide,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints.tightFor(width: 40, height: 40),
                            style: IconButton.styleFrom(
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                            icon: Icon(Icons.info_rounded, size: 22, color: cs.primary),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
        ),
        const Spacer(),
        _filterButton(),
        IconButton(
          icon: Icon(Icons.search_rounded, color: cs.primary),
          onPressed: onSearchOpen,
          tooltip: l10n.tooltipSearch),
        IconButton(
          icon: Icon(Icons.add_rounded, color: cs.primary),
          onPressed: onPlusPressed,
          tooltip: l10n.tooltipDiscover),
      ],
    );
  }
}
