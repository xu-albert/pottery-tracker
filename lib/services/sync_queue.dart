import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

enum SyncOperation {
  pushPiece,
  pushPhoto,
  pushPhotoFile,
  pushClay,
  pushGlaze,
  pushTag,
  pushPieceGlazes,
  pushPieceTags,
  deletePiece,
  deletePhoto,
  deleteMaterial,
}

class SyncQueueEntry {
  final SyncOperation operation;
  final String entityId;
  final String? extraData;
  final List<String>? changedFields;

  const SyncQueueEntry({
    required this.operation,
    required this.entityId,
    this.extraData,
    this.changedFields,
  });

  Map<String, dynamic> toJson() => {
    'op': operation.name,
    'id': entityId,
    if (extraData != null) 'extra': extraData,
    if (changedFields != null) 'changedFields': changedFields,
  };

  factory SyncQueueEntry.fromJson(Map<String, dynamic> json) {
    return SyncQueueEntry(
      operation: SyncOperation.values.byName(json['op'] as String),
      entityId: json['id'] as String,
      extraData: json['extra'] as String?,
      changedFields: (json['changedFields'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
    );
  }

  SyncQueueEntry mergeWith(SyncQueueEntry other) {
    List<String>? merged;
    if (changedFields != null && other.changedFields != null) {
      merged = {...changedFields!, ...other.changedFields!}.toList();
    }
    return SyncQueueEntry(
      operation: operation,
      entityId: entityId,
      extraData: extraData,
      changedFields: merged,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SyncQueueEntry &&
          operation == other.operation &&
          entityId == other.entityId &&
          extraData == other.extraData;

  @override
  int get hashCode => Object.hash(operation, entityId, extraData);
}

class SyncQueue {
  /// The preferences key the queue is persisted under. Public so the database
  /// bootstrap can drop a queue restored alongside a database it discards.
  static const storageKey = 'sync_queue';

  /// The stamp each queued slot currently carries, and the source of the next
  /// one. Entry equality ignores [SyncQueueEntry.changedFields], so a write
  /// that lands while its entity is being pushed merges into the very entry
  /// the push is holding rather than adding a row of its own — an
  /// acknowledgement by equality alone would take that newer revision with it
  /// and the write would never be uploaded.
  ///
  /// In memory only, and deliberately: nothing is in flight across a restart,
  /// so there is no acknowledgement left to honour. The stamp never repeats,
  /// so a revision captured before a push cannot be matched by a later one.
  final Map<SyncQueueEntry, int> _revisions = {};
  int _lastRevision = 0;
  Future<void> _mutationTail = Future<void>.value();
  Map<SyncQueueEntry, int> _unretired = {};
  Future<void>? _retiring;

  /// The revision [entry] holds right now. A drain captures this before it
  /// pushes and may only acknowledge the entry while it still reads the same.
  int revisionOf(SyncQueueEntry entry) => _revisions[entry] ?? 0;

  Future<void> enqueue(SyncQueueEntry entry) async {
    // Stamped before the first await: a push acknowledging between the two
    // would otherwise drop the revision this call is about to merge in.
    _revisions[entry] = ++_lastRevision;
    await _mutate(() async {
      final entries = await getAll();
      final existingIndex = entries.indexWhere((e) => e == entry);
      if (existingIndex != -1) {
        entries[existingIndex] = entries[existingIndex].mergeWith(entry);
      } else {
        entries.add(entry);
      }
      await _save(entries);
    });
  }

  /// Adds every entry of [batch] that is not already queued, with one read and
  /// one write, and stamps only those. An entry already queued keeps its
  /// revision, so a push already in flight for it still answers for it rather
  /// than being sent a second time.
  Future<void> enqueueMissing(List<SyncQueueEntry> batch) async {
    if (batch.isEmpty) return;
    await _mutate(() async {
      final entries = await getAll();
      final queued = entries.toSet();
      final missing = [
        for (final entry in batch)
          if (queued.add(entry)) entry,
      ];
      if (missing.isEmpty) return;
      for (final entry in missing) {
        _revisions[entry] = ++_lastRevision;
      }
      await _save([...entries, ...missing]);
    });
  }

  Future<List<SyncQueueEntry>> getAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(storageKey);
    if (raw == null) return [];
    return raw
        .map(
          (s) =>
              SyncQueueEntry.fromJson(json.decode(s) as Map<String, dynamic>),
        )
        .toList();
  }

  Future<void> remove(SyncQueueEntry entry) async {
    await _mutate(() async {
      _revisions.remove(entry);
      final entries = await getAll();
      entries.remove(entry);
      await _save(entries);
    });
  }

  /// Removes each entry of [dispatched] that no enqueue has revised since it
  /// captured the paired revision.
  ///
  /// Calls made while earlier queue work is still pending join one batch and
  /// receive the same future, so entries retired one by one as their pushes
  /// land still cost one read and one write per batch.
  ///
  /// The check and persisted mutation share the queue's mutation lane. An
  /// enqueue stamps its revision before joining that lane, so even an edit
  /// arriving just before this callback runs prevents the older push from
  /// acknowledging it.
  Future<void> acknowledgeAll(Map<SyncQueueEntry, int> dispatched) {
    _unretired.addAll(dispatched);
    return _retiring ??= _mutate(() async {
      final batch = _unretired;
      _unretired = {};
      _retiring = null;
      final delivered = {
        for (final MapEntry(key: entry, value: revision) in batch.entries)
          if (revisionOf(entry) == revision) entry,
      };
      if (delivered.isEmpty) return;
      delivered.forEach(_revisions.remove);
      final entries = await getAll();
      entries.removeWhere(delivered.contains);
      await _save(entries);
    });
  }

  Future<T> _mutate<T>(Future<T> Function() mutation) {
    final result = _mutationTail.then((_) => mutation());
    _mutationTail = result.then<void>((_) {}, onError: (_, _) {});
    return result;
  }

  Future<void> clear() async {
    await _mutate(() async {
      _revisions.clear();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(storageKey);
    });
  }

  Future<int> get pendingCount async => (await getAll()).length;

  Future<void> _save(List<SyncQueueEntry> entries) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      storageKey,
      entries.map((e) => json.encode(e.toJson())).toList(),
    );
  }
}
