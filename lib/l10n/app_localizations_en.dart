// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Potter Journal';

  @override
  String get homeTab => 'Home';

  @override
  String get settingsTab => 'Settings';

  @override
  String get addPiece => 'Add Piece';

  @override
  String get searchPieces => 'Search anything...';

  @override
  String get searchActive => 'Search Active...';

  @override
  String get searchArchive => 'Search Archive...';

  @override
  String get filterAll => 'Active';

  @override
  String get filterArchived => 'Archive';

  @override
  String get emptyStateTitle => 'No pieces yet';

  @override
  String get emptyStateMessage =>
      'Tap + to take a photo and start tracking your first piece!';

  @override
  String get untitledPiece => 'Untitled Piece';

  @override
  String get stageGreenware => 'Greenware';

  @override
  String get stageBisqued => 'Bisqued';

  @override
  String get stageGlazed => 'Glazed';

  @override
  String get stageNone => 'None';

  @override
  String get titleLabel => 'Title';

  @override
  String get stageLabel => 'Stage';

  @override
  String get clayTypeLabel => 'Clay';

  @override
  String get glazesLabel => 'Glazes';

  @override
  String get notesLabel => 'Notes';

  @override
  String get addPhoto => 'Add Photo';

  @override
  String get deletePhoto => 'Delete Photo';

  @override
  String get setCoverPhoto => 'Set as Cover';

  @override
  String get deletePiece => 'Delete Piece';

  @override
  String get deletePieceConfirmTitle => 'Delete Piece?';

  @override
  String get deletePieceConfirmMessage =>
      'Are you sure you want to delete this piece? This cannot be undone.';

  @override
  String get cancel => 'Cancel';

  @override
  String get delete => 'Delete';

  @override
  String get camera => 'Camera';

  @override
  String get photoLibrary => 'Photo Library';

  @override
  String get signInTitle => 'Potter Journal';

  @override
  String get signInSubtitle => 'Track your ceramic creations';

  @override
  String get signInWithGoogle => 'Sign in with Google';

  @override
  String get signInWithApple => 'Sign in with Apple';

  @override
  String get skipForNow => 'Skip for now';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get account => 'Account';

  @override
  String signedInAs(String name) {
    return 'Signed in as $name';
  }

  @override
  String get notSignedIn => 'Not signed in';

  @override
  String get signOut => 'Sign Out';

  @override
  String get signInCancelled => 'Sign-in cancelled';

  @override
  String get about => 'About';

  @override
  String version(String version) {
    return 'Version $version';
  }

  @override
  String get syncStatus => 'Sync Status';

  @override
  String get syncComingSoon => 'Cloud sync coming soon';

  @override
  String get storage => 'Storage';

  @override
  String photoOf(int current, int total) {
    return 'Photo $current of $total';
  }

  @override
  String get noPhotos => 'No photos';

  @override
  String get deletePhotoConfirmTitle => 'Delete Photo?';

  @override
  String get deletePhotoConfirmMessage =>
      'This photo will be permanently deleted.';

  @override
  String get archivePiece => 'Archive';

  @override
  String get unarchivePiece => 'Unarchive';

  @override
  String lastUpdated(String date) {
    return 'Last updated $date';
  }

  @override
  String get editDate => 'Edit Date';

  @override
  String processingPhotos(int current, int total) {
    return 'Processing $current of $total...';
  }

  @override
  String batchPhotoFailures(int count) {
    return '$count photo(s) could not be added';
  }

  @override
  String get reorderPhotos => 'Reorder photos';

  @override
  String get addNew => 'Add New';

  @override
  String get create => 'Create';

  @override
  String get enterClayName => 'Enter clay name';

  @override
  String get manageClays => 'Manage Clays';

  @override
  String get manageMaterials => 'Materials';

  @override
  String get noClaysYet => 'No clays saved yet';

  @override
  String get editClayName => 'Edit clay name';

  @override
  String get save => 'Save';

  @override
  String get deleteClayConfirmTitle => 'Delete Clay?';

  @override
  String get deleteClayConfirmMessage =>
      'Pieces using this clay will keep their current value, but it will no longer appear in the dropdown.';

  @override
  String get manageGlazes => 'Manage Glazes';

  @override
  String get noGlazesYet => 'No glazes saved yet';

  @override
  String get enterGlazeName => 'Enter glaze name';

  @override
  String get editGlazeName => 'Edit glaze name';

  @override
  String get deleteGlazeConfirmTitle => 'Delete Glaze?';

  @override
  String get deleteGlazeConfirmMessage =>
      'This glaze will be removed from all pieces that use it.';

  @override
  String get selectGlazes => 'Select Glazes';

  @override
  String get glazesNone => 'None';

  @override
  String get done => 'Done';

  @override
  String get tagsLabel => 'Tags';

  @override
  String get manageTags => 'Manage Tags';

  @override
  String get noTagsYet => 'No tags saved yet';

  @override
  String get enterTagName => 'Enter tag name';

  @override
  String get editTagName => 'Edit tag name';

  @override
  String get deleteTagConfirmTitle => 'Delete Tag?';

  @override
  String get deleteTagConfirmMessage =>
      'This tag will be removed from all pieces that use it.';

  @override
  String get selectTags => 'Select Tags';

  @override
  String get tagsNone => 'None';

  @override
  String get manageClaysSubtitle => 'Recently used clays appear first';

  @override
  String get manageGlazesSubtitle => 'Recently used glazes appear first';

  @override
  String get manageTagsSubtitle => 'Recently used tags appear first';

  @override
  String get searchClays => 'Search clays...';

  @override
  String get searchGlazes => 'Search glazes...';

  @override
  String get searchTags => 'Search tags...';

  @override
  String get selectClay => 'Select Clay';

  @override
  String get recent => 'Recent';

  @override
  String addNewWithName(String name) {
    return 'Add \"$name\"';
  }

  @override
  String get tagColor => 'Tag Color';

  @override
  String pieceArchivedWithTitle(String title) {
    return '$title archived';
  }

  @override
  String pieceUnarchivedWithTitle(String title) {
    return '$title unarchived';
  }

  @override
  String get undo => 'Undo';

  @override
  String get sendFeedback => 'Send Feedback';

  @override
  String get connectedAccounts => 'Connected Accounts';

  @override
  String get google => 'Google';

  @override
  String get apple => 'Apple';

  @override
  String get connect => 'Connect';

  @override
  String get connected => 'Connected';

  @override
  String get googleLinkedSuccess => 'Google account connected';

  @override
  String get appleLinkedSuccess => 'Apple account connected';

  @override
  String get accountAlreadyLinked =>
      'This account is already linked to a different user';

  @override
  String get signInToEnableSync => 'Sign in to enable cloud sync';

  @override
  String get comingSoon => 'Coming soon';

  @override
  String get linked => 'LINKED';

  @override
  String get notLinked => 'NOT LINKED';

  @override
  String get disconnect => 'Disconnect';

  @override
  String disconnectConfirmTitle(String provider) {
    return 'Disconnect $provider?';
  }

  @override
  String get disconnectConfirmMessage =>
      'You can reconnect anytime from Settings.';

  @override
  String get googleDisconnected => 'Google account disconnected';

  @override
  String get appleDisconnected => 'Apple account disconnected';

  @override
  String get signOutConfirmTitle => 'Sign out and erase this device?';

  @override
  String get signOutConfirmMessage =>
      'Signing out deletes every piece, photo and material stored on this device. Anything already backed up stays in your account and comes back when you sign in again — anything not backed up yet is gone for good.';

  @override
  String get signOutAndErase => 'Sign Out & Erase';

  @override
  String get signingOut => 'Signing out and erasing this device…';

  @override
  String get signOutWipeFailed =>
      'Signed out, but some data on this device could not be deleted. This device stays locked until the erase finishes.';

  @override
  String get lastProviderCannotDisconnect =>
      'Your only sign-in method — connect another first';

  @override
  String get viewModeList => 'List view';

  @override
  String get viewModeGrid => 'Grid view';

  @override
  String get cloudBackup => 'Cloud Backup';

  @override
  String get syncBackedUp => 'All data backed up';

  @override
  String get syncSyncing => 'Syncing...';

  @override
  String syncPending(int count) {
    return '$count changes pending';
  }

  @override
  String get syncError => 'Sync error';

  @override
  String get syncDisabled => 'Sign in to enable cloud backup';

  @override
  String get deviceLockedWipeTitle => 'This device still has to be erased';

  @override
  String get deviceLockedWipeMessage =>
      'An erase was started on this device and did not finish. Nothing is uploaded and nothing can be changed until it completes.';

  @override
  String get deviceLockedTitle => 'This device is locked';

  @override
  String get deviceLockedMessage =>
      'The pottery stored here belongs to an account that is not signed in, so it is kept read-only: nothing can be added or changed, and nothing is uploaded. Sign in as that account to carry on, or erase this device to start fresh.';

  @override
  String get deviceLockedAccountStillExists =>
      'Your account itself was not deleted — Firebase wanted a more recent sign-in. Erase this device first, then sign in again and use Delete Account & Data to remove it.';

  @override
  String get deviceLockedSwitchAccount => 'Sign In';

  @override
  String get deviceLockedErase => 'Erase This Device';

  @override
  String get eraseLocalDataBusy => 'Busy right now — try again in a moment.';

  @override
  String get eraseLocalDataFailed =>
      'Could not erase this device. Nothing was deleted.';

  @override
  String get eraseLocalDataPhotosSurvived =>
      'Pieces and materials were erased, but some photo files on this device could not be removed. The erase is still owed, so try again to finish it.';

  @override
  String get eraseLocalDataNotSecured =>
      'Everything on this device was erased, but its database key could not be replaced, so the device is not yet secured for whoever uses it next. The erase is still owed, so try again to finish it.';

  @override
  String get deleteAccountTitle => 'Delete Account & Data';

  @override
  String get deleteAccountSubtitle =>
      'Permanently deletes your account and all data';

  @override
  String get deleteAccountConfirmTitle => 'Delete Account & Data?';

  @override
  String get deleteAccountConfirmMessage =>
      'This will permanently delete your account and ALL pieces, photos, and materials from this device and the cloud. This cannot be undone.';

  @override
  String get deleteAccountBusy => 'Busy right now — try again in a moment.';

  @override
  String get deleteAccountSurvived =>
      'Your data was deleted, but your account could not be. Sign in again and retry to remove it.';

  @override
  String get deleteAccountLocalSurvived =>
      'Your cloud data and account were deleted, but the copy on this device could not be. Erase this device to finish.';

  @override
  String get deleteAccountAndLocalSurvived =>
      'Your cloud data was deleted. Your account and the copy on this device were not — erase this device to finish, then sign in again and retry to remove the account.';

  @override
  String get deleteAccountStillExists =>
      'Your last attempt removed your data but not your account. Sign in again first if this does not work.';

  @override
  String get deleteAccountFailed =>
      'Could not delete your account. Nothing was deleted.';

  @override
  String get eraseLocalDataConfirmTitle => 'Erase this device?';

  @override
  String get eraseLocalDataConfirmMessage =>
      'This deletes every piece, photo and material stored on this device. Anything already backed up stays in the account that owns it — anything not backed up yet is gone for good.';

  @override
  String get eraseLocalDataConfirm => 'Erase';

  @override
  String get syncNow => 'Sync Now';

  @override
  String syncLastSynced(String date) {
    return 'Last synced $date';
  }

  @override
  String get enjoymentDialogTitle => 'Enjoying Potter Journal?';

  @override
  String get enjoymentDialogYes => 'Yes, I love it!';

  @override
  String get enjoymentDialogNo => 'Could be better';

  @override
  String get feedbackScreenTitle => 'Send Feedback';

  @override
  String get feedbackCategoryLabel => 'Category';

  @override
  String get feedbackCategoryBug => 'Bug';

  @override
  String get feedbackCategoryFeature => 'Feature request';

  @override
  String get feedbackCategoryOther => 'Other';

  @override
  String get feedbackCategoryPraise => 'Praise';

  @override
  String get feedbackMessageLabel => 'Message';

  @override
  String get feedbackMessageHint => 'What\'s on your mind?';

  @override
  String get feedbackReplyEmailLabel => 'Reply email (optional)';

  @override
  String get feedbackReplyEmailHint => 'Only if you want a reply';

  @override
  String get feedbackSendButton => 'Send';

  @override
  String get feedbackSentSuccess => 'Thanks — we read every message';

  @override
  String get feedbackSendFailed => 'Couldn\'t send — try again later';

  @override
  String get recoveryTitle => 'This phone can\'t open your pottery journal';

  @override
  String get recoveryMessageKeyMissing =>
      'Your journal was restored from a backup, but the key that unlocks it stays on the phone it was made on and is never included in backups. That protects your pottery if a backup is ever copied — and it means this phone can\'t read the restored copy on its own.';

  @override
  String get recoveryMessageKeyMissingAndroid =>
      'The key that unlocks this journal is held in this phone\'s secure hardware and never leaves it, so it is never included in a backup or a phone-to-phone transfer. This phone can no longer read that key, so the journal stored here can\'t be opened on its own.';

  @override
  String get recoveryMessageKeyMismatch =>
      'The journal on this phone was encrypted with a key this phone no longer has, so it can\'t be read on its own.';

  @override
  String get recoveryCloudHint =>
      'This journal was backed up to an account. Sign in with it and your pieces are downloaded again; the photos already on this phone are kept. Changes the old phone never finished backing up are lost.';

  @override
  String get recoveryLocalOnlyHint =>
      'This journal was kept on the old phone only and never signed in, so there is no cloud copy to download. Without its transfer passphrase, its pieces can\'t be recovered here.';

  @override
  String get recoveryLocalOnlyHintAndroid =>
      'This journal was never signed in, so there is no cloud copy to download. Pottery kept on this phone alone can\'t be recovered without its key.';

  @override
  String get recoveryPassphraseSection =>
      'Unlock with your transfer passphrase';

  @override
  String get recoveryPassphraseLabel => 'Transfer passphrase';

  @override
  String get recoveryUnlock => 'Unlock';

  @override
  String get recoveryWrongPassphrase => 'That passphrase doesn\'t match.';

  @override
  String get recoveryTransferKeyMismatch =>
      'The passphrase is right, but the key it protects doesn\'t open this journal.';

  @override
  String get recoveryRedownload => 'Sign in and download again';

  @override
  String get recoveryRedownloadConfirmTitle => 'Download your pieces again?';

  @override
  String get recoveryRedownloadConfirmMessage =>
      'The unreadable copy on this phone is removed. Your photos stay, and your pieces are downloaded again once you sign in. Any changes the old phone never finished backing up are lost.';

  @override
  String get recoveryRedownloadConfirm => 'Remove and sign in';

  @override
  String get recoveryStartFresh => 'Start fresh without them';

  @override
  String get recoveryStartFreshConfirmTitle => 'Delete the restored pieces?';

  @override
  String get recoveryStartFreshConfirmMessage =>
      'The pieces and photos restored from your old phone are deleted from this phone. If you still have the old phone, set a transfer passphrase in its Settings and restore this phone from a new backup instead. This cannot be undone.';

  @override
  String get recoveryStartFreshConfirmMessageAndroid =>
      'The pieces and photos on this phone are deleted. This cannot be undone.';

  @override
  String get recoveryStartFreshConfirm => 'Delete and start fresh';

  @override
  String recoveryFailed(String error) {
    return 'Something went wrong: $error';
  }

  @override
  String get launchFailedTitle => 'Couldn\'t open your pottery journal';

  @override
  String launchFailedMessage(String error) {
    return 'Nothing was changed. Try again, and if this keeps happening, send feedback from a fresh install so it can be fixed.\n\n$error';
  }

  @override
  String get tryAgain => 'Try again';

  @override
  String get deviceTransfer => 'Moving to a new phone';

  @override
  String get transferPassphrase => 'Transfer passphrase';

  @override
  String get transferPassphraseSet =>
      'Set — a phone backup can carry your pottery';

  @override
  String get transferPassphraseNotSet => 'Not set';

  @override
  String get transferExplanationLocalOnly =>
      'Pottery kept only on this phone is encrypted with a key that never leaves it, so a phone backup restores the journal but can\'t open it. A transfer passphrase lets a new phone unlock it. Signing in backs pottery up to the cloud instead.';

  @override
  String get transferExplanationSignedIn =>
      'Your pieces are backed up to your account and come back by signing in on a new phone. A transfer passphrase is only needed for pottery kept on this phone alone.';

  @override
  String get transferExplanationAndroid =>
      'Pottery kept only on this phone stays on this phone: the app keeps its data out of Android backups and phone-to-phone transfers, so it can\'t be moved to a new phone. Signing in backs it up to your account instead, and it comes back by signing in on the new phone.';

  @override
  String get setTransferPassphrase => 'Set transfer passphrase';

  @override
  String get changeTransferPassphrase => 'Change passphrase';

  @override
  String get removeTransferPassphrase => 'Remove passphrase';

  @override
  String transferPassphraseSheetMessage(int min) {
    return 'Choose a passphrase you\'ll remember — you type it once, on the new phone. Anyone holding a backup of this phone can try to guess it, so make it a phrase rather than a PIN: at least $min characters.';
  }

  @override
  String get transferPassphraseHint => 'Passphrase';

  @override
  String get transferPassphraseConfirmHint => 'Repeat passphrase';

  @override
  String transferPassphraseTooShort(int min) {
    return 'Use at least $min characters.';
  }

  @override
  String get transferPassphraseMismatch => 'The two entries don\'t match.';

  @override
  String get transferPassphraseSaved => 'Transfer passphrase set.';

  @override
  String get transferPassphraseRemoved => 'Transfer passphrase removed.';

  @override
  String transferPassphraseFailed(String error) {
    return 'Couldn\'t save the passphrase: $error';
  }

  @override
  String transferPassphraseRemoveFailed(String error) {
    return 'Couldn\'t remove the passphrase: $error';
  }

  @override
  String get transferPassphraseRemoveConfirmTitle =>
      'Remove the transfer passphrase?';

  @override
  String get transferPassphraseRemoveConfirmMessage =>
      'A backup of this phone will no longer be able to open your pottery on a new phone.';

  @override
  String get remove => 'Remove';
}
