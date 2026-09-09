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

  /// The revision [entry] holds right now. A drain captures this before it
  /// pushes and may only acknowledge the entry while it still reads the same.
  int revisionOf(SyncQueueEntry entry) => _revisions[entry] ?? 0;

  Future<void> enqueue(SyncQueueEntry entry) async {
    // Stamped before the first await: a push acknowledging between the two
    // would otherwise drop the revision this call is about to merge in.
    _revisions[entry] = ++_lastRevision;
    final entries = await getAll();
    final existingIndex = entries.indexWhere((e) => e == entry);
    if (existingIndex != -1) {
      entries[existingIndex] = entries[existingIndex].mergeWith(entry);
    } else {
      entries.add(entry);
    }
    await _save(entries);
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
    _revisions.remove(entry);
    final entries = await getAll();
    entries.remove(entry);
    await _save(entries);
  }

  Future<void> clear() async {
    _revisions.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(storageKey);
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
