import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pottery_tracker/database/database.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  Future<String> createPiece(String id) async {
    await db.into(db.pieces).insert(PiecesCompanion.insert(
      id: id,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    ));
    return id;
  }

  Future<String> createGlaze(String id, String name) async {
    await db.into(db.glazeOptions).insert(GlazeOptionsCompanion.insert(
      id: id,
      name: name,
      createdAt: DateTime.now(),
    ));
    return id;
  }

  Future<String> createTag(String id, String name) async {
    await db.into(db.tagOptions).insert(TagOptionsCompanion.insert(
      id: id,
      name: name,
      createdAt: DateTime.now(),
    ));
    return id;
  }

  group('MaterialsDao setGlazesForPiece', () {
    test('records removed glazes in DeletedJunctions', () async {
      final pieceId = await createPiece('p1');
      await createGlaze('g1', 'Clear');
      await createGlaze('g2', 'Matte Black');
      await createGlaze('g3', 'Celadon');

      // Set initial glazes
      await db.materialsDao.setGlazesForPiece(pieceId, ['g1', 'g2', 'g3']);

      // Remove g2, keep g1 and g3
      await db.materialsDao.setGlazesForPiece(pieceId, ['g1', 'g3']);

      final deletions = await db.materialsDao.getDeletedJunctions(
        junctionType: 'pieceGlazes',
        pieceId: pieceId,
      );
      expect(deletions, hasLength(1));
      expect(deletions.first.optionId, 'g2');
      expect(deletions.first.junctionType, 'pieceGlazes');
    });

    test('does not record deletions when glazes are only added', () async {
      final pieceId = await createPiece('p1');
      await createGlaze('g1', 'Clear');
      await createGlaze('g2', 'Matte Black');

      // Set initial glazes
      await db.materialsDao.setGlazesForPiece(pieceId, ['g1']);

      // Add g2 (no removals)
      await db.materialsDao.setGlazesForPiece(pieceId, ['g1', 'g2']);

      final deletions = await db.materialsDao.getDeletedJunctions(
        junctionType: 'pieceGlazes',
        pieceId: pieceId,
      );
      expect(deletions, isEmpty);
    });

    test('records only the removed glaze when set is partially changed',
        () async {
      final pieceId = await createPiece('p1');
      await createGlaze('g1', 'Clear');
      await createGlaze('g2', 'Matte Black');
      await createGlaze('g3', 'Celadon');

      await db.materialsDao.setGlazesForPiece(pieceId, ['g1', 'g2']);

      // Replace g2 with g3 (g2 removed, g3 added)
      await db.materialsDao.setGlazesForPiece(pieceId, ['g1', 'g3']);

      final deletions = await db.materialsDao.getDeletedJunctions(
        junctionType: 'pieceGlazes',
        pieceId: pieceId,
      );
      expect(deletions, hasLength(1));
      expect(deletions.first.optionId, 'g2');
    });
  });

  group('MaterialsDao setTagsForPiece', () {
    test('records removed tags in DeletedJunctions', () async {
      final pieceId = await createPiece('p1');
      await createTag('t1', 'Gift');
      await createTag('t2', 'Sale');
      await createTag('t3', 'Personal');

      await db.materialsDao.setTagsForPiece(pieceId, ['t1', 't2', 't3']);

      // Remove t2
      await db.materialsDao.setTagsForPiece(pieceId, ['t1', 't3']);

      final deletions = await db.materialsDao.getDeletedJunctions(
        junctionType: 'pieceTags',
        pieceId: pieceId,
      );
      expect(deletions, hasLength(1));
      expect(deletions.first.optionId, 't2');
      expect(deletions.first.junctionType, 'pieceTags');
    });

    test('does not record deletions when tags are only added', () async {
      final pieceId = await createPiece('p1');
      await createTag('t1', 'Gift');
      await createTag('t2', 'Sale');

      await db.materialsDao.setTagsForPiece(pieceId, ['t1']);
      await db.materialsDao.setTagsForPiece(pieceId, ['t1', 't2']);

      final deletions = await db.materialsDao.getDeletedJunctions(
        junctionType: 'pieceTags',
        pieceId: pieceId,
      );
      expect(deletions, isEmpty);
    });

    test('records only the removed tag when set is partially changed',
        () async {
      final pieceId = await createPiece('p1');
      await createTag('t1', 'Gift');
      await createTag('t2', 'Sale');
      await createTag('t3', 'Personal');

      await db.materialsDao.setTagsForPiece(pieceId, ['t1', 't2']);
      await db.materialsDao.setTagsForPiece(pieceId, ['t1', 't3']);

      final deletions = await db.materialsDao.getDeletedJunctions(
        junctionType: 'pieceTags',
        pieceId: pieceId,
      );
      expect(deletions, hasLength(1));
      expect(deletions.first.optionId, 't2');
    });
  });

  group('MaterialsDao getDeletedJunctions', () {
    test('filters by junctionType and pieceId correctly', () async {
      final p1 = await createPiece('p1');
      final p2 = await createPiece('p2');
      await createGlaze('g1', 'Clear');
      await createTag('t1', 'Gift');

      // p1: set then remove a glaze
      await db.materialsDao.setGlazesForPiece(p1, ['g1']);
      await db.materialsDao.setGlazesForPiece(p1, []);

      // p2: set then remove a tag
      await db.materialsDao.setTagsForPiece(p2, ['t1']);
      await db.materialsDao.setTagsForPiece(p2, []);

      // Query p1 glazes — should find 1
      final p1Glazes = await db.materialsDao.getDeletedJunctions(
        junctionType: 'pieceGlazes',
        pieceId: p1,
      );
      expect(p1Glazes, hasLength(1));
      expect(p1Glazes.first.optionId, 'g1');

      // Query p2 tags — should find 1
      final p2Tags = await db.materialsDao.getDeletedJunctions(
        junctionType: 'pieceTags',
        pieceId: p2,
      );
      expect(p2Tags, hasLength(1));
      expect(p2Tags.first.optionId, 't1');

      // Query p1 tags — should be empty
      final p1Tags = await db.materialsDao.getDeletedJunctions(
        junctionType: 'pieceTags',
        pieceId: p1,
      );
      expect(p1Tags, isEmpty);
    });

    test('returns empty list when no deletions recorded', () async {
      await createPiece('p1');
      final result = await db.materialsDao.getDeletedJunctions(
        junctionType: 'pieceGlazes',
        pieceId: 'p1',
      );
      expect(result, isEmpty);
    });
  });

  group('MaterialsDao cleanupDeletedJunctions', () {
    test('removes specified records by id', () async {
      final pieceId = await createPiece('p1');
      await createGlaze('g1', 'Clear');
      await createGlaze('g2', 'Matte Black');

      await db.materialsDao.setGlazesForPiece(pieceId, ['g1', 'g2']);
      await db.materialsDao.setGlazesForPiece(pieceId, []);

      final deletions = await db.materialsDao.getDeletedJunctions(
        junctionType: 'pieceGlazes',
        pieceId: pieceId,
      );
      expect(deletions, hasLength(2));

      // Clean up just the first deletion
      await db.materialsDao.cleanupDeletedJunctions([deletions.first.id]);

      final remaining = await db.materialsDao.getDeletedJunctions(
        junctionType: 'pieceGlazes',
        pieceId: pieceId,
      );
      expect(remaining, hasLength(1));
      expect(remaining.first.id, deletions.last.id);
    });

    test('no-op when ids list is empty', () async {
      final pieceId = await createPiece('p1');
      await createGlaze('g1', 'Clear');

      await db.materialsDao.setGlazesForPiece(pieceId, ['g1']);
      await db.materialsDao.setGlazesForPiece(pieceId, []);

      await db.materialsDao.cleanupDeletedJunctions([]);

      final remaining = await db.materialsDao.getDeletedJunctions(
        junctionType: 'pieceGlazes',
        pieceId: pieceId,
      );
      expect(remaining, hasLength(1));
    });
  });

  group('MaterialsDao cleanupDeletedJunctionsForPiece', () {
    test('removes all deletions for given junctionType+pieceId', () async {
      final pieceId = await createPiece('p1');
      await createGlaze('g1', 'Clear');
      await createGlaze('g2', 'Matte Black');

      await db.materialsDao.setGlazesForPiece(pieceId, ['g1', 'g2']);
      await db.materialsDao.setGlazesForPiece(pieceId, []);

      await db.materialsDao.cleanupDeletedJunctionsForPiece(
        junctionType: 'pieceGlazes',
        pieceId: pieceId,
      );

      final remaining = await db.materialsDao.getDeletedJunctions(
        junctionType: 'pieceGlazes',
        pieceId: pieceId,
      );
      expect(remaining, isEmpty);
    });

    test('does not remove deletions for different pieceId', () async {
      final p1 = await createPiece('p1');
      final p2 = await createPiece('p2');
      await createGlaze('g1', 'Clear');

      // Both pieces had g1, then removed it
      await db.materialsDao.setGlazesForPiece(p1, ['g1']);
      await db.materialsDao.setGlazesForPiece(p1, []);
      await db.materialsDao.setGlazesForPiece(p2, ['g1']);
      await db.materialsDao.setGlazesForPiece(p2, []);

      // Clean up only p1's deletions
      await db.materialsDao.cleanupDeletedJunctionsForPiece(
        junctionType: 'pieceGlazes',
        pieceId: p1,
      );

      // p1 should be clean
      final p1Remaining = await db.materialsDao.getDeletedJunctions(
        junctionType: 'pieceGlazes',
        pieceId: p1,
      );
      expect(p1Remaining, isEmpty);

      // p2 should still have its deletion
      final p2Remaining = await db.materialsDao.getDeletedJunctions(
        junctionType: 'pieceGlazes',
        pieceId: p2,
      );
      expect(p2Remaining, hasLength(1));
    });
  });
}
