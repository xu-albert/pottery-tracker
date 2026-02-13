// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $PiecesTable extends Pieces with TableInfo<$PiecesTable, Piece> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PiecesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _stageMeta = const VerificationMeta('stage');
  @override
  late final GeneratedColumn<String> stage = GeneratedColumn<String>(
    'stage',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _clayTypeMeta = const VerificationMeta(
    'clayType',
  );
  @override
  late final GeneratedColumn<String> clayType = GeneratedColumn<String>(
    'clay_type',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _glazesMeta = const VerificationMeta('glazes');
  @override
  late final GeneratedColumn<String> glazes = GeneratedColumn<String>(
    'glazes',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
    'notes',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _coverPhotoIdMeta = const VerificationMeta(
    'coverPhotoId',
  );
  @override
  late final GeneratedColumn<String> coverPhotoId = GeneratedColumn<String>(
    'cover_photo_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isArchivedMeta = const VerificationMeta(
    'isArchived',
  );
  @override
  late final GeneratedColumn<bool> isArchived = GeneratedColumn<bool>(
    'is_archived',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_archived" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    title,
    stage,
    clayType,
    glazes,
    notes,
    coverPhotoId,
    isArchived,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'pieces';
  @override
  VerificationContext validateIntegrity(
    Insertable<Piece> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    }
    if (data.containsKey('stage')) {
      context.handle(
        _stageMeta,
        stage.isAcceptableOrUnknown(data['stage']!, _stageMeta),
      );
    }
    if (data.containsKey('clay_type')) {
      context.handle(
        _clayTypeMeta,
        clayType.isAcceptableOrUnknown(data['clay_type']!, _clayTypeMeta),
      );
    }
    if (data.containsKey('glazes')) {
      context.handle(
        _glazesMeta,
        glazes.isAcceptableOrUnknown(data['glazes']!, _glazesMeta),
      );
    }
    if (data.containsKey('notes')) {
      context.handle(
        _notesMeta,
        notes.isAcceptableOrUnknown(data['notes']!, _notesMeta),
      );
    }
    if (data.containsKey('cover_photo_id')) {
      context.handle(
        _coverPhotoIdMeta,
        coverPhotoId.isAcceptableOrUnknown(
          data['cover_photo_id']!,
          _coverPhotoIdMeta,
        ),
      );
    }
    if (data.containsKey('is_archived')) {
      context.handle(
        _isArchivedMeta,
        isArchived.isAcceptableOrUnknown(data['is_archived']!, _isArchivedMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Piece map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Piece(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      ),
      stage: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}stage'],
      ),
      clayType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}clay_type'],
      ),
      glazes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}glazes'],
      ),
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      ),
      coverPhotoId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cover_photo_id'],
      ),
      isArchived: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_archived'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $PiecesTable createAlias(String alias) {
    return $PiecesTable(attachedDatabase, alias);
  }
}

class Piece extends DataClass implements Insertable<Piece> {
  final String id;
  final String? title;
  final String? stage;
  final String? clayType;
  final String? glazes;
  final String? notes;
  final String? coverPhotoId;
  final bool isArchived;
  final DateTime createdAt;
  final DateTime updatedAt;
  const Piece({
    required this.id,
    this.title,
    this.stage,
    this.clayType,
    this.glazes,
    this.notes,
    this.coverPhotoId,
    required this.isArchived,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    if (!nullToAbsent || title != null) {
      map['title'] = Variable<String>(title);
    }
    if (!nullToAbsent || stage != null) {
      map['stage'] = Variable<String>(stage);
    }
    if (!nullToAbsent || clayType != null) {
      map['clay_type'] = Variable<String>(clayType);
    }
    if (!nullToAbsent || glazes != null) {
      map['glazes'] = Variable<String>(glazes);
    }
    if (!nullToAbsent || notes != null) {
      map['notes'] = Variable<String>(notes);
    }
    if (!nullToAbsent || coverPhotoId != null) {
      map['cover_photo_id'] = Variable<String>(coverPhotoId);
    }
    map['is_archived'] = Variable<bool>(isArchived);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  PiecesCompanion toCompanion(bool nullToAbsent) {
    return PiecesCompanion(
      id: Value(id),
      title: title == null && nullToAbsent
          ? const Value.absent()
          : Value(title),
      stage: stage == null && nullToAbsent
          ? const Value.absent()
          : Value(stage),
      clayType: clayType == null && nullToAbsent
          ? const Value.absent()
          : Value(clayType),
      glazes: glazes == null && nullToAbsent
          ? const Value.absent()
          : Value(glazes),
      notes: notes == null && nullToAbsent
          ? const Value.absent()
          : Value(notes),
      coverPhotoId: coverPhotoId == null && nullToAbsent
          ? const Value.absent()
          : Value(coverPhotoId),
      isArchived: Value(isArchived),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory Piece.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Piece(
      id: serializer.fromJson<String>(json['id']),
      title: serializer.fromJson<String?>(json['title']),
      stage: serializer.fromJson<String?>(json['stage']),
      clayType: serializer.fromJson<String?>(json['clayType']),
      glazes: serializer.fromJson<String?>(json['glazes']),
      notes: serializer.fromJson<String?>(json['notes']),
      coverPhotoId: serializer.fromJson<String?>(json['coverPhotoId']),
      isArchived: serializer.fromJson<bool>(json['isArchived']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'title': serializer.toJson<String?>(title),
      'stage': serializer.toJson<String?>(stage),
      'clayType': serializer.toJson<String?>(clayType),
      'glazes': serializer.toJson<String?>(glazes),
      'notes': serializer.toJson<String?>(notes),
      'coverPhotoId': serializer.toJson<String?>(coverPhotoId),
      'isArchived': serializer.toJson<bool>(isArchived),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  Piece copyWith({
    String? id,
    Value<String?> title = const Value.absent(),
    Value<String?> stage = const Value.absent(),
    Value<String?> clayType = const Value.absent(),
    Value<String?> glazes = const Value.absent(),
    Value<String?> notes = const Value.absent(),
    Value<String?> coverPhotoId = const Value.absent(),
    bool? isArchived,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => Piece(
    id: id ?? this.id,
    title: title.present ? title.value : this.title,
    stage: stage.present ? stage.value : this.stage,
    clayType: clayType.present ? clayType.value : this.clayType,
    glazes: glazes.present ? glazes.value : this.glazes,
    notes: notes.present ? notes.value : this.notes,
    coverPhotoId: coverPhotoId.present ? coverPhotoId.value : this.coverPhotoId,
    isArchived: isArchived ?? this.isArchived,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  Piece copyWithCompanion(PiecesCompanion data) {
    return Piece(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      stage: data.stage.present ? data.stage.value : this.stage,
      clayType: data.clayType.present ? data.clayType.value : this.clayType,
      glazes: data.glazes.present ? data.glazes.value : this.glazes,
      notes: data.notes.present ? data.notes.value : this.notes,
      coverPhotoId: data.coverPhotoId.present
          ? data.coverPhotoId.value
          : this.coverPhotoId,
      isArchived: data.isArchived.present
          ? data.isArchived.value
          : this.isArchived,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Piece(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('stage: $stage, ')
          ..write('clayType: $clayType, ')
          ..write('glazes: $glazes, ')
          ..write('notes: $notes, ')
          ..write('coverPhotoId: $coverPhotoId, ')
          ..write('isArchived: $isArchived, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    title,
    stage,
    clayType,
    glazes,
    notes,
    coverPhotoId,
    isArchived,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Piece &&
          other.id == this.id &&
          other.title == this.title &&
          other.stage == this.stage &&
          other.clayType == this.clayType &&
          other.glazes == this.glazes &&
          other.notes == this.notes &&
          other.coverPhotoId == this.coverPhotoId &&
          other.isArchived == this.isArchived &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class PiecesCompanion extends UpdateCompanion<Piece> {
  final Value<String> id;
  final Value<String?> title;
  final Value<String?> stage;
  final Value<String?> clayType;
  final Value<String?> glazes;
  final Value<String?> notes;
  final Value<String?> coverPhotoId;
  final Value<bool> isArchived;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const PiecesCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.stage = const Value.absent(),
    this.clayType = const Value.absent(),
    this.glazes = const Value.absent(),
    this.notes = const Value.absent(),
    this.coverPhotoId = const Value.absent(),
    this.isArchived = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PiecesCompanion.insert({
    required String id,
    this.title = const Value.absent(),
    this.stage = const Value.absent(),
    this.clayType = const Value.absent(),
    this.glazes = const Value.absent(),
    this.notes = const Value.absent(),
    this.coverPhotoId = const Value.absent(),
    this.isArchived = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<Piece> custom({
    Expression<String>? id,
    Expression<String>? title,
    Expression<String>? stage,
    Expression<String>? clayType,
    Expression<String>? glazes,
    Expression<String>? notes,
    Expression<String>? coverPhotoId,
    Expression<bool>? isArchived,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (stage != null) 'stage': stage,
      if (clayType != null) 'clay_type': clayType,
      if (glazes != null) 'glazes': glazes,
      if (notes != null) 'notes': notes,
      if (coverPhotoId != null) 'cover_photo_id': coverPhotoId,
      if (isArchived != null) 'is_archived': isArchived,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PiecesCompanion copyWith({
    Value<String>? id,
    Value<String?>? title,
    Value<String?>? stage,
    Value<String?>? clayType,
    Value<String?>? glazes,
    Value<String?>? notes,
    Value<String?>? coverPhotoId,
    Value<bool>? isArchived,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return PiecesCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      stage: stage ?? this.stage,
      clayType: clayType ?? this.clayType,
      glazes: glazes ?? this.glazes,
      notes: notes ?? this.notes,
      coverPhotoId: coverPhotoId ?? this.coverPhotoId,
      isArchived: isArchived ?? this.isArchived,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (stage.present) {
      map['stage'] = Variable<String>(stage.value);
    }
    if (clayType.present) {
      map['clay_type'] = Variable<String>(clayType.value);
    }
    if (glazes.present) {
      map['glazes'] = Variable<String>(glazes.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (coverPhotoId.present) {
      map['cover_photo_id'] = Variable<String>(coverPhotoId.value);
    }
    if (isArchived.present) {
      map['is_archived'] = Variable<bool>(isArchived.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PiecesCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('stage: $stage, ')
          ..write('clayType: $clayType, ')
          ..write('glazes: $glazes, ')
          ..write('notes: $notes, ')
          ..write('coverPhotoId: $coverPhotoId, ')
          ..write('isArchived: $isArchived, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PhotosTable extends Photos with TableInfo<$PhotosTable, Photo> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PhotosTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pieceIdMeta = const VerificationMeta(
    'pieceId',
  );
  @override
  late final GeneratedColumn<String> pieceId = GeneratedColumn<String>(
    'piece_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES pieces (id)',
    ),
  );
  static const VerificationMeta _localPathMeta = const VerificationMeta(
    'localPath',
  );
  @override
  late final GeneratedColumn<String> localPath = GeneratedColumn<String>(
    'local_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _thumbnailPathMeta = const VerificationMeta(
    'thumbnailPath',
  );
  @override
  late final GeneratedColumn<String> thumbnailPath = GeneratedColumn<String>(
    'thumbnail_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _cloudUrlMeta = const VerificationMeta(
    'cloudUrl',
  );
  @override
  late final GeneratedColumn<String> cloudUrl = GeneratedColumn<String>(
    'cloud_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _dateTakenMeta = const VerificationMeta(
    'dateTaken',
  );
  @override
  late final GeneratedColumn<DateTime> dateTaken = GeneratedColumn<DateTime>(
    'date_taken',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    pieceId,
    localPath,
    thumbnailPath,
    cloudUrl,
    dateTaken,
    createdAt,
    sortOrder,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'photos';
  @override
  VerificationContext validateIntegrity(
    Insertable<Photo> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('piece_id')) {
      context.handle(
        _pieceIdMeta,
        pieceId.isAcceptableOrUnknown(data['piece_id']!, _pieceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_pieceIdMeta);
    }
    if (data.containsKey('local_path')) {
      context.handle(
        _localPathMeta,
        localPath.isAcceptableOrUnknown(data['local_path']!, _localPathMeta),
      );
    } else if (isInserting) {
      context.missing(_localPathMeta);
    }
    if (data.containsKey('thumbnail_path')) {
      context.handle(
        _thumbnailPathMeta,
        thumbnailPath.isAcceptableOrUnknown(
          data['thumbnail_path']!,
          _thumbnailPathMeta,
        ),
      );
    }
    if (data.containsKey('cloud_url')) {
      context.handle(
        _cloudUrlMeta,
        cloudUrl.isAcceptableOrUnknown(data['cloud_url']!, _cloudUrlMeta),
      );
    }
    if (data.containsKey('date_taken')) {
      context.handle(
        _dateTakenMeta,
        dateTaken.isAcceptableOrUnknown(data['date_taken']!, _dateTakenMeta),
      );
    } else if (isInserting) {
      context.missing(_dateTakenMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Photo map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Photo(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      pieceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}piece_id'],
      )!,
      localPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_path'],
      )!,
      thumbnailPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}thumbnail_path'],
      ),
      cloudUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cloud_url'],
      ),
      dateTaken: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}date_taken'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
    );
  }

  @override
  $PhotosTable createAlias(String alias) {
    return $PhotosTable(attachedDatabase, alias);
  }
}

class Photo extends DataClass implements Insertable<Photo> {
  final String id;
  final String pieceId;
  final String localPath;
  final String? thumbnailPath;
  final String? cloudUrl;
  final DateTime dateTaken;
  final DateTime createdAt;
  final int sortOrder;
  const Photo({
    required this.id,
    required this.pieceId,
    required this.localPath,
    this.thumbnailPath,
    this.cloudUrl,
    required this.dateTaken,
    required this.createdAt,
    required this.sortOrder,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['piece_id'] = Variable<String>(pieceId);
    map['local_path'] = Variable<String>(localPath);
    if (!nullToAbsent || thumbnailPath != null) {
      map['thumbnail_path'] = Variable<String>(thumbnailPath);
    }
    if (!nullToAbsent || cloudUrl != null) {
      map['cloud_url'] = Variable<String>(cloudUrl);
    }
    map['date_taken'] = Variable<DateTime>(dateTaken);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['sort_order'] = Variable<int>(sortOrder);
    return map;
  }

  PhotosCompanion toCompanion(bool nullToAbsent) {
    return PhotosCompanion(
      id: Value(id),
      pieceId: Value(pieceId),
      localPath: Value(localPath),
      thumbnailPath: thumbnailPath == null && nullToAbsent
          ? const Value.absent()
          : Value(thumbnailPath),
      cloudUrl: cloudUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(cloudUrl),
      dateTaken: Value(dateTaken),
      createdAt: Value(createdAt),
      sortOrder: Value(sortOrder),
    );
  }

  factory Photo.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Photo(
      id: serializer.fromJson<String>(json['id']),
      pieceId: serializer.fromJson<String>(json['pieceId']),
      localPath: serializer.fromJson<String>(json['localPath']),
      thumbnailPath: serializer.fromJson<String?>(json['thumbnailPath']),
      cloudUrl: serializer.fromJson<String?>(json['cloudUrl']),
      dateTaken: serializer.fromJson<DateTime>(json['dateTaken']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'pieceId': serializer.toJson<String>(pieceId),
      'localPath': serializer.toJson<String>(localPath),
      'thumbnailPath': serializer.toJson<String?>(thumbnailPath),
      'cloudUrl': serializer.toJson<String?>(cloudUrl),
      'dateTaken': serializer.toJson<DateTime>(dateTaken),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'sortOrder': serializer.toJson<int>(sortOrder),
    };
  }

  Photo copyWith({
    String? id,
    String? pieceId,
    String? localPath,
    Value<String?> thumbnailPath = const Value.absent(),
    Value<String?> cloudUrl = const Value.absent(),
    DateTime? dateTaken,
    DateTime? createdAt,
    int? sortOrder,
  }) => Photo(
    id: id ?? this.id,
    pieceId: pieceId ?? this.pieceId,
    localPath: localPath ?? this.localPath,
    thumbnailPath: thumbnailPath.present
        ? thumbnailPath.value
        : this.thumbnailPath,
    cloudUrl: cloudUrl.present ? cloudUrl.value : this.cloudUrl,
    dateTaken: dateTaken ?? this.dateTaken,
    createdAt: createdAt ?? this.createdAt,
    sortOrder: sortOrder ?? this.sortOrder,
  );
  Photo copyWithCompanion(PhotosCompanion data) {
    return Photo(
      id: data.id.present ? data.id.value : this.id,
      pieceId: data.pieceId.present ? data.pieceId.value : this.pieceId,
      localPath: data.localPath.present ? data.localPath.value : this.localPath,
      thumbnailPath: data.thumbnailPath.present
          ? data.thumbnailPath.value
          : this.thumbnailPath,
      cloudUrl: data.cloudUrl.present ? data.cloudUrl.value : this.cloudUrl,
      dateTaken: data.dateTaken.present ? data.dateTaken.value : this.dateTaken,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Photo(')
          ..write('id: $id, ')
          ..write('pieceId: $pieceId, ')
          ..write('localPath: $localPath, ')
          ..write('thumbnailPath: $thumbnailPath, ')
          ..write('cloudUrl: $cloudUrl, ')
          ..write('dateTaken: $dateTaken, ')
          ..write('createdAt: $createdAt, ')
          ..write('sortOrder: $sortOrder')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    pieceId,
    localPath,
    thumbnailPath,
    cloudUrl,
    dateTaken,
    createdAt,
    sortOrder,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Photo &&
          other.id == this.id &&
          other.pieceId == this.pieceId &&
          other.localPath == this.localPath &&
          other.thumbnailPath == this.thumbnailPath &&
          other.cloudUrl == this.cloudUrl &&
          other.dateTaken == this.dateTaken &&
          other.createdAt == this.createdAt &&
          other.sortOrder == this.sortOrder);
}

class PhotosCompanion extends UpdateCompanion<Photo> {
  final Value<String> id;
  final Value<String> pieceId;
  final Value<String> localPath;
  final Value<String?> thumbnailPath;
  final Value<String?> cloudUrl;
  final Value<DateTime> dateTaken;
  final Value<DateTime> createdAt;
  final Value<int> sortOrder;
  final Value<int> rowid;
  const PhotosCompanion({
    this.id = const Value.absent(),
    this.pieceId = const Value.absent(),
    this.localPath = const Value.absent(),
    this.thumbnailPath = const Value.absent(),
    this.cloudUrl = const Value.absent(),
    this.dateTaken = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PhotosCompanion.insert({
    required String id,
    required String pieceId,
    required String localPath,
    this.thumbnailPath = const Value.absent(),
    this.cloudUrl = const Value.absent(),
    required DateTime dateTaken,
    required DateTime createdAt,
    this.sortOrder = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       pieceId = Value(pieceId),
       localPath = Value(localPath),
       dateTaken = Value(dateTaken),
       createdAt = Value(createdAt);
  static Insertable<Photo> custom({
    Expression<String>? id,
    Expression<String>? pieceId,
    Expression<String>? localPath,
    Expression<String>? thumbnailPath,
    Expression<String>? cloudUrl,
    Expression<DateTime>? dateTaken,
    Expression<DateTime>? createdAt,
    Expression<int>? sortOrder,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (pieceId != null) 'piece_id': pieceId,
      if (localPath != null) 'local_path': localPath,
      if (thumbnailPath != null) 'thumbnail_path': thumbnailPath,
      if (cloudUrl != null) 'cloud_url': cloudUrl,
      if (dateTaken != null) 'date_taken': dateTaken,
      if (createdAt != null) 'created_at': createdAt,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PhotosCompanion copyWith({
    Value<String>? id,
    Value<String>? pieceId,
    Value<String>? localPath,
    Value<String?>? thumbnailPath,
    Value<String?>? cloudUrl,
    Value<DateTime>? dateTaken,
    Value<DateTime>? createdAt,
    Value<int>? sortOrder,
    Value<int>? rowid,
  }) {
    return PhotosCompanion(
      id: id ?? this.id,
      pieceId: pieceId ?? this.pieceId,
      localPath: localPath ?? this.localPath,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      cloudUrl: cloudUrl ?? this.cloudUrl,
      dateTaken: dateTaken ?? this.dateTaken,
      createdAt: createdAt ?? this.createdAt,
      sortOrder: sortOrder ?? this.sortOrder,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (pieceId.present) {
      map['piece_id'] = Variable<String>(pieceId.value);
    }
    if (localPath.present) {
      map['local_path'] = Variable<String>(localPath.value);
    }
    if (thumbnailPath.present) {
      map['thumbnail_path'] = Variable<String>(thumbnailPath.value);
    }
    if (cloudUrl.present) {
      map['cloud_url'] = Variable<String>(cloudUrl.value);
    }
    if (dateTaken.present) {
      map['date_taken'] = Variable<DateTime>(dateTaken.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PhotosCompanion(')
          ..write('id: $id, ')
          ..write('pieceId: $pieceId, ')
          ..write('localPath: $localPath, ')
          ..write('thumbnailPath: $thumbnailPath, ')
          ..write('cloudUrl: $cloudUrl, ')
          ..write('dateTaken: $dateTaken, ')
          ..write('createdAt: $createdAt, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ClayOptionsTable extends ClayOptions
    with TableInfo<$ClayOptionsTable, ClayOption> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ClayOptionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, name, sortOrder, createdAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'clay_options';
  @override
  VerificationContext validateIntegrity(
    Insertable<ClayOption> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ClayOption map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ClayOption(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $ClayOptionsTable createAlias(String alias) {
    return $ClayOptionsTable(attachedDatabase, alias);
  }
}

class ClayOption extends DataClass implements Insertable<ClayOption> {
  final String id;
  final String name;
  final int sortOrder;
  final DateTime createdAt;
  const ClayOption({
    required this.id,
    required this.name,
    required this.sortOrder,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['sort_order'] = Variable<int>(sortOrder);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  ClayOptionsCompanion toCompanion(bool nullToAbsent) {
    return ClayOptionsCompanion(
      id: Value(id),
      name: Value(name),
      sortOrder: Value(sortOrder),
      createdAt: Value(createdAt),
    );
  }

  factory ClayOption.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ClayOption(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'sortOrder': serializer.toJson<int>(sortOrder),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  ClayOption copyWith({
    String? id,
    String? name,
    int? sortOrder,
    DateTime? createdAt,
  }) => ClayOption(
    id: id ?? this.id,
    name: name ?? this.name,
    sortOrder: sortOrder ?? this.sortOrder,
    createdAt: createdAt ?? this.createdAt,
  );
  ClayOption copyWithCompanion(ClayOptionsCompanion data) {
    return ClayOption(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ClayOption(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, sortOrder, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ClayOption &&
          other.id == this.id &&
          other.name == this.name &&
          other.sortOrder == this.sortOrder &&
          other.createdAt == this.createdAt);
}

class ClayOptionsCompanion extends UpdateCompanion<ClayOption> {
  final Value<String> id;
  final Value<String> name;
  final Value<int> sortOrder;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const ClayOptionsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ClayOptionsCompanion.insert({
    required String id,
    required String name,
    this.sortOrder = const Value.absent(),
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       createdAt = Value(createdAt);
  static Insertable<ClayOption> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<int>? sortOrder,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ClayOptionsCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<int>? sortOrder,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return ClayOptionsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ClayOptionsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $PiecesTable pieces = $PiecesTable(this);
  late final $PhotosTable photos = $PhotosTable(this);
  late final $ClayOptionsTable clayOptions = $ClayOptionsTable(this);
  late final PiecesDao piecesDao = PiecesDao(this as AppDatabase);
  late final PhotosDao photosDao = PhotosDao(this as AppDatabase);
  late final MaterialsDao materialsDao = MaterialsDao(this as AppDatabase);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    pieces,
    photos,
    clayOptions,
  ];
}

typedef $$PiecesTableCreateCompanionBuilder =
    PiecesCompanion Function({
      required String id,
      Value<String?> title,
      Value<String?> stage,
      Value<String?> clayType,
      Value<String?> glazes,
      Value<String?> notes,
      Value<String?> coverPhotoId,
      Value<bool> isArchived,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$PiecesTableUpdateCompanionBuilder =
    PiecesCompanion Function({
      Value<String> id,
      Value<String?> title,
      Value<String?> stage,
      Value<String?> clayType,
      Value<String?> glazes,
      Value<String?> notes,
      Value<String?> coverPhotoId,
      Value<bool> isArchived,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

final class $$PiecesTableReferences
    extends BaseReferences<_$AppDatabase, $PiecesTable, Piece> {
  $$PiecesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$PhotosTable, List<Photo>> _photosRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.photos,
    aliasName: $_aliasNameGenerator(db.pieces.id, db.photos.pieceId),
  );

  $$PhotosTableProcessedTableManager get photosRefs {
    final manager = $$PhotosTableTableManager(
      $_db,
      $_db.photos,
    ).filter((f) => f.pieceId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_photosRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$PiecesTableFilterComposer
    extends Composer<_$AppDatabase, $PiecesTable> {
  $$PiecesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get stage => $composableBuilder(
    column: $table.stage,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get clayType => $composableBuilder(
    column: $table.clayType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get glazes => $composableBuilder(
    column: $table.glazes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get coverPhotoId => $composableBuilder(
    column: $table.coverPhotoId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isArchived => $composableBuilder(
    column: $table.isArchived,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> photosRefs(
    Expression<bool> Function($$PhotosTableFilterComposer f) f,
  ) {
    final $$PhotosTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.photos,
      getReferencedColumn: (t) => t.pieceId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PhotosTableFilterComposer(
            $db: $db,
            $table: $db.photos,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$PiecesTableOrderingComposer
    extends Composer<_$AppDatabase, $PiecesTable> {
  $$PiecesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get stage => $composableBuilder(
    column: $table.stage,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get clayType => $composableBuilder(
    column: $table.clayType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get glazes => $composableBuilder(
    column: $table.glazes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get coverPhotoId => $composableBuilder(
    column: $table.coverPhotoId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isArchived => $composableBuilder(
    column: $table.isArchived,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PiecesTableAnnotationComposer
    extends Composer<_$AppDatabase, $PiecesTable> {
  $$PiecesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get stage =>
      $composableBuilder(column: $table.stage, builder: (column) => column);

  GeneratedColumn<String> get clayType =>
      $composableBuilder(column: $table.clayType, builder: (column) => column);

  GeneratedColumn<String> get glazes =>
      $composableBuilder(column: $table.glazes, builder: (column) => column);

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<String> get coverPhotoId => $composableBuilder(
    column: $table.coverPhotoId,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isArchived => $composableBuilder(
    column: $table.isArchived,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  Expression<T> photosRefs<T extends Object>(
    Expression<T> Function($$PhotosTableAnnotationComposer a) f,
  ) {
    final $$PhotosTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.photos,
      getReferencedColumn: (t) => t.pieceId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PhotosTableAnnotationComposer(
            $db: $db,
            $table: $db.photos,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$PiecesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PiecesTable,
          Piece,
          $$PiecesTableFilterComposer,
          $$PiecesTableOrderingComposer,
          $$PiecesTableAnnotationComposer,
          $$PiecesTableCreateCompanionBuilder,
          $$PiecesTableUpdateCompanionBuilder,
          (Piece, $$PiecesTableReferences),
          Piece,
          PrefetchHooks Function({bool photosRefs})
        > {
  $$PiecesTableTableManager(_$AppDatabase db, $PiecesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PiecesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PiecesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PiecesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String?> title = const Value.absent(),
                Value<String?> stage = const Value.absent(),
                Value<String?> clayType = const Value.absent(),
                Value<String?> glazes = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<String?> coverPhotoId = const Value.absent(),
                Value<bool> isArchived = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PiecesCompanion(
                id: id,
                title: title,
                stage: stage,
                clayType: clayType,
                glazes: glazes,
                notes: notes,
                coverPhotoId: coverPhotoId,
                isArchived: isArchived,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<String?> title = const Value.absent(),
                Value<String?> stage = const Value.absent(),
                Value<String?> clayType = const Value.absent(),
                Value<String?> glazes = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<String?> coverPhotoId = const Value.absent(),
                Value<bool> isArchived = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => PiecesCompanion.insert(
                id: id,
                title: title,
                stage: stage,
                clayType: clayType,
                glazes: glazes,
                notes: notes,
                coverPhotoId: coverPhotoId,
                isArchived: isArchived,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) =>
                    (e.readTable(table), $$PiecesTableReferences(db, table, e)),
              )
              .toList(),
          prefetchHooksCallback: ({photosRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (photosRefs) db.photos],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (photosRefs)
                    await $_getPrefetchedData<Piece, $PiecesTable, Photo>(
                      currentTable: table,
                      referencedTable: $$PiecesTableReferences._photosRefsTable(
                        db,
                      ),
                      managerFromTypedResult: (p0) =>
                          $$PiecesTableReferences(db, table, p0).photosRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.pieceId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$PiecesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PiecesTable,
      Piece,
      $$PiecesTableFilterComposer,
      $$PiecesTableOrderingComposer,
      $$PiecesTableAnnotationComposer,
      $$PiecesTableCreateCompanionBuilder,
      $$PiecesTableUpdateCompanionBuilder,
      (Piece, $$PiecesTableReferences),
      Piece,
      PrefetchHooks Function({bool photosRefs})
    >;
typedef $$PhotosTableCreateCompanionBuilder =
    PhotosCompanion Function({
      required String id,
      required String pieceId,
      required String localPath,
      Value<String?> thumbnailPath,
      Value<String?> cloudUrl,
      required DateTime dateTaken,
      required DateTime createdAt,
      Value<int> sortOrder,
      Value<int> rowid,
    });
typedef $$PhotosTableUpdateCompanionBuilder =
    PhotosCompanion Function({
      Value<String> id,
      Value<String> pieceId,
      Value<String> localPath,
      Value<String?> thumbnailPath,
      Value<String?> cloudUrl,
      Value<DateTime> dateTaken,
      Value<DateTime> createdAt,
      Value<int> sortOrder,
      Value<int> rowid,
    });

final class $$PhotosTableReferences
    extends BaseReferences<_$AppDatabase, $PhotosTable, Photo> {
  $$PhotosTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $PiecesTable _pieceIdTable(_$AppDatabase db) => db.pieces.createAlias(
    $_aliasNameGenerator(db.photos.pieceId, db.pieces.id),
  );

  $$PiecesTableProcessedTableManager get pieceId {
    final $_column = $_itemColumn<String>('piece_id')!;

    final manager = $$PiecesTableTableManager(
      $_db,
      $_db.pieces,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_pieceIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$PhotosTableFilterComposer
    extends Composer<_$AppDatabase, $PhotosTable> {
  $$PhotosTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get localPath => $composableBuilder(
    column: $table.localPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get thumbnailPath => $composableBuilder(
    column: $table.thumbnailPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cloudUrl => $composableBuilder(
    column: $table.cloudUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get dateTaken => $composableBuilder(
    column: $table.dateTaken,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );

  $$PiecesTableFilterComposer get pieceId {
    final $$PiecesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.pieceId,
      referencedTable: $db.pieces,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PiecesTableFilterComposer(
            $db: $db,
            $table: $db.pieces,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PhotosTableOrderingComposer
    extends Composer<_$AppDatabase, $PhotosTable> {
  $$PhotosTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get localPath => $composableBuilder(
    column: $table.localPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get thumbnailPath => $composableBuilder(
    column: $table.thumbnailPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cloudUrl => $composableBuilder(
    column: $table.cloudUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get dateTaken => $composableBuilder(
    column: $table.dateTaken,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );

  $$PiecesTableOrderingComposer get pieceId {
    final $$PiecesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.pieceId,
      referencedTable: $db.pieces,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PiecesTableOrderingComposer(
            $db: $db,
            $table: $db.pieces,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PhotosTableAnnotationComposer
    extends Composer<_$AppDatabase, $PhotosTable> {
  $$PhotosTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get localPath =>
      $composableBuilder(column: $table.localPath, builder: (column) => column);

  GeneratedColumn<String> get thumbnailPath => $composableBuilder(
    column: $table.thumbnailPath,
    builder: (column) => column,
  );

  GeneratedColumn<String> get cloudUrl =>
      $composableBuilder(column: $table.cloudUrl, builder: (column) => column);

  GeneratedColumn<DateTime> get dateTaken =>
      $composableBuilder(column: $table.dateTaken, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  $$PiecesTableAnnotationComposer get pieceId {
    final $$PiecesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.pieceId,
      referencedTable: $db.pieces,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PiecesTableAnnotationComposer(
            $db: $db,
            $table: $db.pieces,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PhotosTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PhotosTable,
          Photo,
          $$PhotosTableFilterComposer,
          $$PhotosTableOrderingComposer,
          $$PhotosTableAnnotationComposer,
          $$PhotosTableCreateCompanionBuilder,
          $$PhotosTableUpdateCompanionBuilder,
          (Photo, $$PhotosTableReferences),
          Photo,
          PrefetchHooks Function({bool pieceId})
        > {
  $$PhotosTableTableManager(_$AppDatabase db, $PhotosTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PhotosTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PhotosTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PhotosTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> pieceId = const Value.absent(),
                Value<String> localPath = const Value.absent(),
                Value<String?> thumbnailPath = const Value.absent(),
                Value<String?> cloudUrl = const Value.absent(),
                Value<DateTime> dateTaken = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PhotosCompanion(
                id: id,
                pieceId: pieceId,
                localPath: localPath,
                thumbnailPath: thumbnailPath,
                cloudUrl: cloudUrl,
                dateTaken: dateTaken,
                createdAt: createdAt,
                sortOrder: sortOrder,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String pieceId,
                required String localPath,
                Value<String?> thumbnailPath = const Value.absent(),
                Value<String?> cloudUrl = const Value.absent(),
                required DateTime dateTaken,
                required DateTime createdAt,
                Value<int> sortOrder = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PhotosCompanion.insert(
                id: id,
                pieceId: pieceId,
                localPath: localPath,
                thumbnailPath: thumbnailPath,
                cloudUrl: cloudUrl,
                dateTaken: dateTaken,
                createdAt: createdAt,
                sortOrder: sortOrder,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) =>
                    (e.readTable(table), $$PhotosTableReferences(db, table, e)),
              )
              .toList(),
          prefetchHooksCallback: ({pieceId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (pieceId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.pieceId,
                                referencedTable: $$PhotosTableReferences
                                    ._pieceIdTable(db),
                                referencedColumn: $$PhotosTableReferences
                                    ._pieceIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$PhotosTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PhotosTable,
      Photo,
      $$PhotosTableFilterComposer,
      $$PhotosTableOrderingComposer,
      $$PhotosTableAnnotationComposer,
      $$PhotosTableCreateCompanionBuilder,
      $$PhotosTableUpdateCompanionBuilder,
      (Photo, $$PhotosTableReferences),
      Photo,
      PrefetchHooks Function({bool pieceId})
    >;
typedef $$ClayOptionsTableCreateCompanionBuilder =
    ClayOptionsCompanion Function({
      required String id,
      required String name,
      Value<int> sortOrder,
      required DateTime createdAt,
      Value<int> rowid,
    });
typedef $$ClayOptionsTableUpdateCompanionBuilder =
    ClayOptionsCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<int> sortOrder,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

class $$ClayOptionsTableFilterComposer
    extends Composer<_$AppDatabase, $ClayOptionsTable> {
  $$ClayOptionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ClayOptionsTableOrderingComposer
    extends Composer<_$AppDatabase, $ClayOptionsTable> {
  $$ClayOptionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ClayOptionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ClayOptionsTable> {
  $$ClayOptionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$ClayOptionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ClayOptionsTable,
          ClayOption,
          $$ClayOptionsTableFilterComposer,
          $$ClayOptionsTableOrderingComposer,
          $$ClayOptionsTableAnnotationComposer,
          $$ClayOptionsTableCreateCompanionBuilder,
          $$ClayOptionsTableUpdateCompanionBuilder,
          (
            ClayOption,
            BaseReferences<_$AppDatabase, $ClayOptionsTable, ClayOption>,
          ),
          ClayOption,
          PrefetchHooks Function()
        > {
  $$ClayOptionsTableTableManager(_$AppDatabase db, $ClayOptionsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ClayOptionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ClayOptionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ClayOptionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ClayOptionsCompanion(
                id: id,
                name: name,
                sortOrder: sortOrder,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                Value<int> sortOrder = const Value.absent(),
                required DateTime createdAt,
                Value<int> rowid = const Value.absent(),
              }) => ClayOptionsCompanion.insert(
                id: id,
                name: name,
                sortOrder: sortOrder,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ClayOptionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ClayOptionsTable,
      ClayOption,
      $$ClayOptionsTableFilterComposer,
      $$ClayOptionsTableOrderingComposer,
      $$ClayOptionsTableAnnotationComposer,
      $$ClayOptionsTableCreateCompanionBuilder,
      $$ClayOptionsTableUpdateCompanionBuilder,
      (
        ClayOption,
        BaseReferences<_$AppDatabase, $ClayOptionsTable, ClayOption>,
      ),
      ClayOption,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$PiecesTableTableManager get pieces =>
      $$PiecesTableTableManager(_db, _db.pieces);
  $$PhotosTableTableManager get photos =>
      $$PhotosTableTableManager(_db, _db.photos);
  $$ClayOptionsTableTableManager get clayOptions =>
      $$ClayOptionsTableTableManager(_db, _db.clayOptions);
}
