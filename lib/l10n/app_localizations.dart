import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';

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
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

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
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('en')];

  /// The app title
  ///
  /// In en, this message translates to:
  /// **'Pottery Tracker'**
  String get appTitle;

  /// Home tab label
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get homeTab;

  /// Settings tab label
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTab;

  /// Add piece button label
  ///
  /// In en, this message translates to:
  /// **'Add Piece'**
  String get addPiece;

  /// Search bar placeholder
  ///
  /// In en, this message translates to:
  /// **'Search pieces...'**
  String get searchPieces;

  /// Active filter label
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get filterAll;

  /// Archive filter label
  ///
  /// In en, this message translates to:
  /// **'Archive'**
  String get filterArchived;

  /// Empty state title
  ///
  /// In en, this message translates to:
  /// **'No pieces yet'**
  String get emptyStateTitle;

  /// Empty state message
  ///
  /// In en, this message translates to:
  /// **'Tap + to take a photo and start tracking your first piece!'**
  String get emptyStateMessage;

  /// Default piece title
  ///
  /// In en, this message translates to:
  /// **'Untitled Piece'**
  String get untitledPiece;

  /// Greenware stage label
  ///
  /// In en, this message translates to:
  /// **'Greenware'**
  String get stageGreenware;

  /// Bisqued stage label
  ///
  /// In en, this message translates to:
  /// **'Bisqued'**
  String get stageBisqued;

  /// Glazed stage label
  ///
  /// In en, this message translates to:
  /// **'Glazed'**
  String get stageGlazed;

  /// No stage selected
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get stageNone;

  /// Title field label
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get titleLabel;

  /// Stage field label
  ///
  /// In en, this message translates to:
  /// **'Stage'**
  String get stageLabel;

  /// Clay type field label
  ///
  /// In en, this message translates to:
  /// **'Clay Type'**
  String get clayTypeLabel;

  /// Glazes field label
  ///
  /// In en, this message translates to:
  /// **'Glazes'**
  String get glazesLabel;

  /// Notes field label
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get notesLabel;

  /// Add photo button label
  ///
  /// In en, this message translates to:
  /// **'Add Photo'**
  String get addPhoto;

  /// Delete photo action
  ///
  /// In en, this message translates to:
  /// **'Delete Photo'**
  String get deletePhoto;

  /// Set cover photo action
  ///
  /// In en, this message translates to:
  /// **'Set as Cover'**
  String get setCoverPhoto;

  /// Delete piece action
  ///
  /// In en, this message translates to:
  /// **'Delete Piece'**
  String get deletePiece;

  /// Delete piece confirmation dialog title
  ///
  /// In en, this message translates to:
  /// **'Delete Piece?'**
  String get deletePieceConfirmTitle;

  /// Delete piece confirmation message
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete this piece? This cannot be undone.'**
  String get deletePieceConfirmMessage;

  /// Cancel action
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// Delete action
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// Camera option
  ///
  /// In en, this message translates to:
  /// **'Camera'**
  String get camera;

  /// Photo library option
  ///
  /// In en, this message translates to:
  /// **'Photo Library'**
  String get photoLibrary;

  /// Sign in screen title
  ///
  /// In en, this message translates to:
  /// **'Pottery Tracker'**
  String get signInTitle;

  /// Sign in screen subtitle
  ///
  /// In en, this message translates to:
  /// **'Track your ceramic creations'**
  String get signInSubtitle;

  /// Google sign in button
  ///
  /// In en, this message translates to:
  /// **'Sign in with Google'**
  String get signInWithGoogle;

  /// Apple sign in button
  ///
  /// In en, this message translates to:
  /// **'Sign in with Apple'**
  String get signInWithApple;

  /// Skip sign in button
  ///
  /// In en, this message translates to:
  /// **'Skip for now'**
  String get skipForNow;

  /// Settings screen title
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// Account section label
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get account;

  /// Signed in status
  ///
  /// In en, this message translates to:
  /// **'Signed in as {name}'**
  String signedInAs(String name);

  /// Not signed in status
  ///
  /// In en, this message translates to:
  /// **'Not signed in'**
  String get notSignedIn;

  /// Sign out button
  ///
  /// In en, this message translates to:
  /// **'Sign Out'**
  String get signOut;

  /// About section label
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get about;

  /// App version
  ///
  /// In en, this message translates to:
  /// **'Version {version}'**
  String version(String version);

  /// Sync status label
  ///
  /// In en, this message translates to:
  /// **'Sync Status'**
  String get syncStatus;

  /// Sync coming soon message
  ///
  /// In en, this message translates to:
  /// **'Cloud sync coming soon'**
  String get syncComingSoon;

  /// Storage section label
  ///
  /// In en, this message translates to:
  /// **'Storage'**
  String get storage;

  /// Support developer label
  ///
  /// In en, this message translates to:
  /// **'Support the Developer'**
  String get supportDeveloper;

  /// Photo counter
  ///
  /// In en, this message translates to:
  /// **'Photo {current} of {total}'**
  String photoOf(int current, int total);

  /// No photos message
  ///
  /// In en, this message translates to:
  /// **'No photos'**
  String get noPhotos;

  /// Delete photo confirmation title
  ///
  /// In en, this message translates to:
  /// **'Delete Photo?'**
  String get deletePhotoConfirmTitle;

  /// Delete photo confirmation message
  ///
  /// In en, this message translates to:
  /// **'This photo will be permanently deleted.'**
  String get deletePhotoConfirmMessage;

  /// Archive piece action
  ///
  /// In en, this message translates to:
  /// **'Archive'**
  String get archivePiece;

  /// Unarchive piece action
  ///
  /// In en, this message translates to:
  /// **'Unarchive'**
  String get unarchivePiece;

  /// Last updated timestamp
  ///
  /// In en, this message translates to:
  /// **'Last updated {date}'**
  String lastUpdated(String date);

  /// Edit date tooltip
  ///
  /// In en, this message translates to:
  /// **'Edit Date'**
  String get editDate;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
