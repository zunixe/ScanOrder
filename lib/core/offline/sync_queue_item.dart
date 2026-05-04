import 'package:equatable/equatable.dart';

enum SyncOperationType {
  create,
  update,
  delete,
}

enum SyncStatus {
  pending,
  syncing,
  completed,
  failed,
  conflict,
}

class SyncQueueItem extends Equatable {
  final String id;
  final String tableName;
  final String recordId;
  final SyncOperationType operationType;
  final Map<String, dynamic> payload;
  final SyncStatus status;
  final int retryCount;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final DateTime? lastAttemptAt;
  final String? errorMessage;
  final int? serverVersion;
  final int? localVersion;

  const SyncQueueItem({
    required this.id,
    required this.tableName,
    required this.recordId,
    required this.operationType,
    required this.payload,
    this.status = SyncStatus.pending,
    this.retryCount = 0,
    required this.createdAt,
    this.updatedAt,
    this.lastAttemptAt,
    this.errorMessage,
    this.serverVersion,
    this.localVersion,
  });

  SyncQueueItem copyWith({
    String? id,
    String? tableName,
    String? recordId,
    SyncOperationType? operationType,
    Map<String, dynamic>? payload,
    SyncStatus? status,
    int? retryCount,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? lastAttemptAt,
    String? errorMessage,
    int? serverVersion,
    int? localVersion,
  }) {
    return SyncQueueItem(
      id: id ?? this.id,
      tableName: tableName ?? this.tableName,
      recordId: recordId ?? this.recordId,
      operationType: operationType ?? this.operationType,
      payload: payload ?? this.payload,
      status: status ?? this.status,
      retryCount: retryCount ?? this.retryCount,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
      errorMessage: errorMessage ?? this.errorMessage,
      serverVersion: serverVersion ?? this.serverVersion,
      localVersion: localVersion ?? this.localVersion,
    );
  }

  @override
  List<Object?> get props => [
        id,
        tableName,
        recordId,
        operationType,
        payload,
        status,
        retryCount,
        createdAt,
        updatedAt,
        lastAttemptAt,
        errorMessage,
        serverVersion,
        localVersion,
      ];

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'table_name': tableName,
      'record_id': recordId,
      'operation_type': operationType.index,
      'payload': payload,
      'status': status.index,
      'retry_count': retryCount,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
      'last_attempt_at': lastAttemptAt?.toIso8601String(),
      'error_message': errorMessage,
      'server_version': serverVersion,
      'local_version': localVersion,
    };
  }

  factory SyncQueueItem.fromMap(Map<String, dynamic> map) {
    return SyncQueueItem(
      id: map['id'] as String,
      tableName: map['table_name'] as String,
      recordId: map['record_id'] as String,
      operationType: SyncOperationType.values[map['operation_type'] as int],
      payload: Map<String, dynamic>.from(map['payload'] as Map),
      status: SyncStatus.values[map['status'] as int],
      retryCount: map['retry_count'] as int? ?? 0,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: map['updated_at'] != null
          ? DateTime.parse(map['updated_at'] as String)
          : null,
      lastAttemptAt: map['last_attempt_at'] != null
          ? DateTime.parse(map['last_attempt_at'] as String)
          : null,
      errorMessage: map['error_message'] as String?,
      serverVersion: map['server_version'] as int?,
      localVersion: map['local_version'] as int?,
    );
  }
}
