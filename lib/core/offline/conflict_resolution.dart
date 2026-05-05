import 'dart:async';
import 'dart:math';

import 'package:meta/meta.dart';

/// Strategy interface for resolving conflicts between local and server data
abstract class ConflictResolutionStrategy {
  /// Resolve conflict between local and server versions
  /// Returns true if local version should win, false if server version should win
  Future<bool> resolveConflict({
    required String tableName,
    required String recordId,
    required Map<String, dynamic> localData,
    required Map<String, dynamic> serverData,
    required int localVersion,
    required int serverVersion,
    required DateTime localUpdatedAt,
    required DateTime serverUpdatedAt,
  });

  /// Get the merged data after conflict resolution
  Future<Map<String, dynamic>> mergeData({
    required Map<String, dynamic> localData,
    required Map<String, dynamic> serverData,
    required bool localWins,
  });
}

/// Last Write Wins strategy - uses the most recently updated version
class LastWriteWinsStrategy implements ConflictResolutionStrategy {
  @override
  Future<bool> resolveConflict({
    required String tableName,
    required String recordId,
    required Map<String, dynamic> localData,
    required Map<String, dynamic> serverData,
    required int localVersion,
    required int serverVersion,
    required DateTime localUpdatedAt,
    required DateTime serverUpdatedAt,
  }) async {
    // Compare timestamps to determine which is more recent
    return localUpdatedAt.isAfter(serverUpdatedAt);
  }

  @override
  Future<Map<String, dynamic>> mergeData({
    required Map<String, dynamic> localData,
    required Map<String, dynamic> serverData,
    required bool localWins,
  }) async {
    // Simply return the winning version
    return localWins ? localData : serverData;
  }
}

/// Server Wins strategy - always prefers server version
class ServerWinsStrategy implements ConflictResolutionStrategy {
  @override
  Future<bool> resolveConflict({
    required String tableName,
    required String recordId,
    required Map<String, dynamic> localData,
    required Map<String, dynamic> serverData,
    required int localVersion,
    required int serverVersion,
    required DateTime localUpdatedAt,
    required DateTime serverUpdatedAt,
  }) async {
    // Server always wins
    return false;
  }

  @override
  Future<Map<String, dynamic>> mergeData({
    required Map<String, dynamic> localData,
    required Map<String, dynamic> serverData,
    required bool localWins,
  }) async {
    // Return server data
    return serverData;
  }
}

/// Manual Resolution Strategy - requires user intervention
/// This strategy throws an exception that should be caught and handled by UI
class ManualResolutionStrategy implements ConflictResolutionStrategy {
  @override
  Future<bool> resolveConflict({
    required String tableName,
    required String recordId,
    required Map<String, dynamic> localData,
    required Map<String, dynamic> serverData,
    required int localVersion,
    required int serverVersion,
    required DateTime localUpdatedAt,
    required DateTime serverUpdatedAt,
  }) async {
    throw ConflictRequiresManualResolutionException(
      tableName: tableName,
      recordId: recordId,
      localData: localData,
      serverData: serverData,
      localVersion: localVersion,
      serverVersion: serverVersion,
      localUpdatedAt: localUpdatedAt,
      serverUpdatedAt: serverUpdatedAt,
    );
  }

  @override
  Future<Map<String, dynamic>> mergeData({
    required Map<String, dynamic> localData,
    required Map<String, dynamic> serverData,
    required bool localWins,
  }) async {
    return localWins ? localData : serverData;
  }
}

/// Smart Merge Strategy - attempts to merge fields intelligently
class SmartMergeStrategy implements ConflictResolutionStrategy {
  final List<String> priorityFields; // Fields where local always wins

  SmartMergeStrategy({this.priorityFields = const ['status', 'notes']});

  @override
  Future<bool> resolveConflict({
    required String tableName,
    required String recordId,
    required Map<String, dynamic> localData,
    required Map<String, dynamic> serverData,
    required int localVersion,
    required int serverVersion,
    required DateTime localUpdatedAt,
    required DateTime serverUpdatedAt,
  }) async {
    // Check if there are actual conflicts in non-priority fields
    final conflicts = _findConflicts(localData, serverData);
    
    if (conflicts.isEmpty) {
      // No real conflicts, can merge safely
      return true;
    }

    // If conflicts only in priority fields, local wins
    final hasNonPriorityConflicts = conflicts.any(
      (field) => !priorityFields.contains(field),
    );

    if (!hasNonPriorityConflicts) {
      return true;
    }

    // For other conflicts, use last-write-wins
    return localUpdatedAt.isAfter(serverUpdatedAt);
  }

  @override
  Future<Map<String, dynamic>> mergeData({
    required Map<String, dynamic> localData,
    required Map<String, dynamic> serverData,
    required bool localWins,
  }) async {
    if (localWins) {
      // Start with server data and overlay priority fields from local
      final merged = Map<String, dynamic>.from(serverData);
      for (final field in priorityFields) {
        if (localData.containsKey(field)) {
          merged[field] = localData[field];
        }
      }
      return merged;
    } else {
      // Server wins, but keep local priority fields
      final merged = Map<String, dynamic>.from(localData);
      for (final field in serverData.keys) {
        if (!priorityFields.contains(field)) {
          merged[field] = serverData[field];
        }
      }
      return merged;
    }
  }

  List<String> _findConflicts(
    Map<String, dynamic> localData,
    Map<String, dynamic> serverData,
  ) {
    final conflicts = <String>[];
    
    for (final key in localData.keys) {
      if (serverData.containsKey(key)) {
        if (localData[key] != serverData[key]) {
          conflicts.add(key);
        }
      }
    }
    
    return conflicts;
  }
}

/// Exception thrown when manual conflict resolution is required
@immutable
class ConflictRequiresManualResolutionException implements Exception {
  final String tableName;
  final String recordId;
  final Map<String, dynamic> localData;
  final Map<String, dynamic> serverData;
  final int localVersion;
  final int serverVersion;
  final DateTime localUpdatedAt;
  final DateTime serverUpdatedAt;

  const ConflictRequiresManualResolutionException({
    required this.tableName,
    required this.recordId,
    required this.localData,
    required this.serverData,
    required this.localVersion,
    required this.serverVersion,
    required this.localUpdatedAt,
    required this.serverUpdatedAt,
  });

  @override
  String toString() {
    return 'ConflictRequiresManualResolutionException: '
        'Conflict detected for $tableName.$recordId. '
        'Local version: $localVersion, Server version: $serverVersion. '
        'Local updated: $localUpdatedAt, Server updated: $serverUpdatedAt';
  }
}

/// Configuration for conflict resolution per table
class ConflictResolutionConfig {
  final String tableName;
  final ConflictResolutionStrategy strategy;
  final Duration autoResolveTimeout; // How long to wait for manual resolution

  const ConflictResolutionConfig({
    required this.tableName,
    required this.strategy,
    this.autoResolveTimeout = const Duration(hours: 24),
  });
}
