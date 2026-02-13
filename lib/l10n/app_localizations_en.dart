// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Pottery Tracker';

  @override
  String get homeTab => 'Home';

  @override
  String get settingsTab => 'Settings';

  @override
  String get addPiece => 'Add Piece';

  @override
  String get searchPieces => 'Search pieces...';

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
  String get signInTitle => 'Pottery Tracker';

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
  String get supportDeveloper => 'Support the Developer';

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
  String get reorderPhotos => 'Reorder';

  @override
  String get addNew => '+ Add New';

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
}
