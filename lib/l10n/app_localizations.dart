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

  /// No description provided for @emptyFavoritesTitle.
  ///
  /// In en, this message translates to:
  /// **'No favourites yet'**
  String get emptyFavoritesTitle;

  /// No description provided for @emptyFavoritesSub.
  ///
  /// In en, this message translates to:
  /// **'Long-press an episode, or tap the heart in the player'**
  String get emptyFavoritesSub;

  /// No description provided for @emptyPodcastsTitle.
  ///
  /// In en, this message translates to:
  /// **'No subscriptions yet'**
  String get emptyPodcastsTitle;

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

  /// No description provided for @filterFavorites.
  ///
  /// In en, this message translates to:
  /// **'Favourites'**
  String get filterFavorites;

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
  /// **'Add by RSS URL'**
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

  /// No description provided for @aboutAntpod.
  ///
  /// In en, this message translates to:
  /// **'About AntPod'**
  String get aboutAntpod;

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

  /// No description provided for @addFavorite.
  ///
  /// In en, this message translates to:
  /// **'Add to favourites'**
  String get addFavorite;

  /// No description provided for @removeFavorite.
  ///
  /// In en, this message translates to:
  /// **'Remove from favourites'**
  String get removeFavorite;

  /// No description provided for @sharePodcast.
  ///
  /// In en, this message translates to:
  /// **'Share podcast'**
  String get sharePodcast;

  /// No description provided for @subscribe.
  ///
  /// In en, this message translates to:
  /// **'Subscribe'**
  String get subscribe;

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

  /// No description provided for @downloadNow.
  ///
  /// In en, this message translates to:
  /// **'Download now'**
  String get downloadNow;

  /// No description provided for @saveForWifi.
  ///
  /// In en, this message translates to:
  /// **'Save for WiFi'**
  String get saveForWifi;

  /// No description provided for @cancelWifiQueue.
  ///
  /// In en, this message translates to:
  /// **'Cancel WiFi queue'**
  String get cancelWifiQueue;

  /// No description provided for @showMarkedForDownload.
  ///
  /// In en, this message translates to:
  /// **'Show marked for download'**
  String get showMarkedForDownload;

  /// No description provided for @noWifi.
  ///
  /// In en, this message translates to:
  /// **'No WiFi'**
  String get noWifi;

  /// No description provided for @onMobileData.
  ///
  /// In en, this message translates to:
  /// **'You\'re on mobile data'**
  String get onMobileData;

  /// No description provided for @noConnection.
  ///
  /// In en, this message translates to:
  /// **'No connection'**
  String get noConnection;

  /// No description provided for @offlineSub.
  ///
  /// In en, this message translates to:
  /// **'You\'re offline'**
  String get offlineSub;

  /// No description provided for @unsubscribeConfirm.
  ///
  /// In en, this message translates to:
  /// **'Sure you want to unsubscribe?'**
  String get unsubscribeConfirm;

  /// No description provided for @foundDownloaded.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 downloaded episode found} other{{count} downloaded episodes found}}'**
  String foundDownloaded(int count);

  /// No description provided for @foundStarted.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 started episode found} other{{count} started episodes found}}'**
  String foundStarted(int count);

  /// No description provided for @foundStartedAndDownloaded.
  ///
  /// In en, this message translates to:
  /// **'Started and downloaded episodes found'**
  String get foundStartedAndDownloaded;

  /// No description provided for @favoritesKept.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 favourite stays either way} other{{count} favourites stay either way}}'**
  String favoritesKept(int count);

  /// No description provided for @unsubscribeDeleteAll.
  ///
  /// In en, this message translates to:
  /// **'Unsubscribe & delete'**
  String get unsubscribeDeleteAll;

  /// No description provided for @unsubscribeFinishEpisodes.
  ///
  /// In en, this message translates to:
  /// **'Finish episodes'**
  String get unsubscribeFinishEpisodes;

  /// No description provided for @stopNewEpisodes.
  ///
  /// In en, this message translates to:
  /// **'Don\'t load new episodes'**
  String get stopNewEpisodes;

  /// No description provided for @newEpisodesStopped.
  ///
  /// In en, this message translates to:
  /// **'Not loading new episodes'**
  String get newEpisodesStopped;

  /// No description provided for @finishingEpisodes.
  ///
  /// In en, this message translates to:
  /// **'Finishing episodes'**
  String get finishingEpisodes;

  /// No description provided for @feedNotLoading.
  ///
  /// In en, this message translates to:
  /// **'Feed hasn\'t loaded lately'**
  String get feedNotLoading;

  /// No description provided for @downloadingEpisodes.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Downloading 1 episode} other{Downloading {count} episodes}}'**
  String downloadingEpisodes(int count);

  /// No description provided for @downloadNotificationChannel.
  ///
  /// In en, this message translates to:
  /// **'Downloads'**
  String get downloadNotificationChannel;

  /// No description provided for @aboutText.
  ///
  /// In en, this message translates to:
  /// **'The anthill for your podcasts — every episode carried home to the hill tirelessly. A nimble scout hatched from the spirit of the grand old AntennaPod.'**
  String get aboutText;

  /// No description provided for @tooltipFilter.
  ///
  /// In en, this message translates to:
  /// **'Filter'**
  String get tooltipFilter;

  /// No description provided for @tooltipSearch.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get tooltipSearch;

  /// No description provided for @tooltipDiscover.
  ///
  /// In en, this message translates to:
  /// **'Discover'**
  String get tooltipDiscover;

  /// No description provided for @tooltipGuide.
  ///
  /// In en, this message translates to:
  /// **'Guide'**
  String get tooltipGuide;

  /// No description provided for @trendingError.
  ///
  /// In en, this message translates to:
  /// **'Could not load trending podcasts'**
  String get trendingError;

  /// No description provided for @trendingEmpty.
  ///
  /// In en, this message translates to:
  /// **'No trending podcasts available.'**
  String get trendingEmpty;

  /// No description provided for @trendsCountry.
  ///
  /// In en, this message translates to:
  /// **'Trends country'**
  String get trendsCountry;

  /// No description provided for @trendsCountrySearch.
  ///
  /// In en, this message translates to:
  /// **'Search countries…'**
  String get trendsCountrySearch;

  /// No description provided for @settingsPrivacy.
  ///
  /// In en, this message translates to:
  /// **'Privacy'**
  String get settingsPrivacy;

  /// No description provided for @settingsAppleApiSub.
  ///
  /// In en, this message translates to:
  /// **'Trends and episode search use Apple. When off, search finds podcasts through PodcastIndex only'**
  String get settingsAppleApiSub;

  /// No description provided for @trendsAppleOff.
  ///
  /// In en, this message translates to:
  /// **'Apple Podcasts is off'**
  String get trendsAppleOff;

  /// No description provided for @trendsAppleOffSub.
  ///
  /// In en, this message translates to:
  /// **'The trends come from Apple Podcasts. Meanwhile, search finds podcasts through PodcastIndex only.'**
  String get trendsAppleOffSub;

  /// No description provided for @trendsAppleOn.
  ///
  /// In en, this message translates to:
  /// **'Turn on'**
  String get trendsAppleOn;

  /// No description provided for @playbackError.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t play this episode'**
  String get playbackError;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @settingsAppearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get settingsAppearance;

  /// No description provided for @settingsMaterialYou.
  ///
  /// In en, this message translates to:
  /// **'Material You'**
  String get settingsMaterialYou;

  /// No description provided for @settingsMaterialYouSub.
  ///
  /// In en, this message translates to:
  /// **'Colours from your wallpaper'**
  String get settingsMaterialYouSub;

  /// No description provided for @settingsTheme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get settingsTheme;

  /// No description provided for @settingsThemeSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get settingsThemeSystem;

  /// No description provided for @settingsThemeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get settingsThemeLight;

  /// No description provided for @settingsThemeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get settingsThemeDark;

  /// No description provided for @settingsPlayback.
  ///
  /// In en, this message translates to:
  /// **'Playback'**
  String get settingsPlayback;

  /// No description provided for @settingsRewindOnResume.
  ///
  /// In en, this message translates to:
  /// **'Rewind on resume'**
  String get settingsRewindOnResume;

  /// No description provided for @settingsRewindOnResumeSub.
  ///
  /// In en, this message translates to:
  /// **'Back 3 seconds after a pause of 5 minutes or more'**
  String get settingsRewindOnResumeSub;

  /// No description provided for @settingsMarkPlayedNearEnd.
  ///
  /// In en, this message translates to:
  /// **'Played near the end'**
  String get settingsMarkPlayedNearEnd;

  /// No description provided for @settingsMarkPlayedNearEndSub.
  ///
  /// In en, this message translates to:
  /// **'Pausing in the last 100 seconds marks the episode as played'**
  String get settingsMarkPlayedNearEndSub;

  /// No description provided for @settingsDownloads.
  ///
  /// In en, this message translates to:
  /// **'Downloads'**
  String get settingsDownloads;

  /// No description provided for @settingsDeletePlayed.
  ///
  /// In en, this message translates to:
  /// **'Delete played downloads'**
  String get settingsDeletePlayed;

  /// No description provided for @settingsDeletePlayedSub.
  ///
  /// In en, this message translates to:
  /// **'Two days after an episode is played; favourites are kept'**
  String get settingsDeletePlayedSub;

  /// No description provided for @settingsDownloadsFolder.
  ///
  /// In en, this message translates to:
  /// **'Downloads folder'**
  String get settingsDownloadsFolder;

  /// No description provided for @settingsDownloadsFolderSub.
  ///
  /// In en, this message translates to:
  /// **'The downloaded episodes in the Files app, under AntPod'**
  String get settingsDownloadsFolderSub;

  /// No description provided for @settingsDownloadsFolderFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open the Files app'**
  String get settingsDownloadsFolderFailed;

  /// No description provided for @settingsImportExport.
  ///
  /// In en, this message translates to:
  /// **'Import & export'**
  String get settingsImportExport;

  /// No description provided for @exportBackup.
  ///
  /// In en, this message translates to:
  /// **'Export backup'**
  String get exportBackup;

  /// No description provided for @exportBackupSub.
  ///
  /// In en, this message translates to:
  /// **'Subscriptions, play state, favourites and settings'**
  String get exportBackupSub;

  /// No description provided for @importBackup.
  ///
  /// In en, this message translates to:
  /// **'Import backup'**
  String get importBackup;

  /// No description provided for @importBackupSub.
  ///
  /// In en, this message translates to:
  /// **'Adds to what\'s here; the newer play state is kept'**
  String get importBackupSub;

  /// No description provided for @exportOpml.
  ///
  /// In en, this message translates to:
  /// **'Export subscriptions (OPML)'**
  String get exportOpml;

  /// No description provided for @exportOpmlSub.
  ///
  /// In en, this message translates to:
  /// **'For other podcast apps'**
  String get exportOpmlSub;

  /// No description provided for @importOpml.
  ///
  /// In en, this message translates to:
  /// **'Import subscriptions (OPML)'**
  String get importOpml;

  /// No description provided for @importOpmlSub.
  ///
  /// In en, this message translates to:
  /// **'From another podcast app'**
  String get importOpmlSub;

  /// No description provided for @importProgress.
  ///
  /// In en, this message translates to:
  /// **'Loading feeds: {done} of {total}'**
  String importProgress(int done, int total);

  /// No description provided for @importSubscribed.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No new podcasts} =1{1 podcast added} other{{count} podcasts added}}'**
  String importSubscribed(int count);

  /// No description provided for @importEpisodes.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 episode updated} other{{count} episodes updated}}'**
  String importEpisodes(int count);

  /// No description provided for @importFailed.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 feed didn\'t load, it will on the next refresh} other{{count} feeds didn\'t load, they will on the next refresh}}'**
  String importFailed(int count);

  /// No description provided for @importNotBackup.
  ///
  /// In en, this message translates to:
  /// **'This file isn\'t an AntPod backup'**
  String get importNotBackup;

  /// No description provided for @importNewerBackup.
  ///
  /// In en, this message translates to:
  /// **'This backup is from a newer AntPod, update the app first'**
  String get importNewerBackup;

  /// No description provided for @importNotOpml.
  ///
  /// In en, this message translates to:
  /// **'This file isn\'t an OPML file'**
  String get importNotOpml;

  /// No description provided for @importUnreadable.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t read this file'**
  String get importUnreadable;

  /// No description provided for @exportSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get exportSaved;

  /// No description provided for @exportFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save the file'**
  String get exportFailed;
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
