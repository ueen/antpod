import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_de.dart';
import 'app_localizations_en.dart';
import 'app_localizations_es.dart';
import 'app_localizations_fr.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale) : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate = _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates = <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('de'),
    Locale('en'),
    Locale('es'),
    Locale('fr')
  ];

  /// No description provided for @toolbarSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search episodes…'**
  String get toolbarSearchHint;

  /// No description provided for @searchHint.
  ///
  /// In en, this message translates to:
  /// **'Search podcasts…'**
  String get searchHint;

  /// No description provided for @searchNoResults.
  ///
  /// In en, this message translates to:
  /// **'No results found.'**
  String get searchNoResults;

  /// No description provided for @sectionTrending.
  ///
  /// In en, this message translates to:
  /// **'Trending this month'**
  String get sectionTrending;

  /// No description provided for @sectionRecommended.
  ///
  /// In en, this message translates to:
  /// **'Recommended for you'**
  String get sectionRecommended;

  /// No description provided for @sectionRecommendedSub.
  ///
  /// In en, this message translates to:
  /// **'based on your subscriptions'**
  String get sectionRecommendedSub;

  /// No description provided for @sectionSearchResults.
  ///
  /// In en, this message translates to:
  /// **'Search results'**
  String get sectionSearchResults;

  /// No description provided for @emptyFeedTitle.
  ///
  /// In en, this message translates to:
  /// **'No podcasts yet'**
  String get emptyFeedTitle;

  /// No description provided for @emptyFeedSub.
  ///
  /// In en, this message translates to:
  /// **'Tap + to search and subscribe'**
  String get emptyFeedSub;

  /// No description provided for @emptySearchTitle.
  ///
  /// In en, this message translates to:
  /// **'No results'**
  String get emptySearchTitle;

  /// No description provided for @emptyPodcastsTitle.
  ///
  /// In en, this message translates to:
  /// **'No subscriptions yet'**
  String get emptyPodcastsTitle;

  /// No description provided for @subscribeDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Subscribe'**
  String get subscribeDialogTitle;

  /// No description provided for @subscribed.
  ///
  /// In en, this message translates to:
  /// **'Subscribed to \"{title}\"'**
  String subscribed(String title);

  /// No description provided for @downloaded.
  ///
  /// In en, this message translates to:
  /// **'Downloaded'**
  String get downloaded;

  /// No description provided for @downloading.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get downloading;

  /// No description provided for @deleteDownload.
  ///
  /// In en, this message translates to:
  /// **'Delete download'**
  String get deleteDownload;

  /// No description provided for @shownotes.
  ///
  /// In en, this message translates to:
  /// **'Show notes'**
  String get shownotes;

  /// No description provided for @filterNew.
  ///
  /// In en, this message translates to:
  /// **'New'**
  String get filterNew;

  /// No description provided for @filterListened.
  ///
  /// In en, this message translates to:
  /// **'Listened'**
  String get filterListened;

  /// No description provided for @filterPodcasts.
  ///
  /// In en, this message translates to:
  /// **'Podcasts'**
  String get filterPodcasts;

  /// No description provided for @filterDownloaded.
  ///
  /// In en, this message translates to:
  /// **'Downloaded'**
  String get filterDownloaded;

  /// No description provided for @filterAlphabetical.
  ///
  /// In en, this message translates to:
  /// **'A–Z'**
  String get filterAlphabetical;

  /// No description provided for @filterOldest.
  ///
  /// In en, this message translates to:
  /// **'Oldest first'**
  String get filterOldest;

  /// No description provided for @filterPlaying.
  ///
  /// In en, this message translates to:
  /// **'Playing'**
  String get filterPlaying;

  /// No description provided for @addRssFeed.
  ///
  /// In en, this message translates to:
  /// **'Add RSS feed'**
  String get addRssFeed;

  /// No description provided for @openFeed.
  ///
  /// In en, this message translates to:
  /// **'Open feed'**
  String get openFeed;

  /// No description provided for @addByRssUrl.
  ///
  /// In en, this message translates to:
  /// **'Add by RSS feed URL'**
  String get addByRssUrl;

  /// No description provided for @subscribeToRss.
  ///
  /// In en, this message translates to:
  /// **'Subscribe to RSS feed'**
  String get subscribeToRss;

  /// No description provided for @searchOnline.
  ///
  /// In en, this message translates to:
  /// **'Search online'**
  String get searchOnline;

  /// No description provided for @discoverTabTrending.
  ///
  /// In en, this message translates to:
  /// **'Trending'**
  String get discoverTabTrending;

  /// No description provided for @discoverTabSuggestions.
  ///
  /// In en, this message translates to:
  /// **'Suggestions'**
  String get discoverTabSuggestions;

  /// No description provided for @aboutAntpod.
  ///
  /// In en, this message translates to:
  /// **'About AntPod'**
  String get aboutAntpod;

  /// No description provided for @subscriptions.
  ///
  /// In en, this message translates to:
  /// **'Subscriptions'**
  String get subscriptions;

  /// No description provided for @markUnplayed.
  ///
  /// In en, this message translates to:
  /// **'Mark as unplayed'**
  String get markUnplayed;

  /// No description provided for @markPlayed.
  ///
  /// In en, this message translates to:
  /// **'Mark as played'**
  String get markPlayed;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @shareEpisode.
  ///
  /// In en, this message translates to:
  /// **'Share episode'**
  String get shareEpisode;

  /// No description provided for @sharePodcast.
  ///
  /// In en, this message translates to:
  /// **'Share podcast'**
  String get sharePodcast;

  /// No description provided for @unsubscribe.
  ///
  /// In en, this message translates to:
  /// **'Unsubscribe'**
  String get unsubscribe;

  /// No description provided for @filterRandom.
  ///
  /// In en, this message translates to:
  /// **'Random'**
  String get filterRandom;

  /// No description provided for @removeEpisode.
  ///
  /// In en, this message translates to:
  /// **'Remove episode'**
  String get removeEpisode;

  /// No description provided for @exportFile.
  ///
  /// In en, this message translates to:
  /// **'Export file'**
  String get exportFile;

  /// No description provided for @showAllDownloads.
  ///
  /// In en, this message translates to:
  /// **'Show all downloads'**
  String get showAllDownloads;

  String get downloadNow;
  String get saveForWifi;
  String get cancelWifiQueue;
  String get showMarkedForDownload;
  String get noWifi;
  String get onMobileData;
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>['de', 'en', 'es', 'fr'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {


  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'de': return AppLocalizationsDe();
    case 'en': return AppLocalizationsEn();
    case 'es': return AppLocalizationsEs();
    case 'fr': return AppLocalizationsFr();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.'
  );
}
