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

  /// The uid of the session that made the write, or null when it was made
  /// local-only with nobody signed in.
  ///
  /// A null uid belongs to whoever owns the device — that is the local-only
  /// upgrade path, where a user's pre-sign-in pottery is theirs to upload. A
  /// non-null uid that differs from the account draining the queue is work
  /// from a session this device refused, and must never reach the draining
  /// account's cloud tree.
  ///
  /// This has to be captured at enqueue time: by the time the queue drains,
  /// the session that produced the write may be long gone.
  ///
  /// Entries persisted by builds that shipped before entries carried a uid
  /// have no `uid` key. They deserialize to null and are therefore treated as
  /// local-only, which is the only safe reading — those builds had no way for
  /// a second account to write here at all.
  final String? uid;

  const SyncQueueEntry({
    required this.operation,
    required this.entityId,
    this.extraData,
    this.changedFields,
    this.uid,
  });

  Map<String, dynamic> toJson() => {
    'op': operation.name,
    'id': entityId,
    if (extraData != null) 'extra': extraData,
    if (changedFields != null) 'changedFields': changedFields,
    if (uid != null) 'uid': uid,
  };

  factory SyncQueueEntry.fromJson(Map<String, dynamic> json) {
    return SyncQueueEntry(
      operation: SyncOperation.values.byName(json['op'] as String),
      entityId: json['id'] as String,
      extraData: json['extra'] as String?,
      changedFields: (json['changedFields'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      uid: json['uid'] as String?,
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
      uid: uid,
    );
  }

  /// [uid] is part of identity, so a second account's write never merges
  /// into the owner's entry and rides out under the owner's name.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SyncQueueEntry &&
          operation == other.operation &&
          entityId == other.entityId &&
          extraData == other.extraData &&
          uid == other.uid;

  @override
  int get hashCode => Object.hash(operation, entityId, extraData, uid);
}

class SyncQueue {
  static const _key = 'sync_queue';

  Future<void> enqueue(SyncQueueEntry entry) async {
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
    final raw = prefs.getStringList(_key);
    if (raw == null) return [];
    return raw
        .map(
          (s) =>
              SyncQueueEntry.fromJson(json.decode(s) as Map<String, dynamic>),
        )
        .toList();
  }

  Future<void> remove(SyncQueueEntry entry) async {
    final entries = await getAll();
    entries.remove(entry);
    await _save(entries);
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  Future<int> get pendingCount async => (await getAll()).length;

  Future<void> _save(List<SyncQueueEntry> entries) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _key,
      entries.map((e) => json.encode(e.toJson())).toList(),
    );
  }
}
