import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pottery_tracker/database/daos/pieces_dao.dart';
import 'package:pottery_tracker/database/daos/photos_dao.dart';
import 'package:pottery_tracker/database/daos/materials_dao.dart';
import 'package:pottery_tracker/services/image_service.dart';
import 'package:pottery_tracker/services/sync_trigger.dart';

class MockPiecesDao extends Mock implements PiecesDao {}

class MockPhotosDao extends Mock implements PhotosDao {}

class MockMaterialsDao extends Mock implements MaterialsDao {}

class MockImageService extends Mock implements ImageService {}

class MockFirebaseAnalytics extends Mock implements FirebaseAnalytics {}

class MockSyncTrigger extends Mock implements SyncTrigger {}
