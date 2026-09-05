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
  /// **'Potter Journal'**
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
  /// **'Search anything...'**
  String get searchPieces;

  /// Search bar placeholder for active pieces
  ///
  /// In en, this message translates to:
  /// **'Search Active...'**
  String get searchActive;

  /// Search bar placeholder for archived pieces
  ///
  /// In en, this message translates to:
  /// **'Search Archive...'**
  String get searchArchive;

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

  /// Clay field label
  ///
  /// In en, this message translates to:
  /// **'Clay'**
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
  /// **'Potter Journal'**
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

  /// Shown when user cancels sign-in
  ///
  /// In en, this message translates to:
  /// **'Sign-in cancelled'**
  String get signInCancelled;

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

  /// Batch photo processing progress
  ///
  /// In en, this message translates to:
  /// **'Processing {current} of {total}...'**
  String processingPhotos(int current, int total);

  /// Batch photo failure count
  ///
  /// In en, this message translates to:
  /// **'{count} photo(s) could not be added'**
  String batchPhotoFailures(int count);

  /// Reorder photos button
  ///
  /// In en, this message translates to:
  /// **'Reorder photos'**
  String get reorderPhotos;

  /// Add new option to dropdown
  ///
  /// In en, this message translates to:
  /// **'Add New'**
  String get addNew;

  /// Create action button
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get create;

  /// Clay name input hint
  ///
  /// In en, this message translates to:
  /// **'Enter clay name'**
  String get enterClayName;

  /// Manage clays settings option
  ///
  /// In en, this message translates to:
  /// **'Manage Clays'**
  String get manageClays;

  /// Materials section header in settings
  ///
  /// In en, this message translates to:
  /// **'Materials'**
  String get manageMaterials;

  /// Empty state for clay management
  ///
  /// In en, this message translates to:
  /// **'No clays saved yet'**
  String get noClaysYet;

  /// Edit clay name dialog title
  ///
  /// In en, this message translates to:
  /// **'Edit clay name'**
  String get editClayName;

  /// Save action button
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// Delete clay confirmation title
  ///
  /// In en, this message translates to:
  /// **'Delete Clay?'**
  String get deleteClayConfirmTitle;

  /// Delete clay confirmation message
  ///
  /// In en, this message translates to:
  /// **'Pieces using this clay will keep their current value, but it will no longer appear in the dropdown.'**
  String get deleteClayConfirmMessage;

  /// Manage glazes settings option
  ///
  /// In en, this message translates to:
  /// **'Manage Glazes'**
  String get manageGlazes;

  /// Empty state for glaze management
  ///
  /// In en, this message translates to:
  /// **'No glazes saved yet'**
  String get noGlazesYet;

  /// Glaze name input hint
  ///
  /// In en, this message translates to:
  /// **'Enter glaze name'**
  String get enterGlazeName;

  /// Edit glaze name dialog title
  ///
  /// In en, this message translates to:
  /// **'Edit glaze name'**
  String get editGlazeName;

  /// Delete glaze confirmation title
  ///
  /// In en, this message translates to:
  /// **'Delete Glaze?'**
  String get deleteGlazeConfirmTitle;

  /// Delete glaze confirmation message
  ///
  /// In en, this message translates to:
  /// **'This glaze will be removed from all pieces that use it.'**
  String get deleteGlazeConfirmMessage;

  /// Glaze multi-select picker title
  ///
  /// In en, this message translates to:
  /// **'Select Glazes'**
  String get selectGlazes;

  /// No glazes selected
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get glazesNone;

  /// Done action button
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// Tags field label
  ///
  /// In en, this message translates to:
  /// **'Tags'**
  String get tagsLabel;

  /// Manage tags settings option
  ///
  /// In en, this message translates to:
  /// **'Manage Tags'**
  String get manageTags;

  /// Empty state for tag management
  ///
  /// In en, this message translates to:
  /// **'No tags saved yet'**
  String get noTagsYet;

  /// Tag name input hint
  ///
  /// In en, this message translates to:
  /// **'Enter tag name'**
  String get enterTagName;

  /// Edit tag name dialog title
  ///
  /// In en, this message translates to:
  /// **'Edit tag name'**
  String get editTagName;

  /// Delete tag confirmation title
  ///
  /// In en, this message translates to:
  /// **'Delete Tag?'**
  String get deleteTagConfirmTitle;

  /// Delete tag confirmation message
  ///
  /// In en, this message translates to:
  /// **'This tag will be removed from all pieces that use it.'**
  String get deleteTagConfirmMessage;

  /// Tag multi-select picker title
  ///
  /// In en, this message translates to:
  /// **'Select Tags'**
  String get selectTags;

  /// No tags selected
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get tagsNone;

  /// Subtitle for manage clays screen
  ///
  /// In en, this message translates to:
  /// **'Recently used clays appear first'**
  String get manageClaysSubtitle;

  /// Subtitle for manage glazes screen
  ///
  /// In en, this message translates to:
  /// **'Recently used glazes appear first'**
  String get manageGlazesSubtitle;

  /// Subtitle for manage tags screen
  ///
  /// In en, this message translates to:
  /// **'Recently used tags appear first'**
  String get manageTagsSubtitle;

  /// Clay search field placeholder
  ///
  /// In en, this message translates to:
  /// **'Search clays...'**
  String get searchClays;

  /// Glaze search field placeholder
  ///
  /// In en, this message translates to:
  /// **'Search glazes...'**
  String get searchGlazes;

  /// Tag search field placeholder
  ///
  /// In en, this message translates to:
  /// **'Search tags...'**
  String get searchTags;

  /// Clay picker title
  ///
  /// In en, this message translates to:
  /// **'Select Clay'**
  String get selectClay;

  /// Recent section label for pills
  ///
  /// In en, this message translates to:
  /// **'Recent'**
  String get recent;

  /// Add new option with pre-filled name
  ///
  /// In en, this message translates to:
  /// **'Add \"{name}\"'**
  String addNewWithName(String name);

  /// Tag color picker title
  ///
  /// In en, this message translates to:
  /// **'Tag Color'**
  String get tagColor;

  /// Snackbar message when a piece is archived
  ///
  /// In en, this message translates to:
  /// **'{title} archived'**
  String pieceArchivedWithTitle(String title);

  /// Snackbar message when a piece is unarchived
  ///
  /// In en, this message translates to:
  /// **'{title} unarchived'**
  String pieceUnarchivedWithTitle(String title);

  /// Undo action label
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get undo;

  /// Send feedback email option in settings
  ///
  /// In en, this message translates to:
  /// **'Send Feedback'**
  String get sendFeedback;

  /// Connected accounts section header
  ///
  /// In en, this message translates to:
  /// **'Connected Accounts'**
  String get connectedAccounts;

  /// Google provider name
  ///
  /// In en, this message translates to:
  /// **'Google'**
  String get google;

  /// Apple provider name
  ///
  /// In en, this message translates to:
  /// **'Apple'**
  String get apple;

  /// Connect provider button
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get connect;

  /// Provider is connected label
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get connected;

  /// Google link success snackbar
  ///
  /// In en, this message translates to:
  /// **'Google account connected'**
  String get googleLinkedSuccess;

  /// Apple link success snackbar
  ///
  /// In en, this message translates to:
  /// **'Apple account connected'**
  String get appleLinkedSuccess;

  /// Account already linked error
  ///
  /// In en, this message translates to:
  /// **'This account is already linked to a different user'**
  String get accountAlreadyLinked;

  /// Subtitle when not signed in
  ///
  /// In en, this message translates to:
  /// **'Sign in to enable cloud sync'**
  String get signInToEnableSync;

  /// Coming soon placeholder
  ///
  /// In en, this message translates to:
  /// **'Coming soon'**
  String get comingSoon;

  /// Provider linked status label
  ///
  /// In en, this message translates to:
  /// **'LINKED'**
  String get linked;

  /// Provider not linked status label
  ///
  /// In en, this message translates to:
  /// **'NOT LINKED'**
  String get notLinked;

  /// Disconnect provider button
  ///
  /// In en, this message translates to:
  /// **'Disconnect'**
  String get disconnect;

  /// Disconnect confirmation title
  ///
  /// In en, this message translates to:
  /// **'Disconnect {provider}?'**
  String disconnectConfirmTitle(String provider);

  /// Disconnect confirmation message
  ///
  /// In en, this message translates to:
  /// **'You can reconnect anytime from Settings.'**
  String get disconnectConfirmMessage;

  /// Google disconnect success snackbar
  ///
  /// In en, this message translates to:
  /// **'Google account disconnected'**
  String get googleDisconnected;

  /// Apple disconnect success snackbar
  ///
  /// In en, this message translates to:
  /// **'Apple account disconnected'**
  String get appleDisconnected;

  /// Sign out confirmation title
  ///
  /// In en, this message translates to:
  /// **'Sign out and erase this device?'**
  String get signOutConfirmTitle;

  /// Sign out confirmation message, warning that local data is destroyed
  ///
  /// In en, this message translates to:
  /// **'Signing out deletes every piece, photo and material stored on this device. Anything already backed up stays in your account and comes back when you sign in again — anything not backed up yet is gone for good.'**
  String get signOutConfirmMessage;

  /// Destructive confirm button in the sign out dialog
  ///
  /// In en, this message translates to:
  /// **'Sign Out & Erase'**
  String get signOutAndErase;

  /// Progress message shown while the local wipe runs
  ///
  /// In en, this message translates to:
  /// **'Signing out and erasing this device…'**
  String get signingOut;

  /// Shown when the local wipe on sign-out did not finish. Names the lock rather than a later sign-in: the owed wipe locks the router, and the lock screen is what retries it
  ///
  /// In en, this message translates to:
  /// **'Signed out, but some data on this device could not be deleted. This device stays locked until the erase finishes.'**
  String get signOutWipeFailed;

  /// Explains why the last remaining provider cannot be disconnected
  ///
  /// In en, this message translates to:
  /// **'Your only sign-in method — connect another first'**
  String get lastProviderCannotDisconnect;

  /// List view mode label for accessibility
  ///
  /// In en, this message translates to:
  /// **'List view'**
  String get viewModeList;

  /// Grid view mode label for accessibility
  ///
  /// In en, this message translates to:
  /// **'Grid view'**
  String get viewModeGrid;

  /// Cloud backup section header
  ///
  /// In en, this message translates to:
  /// **'Cloud Backup'**
  String get cloudBackup;

  /// Sync status when everything is synced
  ///
  /// In en, this message translates to:
  /// **'All data backed up'**
  String get syncBackedUp;

  /// Sync status while syncing
  ///
  /// In en, this message translates to:
  /// **'Syncing...'**
  String get syncSyncing;

  /// Sync status with pending changes
  ///
  /// In en, this message translates to:
  /// **'{count} changes pending'**
  String syncPending(int count);

  /// Sync error status
  ///
  /// In en, this message translates to:
  /// **'Sync error'**
  String get syncError;

  /// Sync disabled status
  ///
  /// In en, this message translates to:
  /// **'Sign in to enable cloud backup'**
  String get syncDisabled;

  /// Title of the lock screen when a wipe the user confirmed did not finish
  ///
  /// In en, this message translates to:
  /// **'This device still has to be erased'**
  String get deviceLockedWipeTitle;

  /// Explains the lock screen's owed-wipe reason. States the device's condition rather than attributing the request, because whichever account signs in next reads this and it may not be the one that asked
  ///
  /// In en, this message translates to:
  /// **'An erase was started on this device and did not finish. Nothing is uploaded and nothing can be changed until it completes.'**
  String get deviceLockedWipeMessage;

  /// Title of the read-only lock screen. Says nothing about who the reader is: a session-less launch on a contested device is either the owner opening the app offline or a refused account relaunching, and the lock deliberately cannot tell them apart
  ///
  /// In en, this message translates to:
  /// **'This device is locked'**
  String get deviceLockedTitle;

  /// Explains why the device is locked read-only, in terms true for either reader — it never asserts whose pottery it is
  ///
  /// In en, this message translates to:
  /// **'The pottery stored here belongs to an account that is not signed in, so it is kept read-only: nothing can be added or changed, and nothing is uploaded. Sign in as that account to carry on, or erase this device to start fresh.'**
  String get deviceLockedMessage;

  /// Shown on the lock screen when a confirmed account deletion left the account behind, naming the steps in the order the lock permits
  ///
  /// In en, this message translates to:
  /// **'Your account itself was not deleted — Firebase wanted a more recent sign-in. Erase this device first, then sign in again and use Delete Account & Data to remove it.'**
  String get deviceLockedAccountStillExists;

  /// Drops to the sign-in screen without deleting anything. Not "as another account": the reader may be the owner offline, signing in as themselves
  ///
  /// In en, this message translates to:
  /// **'Sign In'**
  String get deviceLockedSwitchAccount;

  /// Destructive action on the lock screen
  ///
  /// In en, this message translates to:
  /// **'Erase This Device'**
  String get deviceLockedErase;

  /// Shown when an erase was refused because a sync or wipe is running
  ///
  /// In en, this message translates to:
  /// **'Busy right now — try again in a moment.'**
  String get eraseLocalDataBusy;

  /// Shown only when an erase deleted nothing at all; a wipe that removed the rows but not every photo file uses eraseLocalDataPhotosSurvived instead
  ///
  /// In en, this message translates to:
  /// **'Could not erase this device. Nothing was deleted.'**
  String get eraseLocalDataFailed;

  /// Shown when an erase removed every row but left photo files behind, including a Delete Account & Data from a session with no account, where the local wipe is the whole action. Says what is true — the library is gone, the photographs are not, the wipe is still owed — and points at the retry the lock screen keeps offering
  ///
  /// In en, this message translates to:
  /// **'Pieces and materials were erased, but some photo files on this device could not be removed. The erase is still owed, so try again to finish it.'**
  String get eraseLocalDataPhotosSurvived;

  /// Settings tile that deletes the account and everything with it
  ///
  /// In en, this message translates to:
  /// **'Delete Account & Data'**
  String get deleteAccountTitle;

  /// Delete-account tile subtitle when nothing is outstanding
  ///
  /// In en, this message translates to:
  /// **'Permanently deletes your account and all data'**
  String get deleteAccountSubtitle;

  /// Title of the confirmation dialog for deleting the account
  ///
  /// In en, this message translates to:
  /// **'Delete Account & Data?'**
  String get deleteAccountConfirmTitle;

  /// Body of the confirmation dialog for deleting the account — names what is destroyed and that it cannot be undone
  ///
  /// In en, this message translates to:
  /// **'This will permanently delete your account and ALL pieces, photos, and materials from this device and the cloud. This cannot be undone.'**
  String get deleteAccountConfirmMessage;

  /// Shown when an account deletion was refused because a sync is running
  ///
  /// In en, this message translates to:
  /// **'Busy right now — try again in a moment.'**
  String get deleteAccountBusy;

  /// Shown when cloud data was deleted but the auth account still exists
  ///
  /// In en, this message translates to:
  /// **'Your data was deleted, but your account could not be. Sign in again and retry to remove it.'**
  String get deleteAccountSurvived;

  /// Shown when the cloud side was deleted but the local wipe failed
  ///
  /// In en, this message translates to:
  /// **'Your cloud data and account were deleted, but the copy on this device could not be. Erase this device to finish.'**
  String get deleteAccountLocalSurvived;

  /// Shown when the cloud tree was deleted but both the auth account and the local wipe survived
  ///
  /// In en, this message translates to:
  /// **'Your cloud data was deleted. Your account and the copy on this device were not — erase this device to finish, then sign in again and retry to remove the account.'**
  String get deleteAccountAndLocalSurvived;

  /// Replaces the delete-account tile's subtitle while an account deletion the user confirmed is still outstanding
  ///
  /// In en, this message translates to:
  /// **'Your last attempt removed your data but not your account. Sign in again first if this does not work.'**
  String get deleteAccountStillExists;

  /// Shown when an account deletion failed
  ///
  /// In en, this message translates to:
  /// **'Could not delete your account. Nothing was deleted.'**
  String get deleteAccountFailed;

  /// Title of the confirmation shown before erasing local data
  ///
  /// In en, this message translates to:
  /// **'Erase this device?'**
  String get eraseLocalDataConfirmTitle;

  /// Warning shown before an explicit local data erase
  ///
  /// In en, this message translates to:
  /// **'This deletes every piece, photo and material stored on this device. Anything already backed up stays in the account that owns it — anything not backed up yet is gone for good.'**
  String get eraseLocalDataConfirmMessage;

  /// Destructive confirm button for erasing local data
  ///
  /// In en, this message translates to:
  /// **'Erase'**
  String get eraseLocalDataConfirm;

  /// Manual sync button
  ///
  /// In en, this message translates to:
  /// **'Sync Now'**
  String get syncNow;

  /// Last sync timestamp
  ///
  /// In en, this message translates to:
  /// **'Last synced {date}'**
  String syncLastSynced(String date);

  /// Soft-ask dialog title
  ///
  /// In en, this message translates to:
  /// **'Enjoying Potter Journal?'**
  String get enjoymentDialogTitle;

  /// Soft-ask positive action
  ///
  /// In en, this message translates to:
  /// **'Yes, I love it!'**
  String get enjoymentDialogYes;

  /// Soft-ask negative action
  ///
  /// In en, this message translates to:
  /// **'Could be better'**
  String get enjoymentDialogNo;

  /// Feedback screen title
  ///
  /// In en, this message translates to:
  /// **'Send Feedback'**
  String get feedbackScreenTitle;

  /// Feedback category dropdown label
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get feedbackCategoryLabel;

  /// Bug category
  ///
  /// In en, this message translates to:
  /// **'Bug'**
  String get feedbackCategoryBug;

  /// Feature request category
  ///
  /// In en, this message translates to:
  /// **'Feature request'**
  String get feedbackCategoryFeature;

  /// Other category
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get feedbackCategoryOther;

  /// Praise category
  ///
  /// In en, this message translates to:
  /// **'Praise'**
  String get feedbackCategoryPraise;

  /// Feedback message field label
  ///
  /// In en, this message translates to:
  /// **'Message'**
  String get feedbackMessageLabel;

  /// Feedback message placeholder
  ///
  /// In en, this message translates to:
  /// **'What\'s on your mind?'**
  String get feedbackMessageHint;

  /// Optional reply email label
  ///
  /// In en, this message translates to:
  /// **'Reply email (optional)'**
  String get feedbackReplyEmailLabel;

  /// Optional reply email helper
  ///
  /// In en, this message translates to:
  /// **'Only if you want a reply'**
  String get feedbackReplyEmailHint;

  /// Send feedback button
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get feedbackSendButton;

  /// Toast after successful submit
  ///
  /// In en, this message translates to:
  /// **'Thanks — we read every message'**
  String get feedbackSentSuccess;

  /// Toast after failed submit
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t send — try again later'**
  String get feedbackSendFailed;
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
