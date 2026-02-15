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

  const SyncQueueEntry({
    required this.operation,
    required this.entityId,
    this.extraData,
  });

  Map<String, dynamic> toJson() => {
        'op': operation.name,
        'id': entityId,
        if (extraData != null) 'extra': extraData,
      };

  factory SyncQueueEntry.fromJson(Map<String, dynamic> json) {
    return SyncQueueEntry(
      operation: SyncOperation.values.byName(json['op'] as String),
      entityId: json['id'] as String,
      extraData: json['extra'] as String?,
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
  static const _key = 'sync_queue';

  Future<void> enqueue(SyncQueueEntry entry) async {
    final entries = await getAll();
    if (entries.contains(entry)) return;
    entries.add(entry);
    await _save(entries);
  }

  Future<List<SyncQueueEntry>> getAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key);
    if (raw == null) return [];
    return raw
        .map((s) => SyncQueueEntry.fromJson(
            json.decode(s) as Map<String, dynamic>))
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
