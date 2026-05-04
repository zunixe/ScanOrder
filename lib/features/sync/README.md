# Offline-First Architecture Implementation

## 📋 Overview

Implementasi lengkap untuk offline-first architecture dengan fitur:
- ✅ Enhanced sync queue mechanism
- ✅ Conflict resolution strategies
- ✅ Exponential backoff retry

## 🏗️ Architecture

```
lib/core/offline/
├── sync_queue_item.dart          # Model untuk item antrian sync
├── conflict_resolution.dart      # Strategi resolusi konflik
├── exponential_backoff.dart      # Mekanisme retry dengan backoff
├── sync_queue_manager.dart       # Manager utama sync queue
└── offline.dart                  # Export barrel file

lib/features/sync/
├── sync_widgets.dart             # UI widgets untuk sync status
└── README.md                     # Dokumentasi ini
```

## 🚀 Cara Penggunaan

### 1. Inisialisasi SyncQueueManager

```dart
import 'package:scanorder/core/offline/offline.dart';

// Inisialisasi database
final db = await openDatabase('app.db');

// Buat instance manager
final syncManager = SyncQueueManager(
  database: db,
  defaultStrategy: LastWriteWinsStrategy(), // atau strategi lain
  tableConfigs: {
    'orders': ConflictResolutionConfig(
      tableName: 'orders',
      strategy: SmartMergeStrategy(priorityFields: ['status', 'notes']),
    ),
    'customers': ConflictResolutionConfig(
      tableName: 'customers',
      strategy: ServerWinsStrategy(),
    ),
  },
);

// Mulai auto-sync (opsional)
syncManager.startAutoSync(Duration(minutes: 5));
```

### 2. Menambahkan Item ke Queue

```dart
// Saat membuat data baru (offline)
await syncManager.addToQueue(
  tableName: 'orders',
  recordId: 'order_123',
  operationType: SyncOperationType.create,
  payload: {
    'customer_name': 'John Doe',
    'items': [...],
    'total': 100000,
  },
  localVersion: 1,
);

// Saat update data
await syncManager.addToQueue(
  tableName: 'orders',
  recordId: 'order_123',
  operationType: SyncOperationType.update,
  payload: {'status': 'completed'},
  localVersion: 2,
);

// Saat delete data
await syncManager.addToQueue(
  tableName: 'orders',
  recordId: 'order_123',
  operationType: SyncOperationType.delete,
  payload: {},
);
```

### 3. Monitoring Status Sync

```dart
// Subscribe ke status stream
syncManager.syncStatusStream.listen((status) {
  switch (status) {
    case SyncQueueStatus.idle:
      print('✅ Semua data tersinkronisasi');
      break;
    case SyncQueueStatus.syncing:
      print('🔄 Menyinkronkan data...');
      break;
    case SyncQueueStatus.pending:
      print('⏳ Menunggu sinkronisasi');
      break;
    case SyncQueueStatus.error:
      print('❌ Sinkronisasi gagal');
      break;
  }
});

// Monitor progress per item
syncManager.itemProgressStream.listen((progress) {
  print('Item ${progress.itemId}: ${progress.status} - ${progress.message}');
});
```

### 4. Menampilkan UI Sync Status

```dart
import 'package:scanorder/features/sync/sync_widgets.dart';

// Widget status sync
SyncStatusWidget(
  statusStream: syncManager.syncStatusStream,
  progressStream: syncManager.itemProgressStream,
  onRetry: () => syncManager.processQueue(),
)

// Badge untuk pending items
FutureBuilder<SyncQueueStats>(
  future: syncManager.getStats(),
  builder: (context, snapshot) {
    final stats = snapshot.data ?? SyncQueueStats.empty;
    return SyncPendingBadge(
      count: stats.pending,
      onTap: () => _showSyncDetails(context),
    );
  },
)
```

### 5. Resolusi Konflik Manual

```dart
// Ketika terjadi konflik, dialog akan muncul
void showConflictDialog(SyncQueueItem item, Exception exception) {
  if (exception is ConflictRequiresManualResolutionException) {
    showDialog(
      context: context,
      builder: (context) => ConflictResolutionDialog(
        itemId: item.id,
        tableName: item.tableName,
        recordId: item.recordId,
        localData: item.payload,
        serverData: exception.serverData,
        localUpdatedAt: exception.localUpdatedAt,
        serverUpdatedAt: exception.serverUpdatedAt,
        onResolveConflict: (itemId, useLocal) async {
          await syncManager.resolveConflict(
            itemId: itemId,
            useLocalVersion: useLocal,
          );
        },
      ),
    );
  }
}
```

## 🎯 Conflict Resolution Strategies

### 1. Last Write Wins (Default)
Memilih versi yang paling terakhir diupdate berdasarkan timestamp.

```dart
LastWriteWinsStrategy()
```

### 2. Server Wins
Selalu menggunakan versi dari server.

```dart
ServerWinsStrategy()
```

### 3. Manual Resolution
Memerlukan intervensi user untuk memilih versi.

```dart
ManualResolutionStrategy()
```

### 4. Smart Merge
Menggabungkan data secara cerdas dengan prioritas field tertentu.

```dart
SmartMergeStrategy(
  priorityFields: ['status', 'notes'], // Field yang selalu menang dari lokal
)
```

## ⏱️ Exponential Backoff Configuration

### Default Configuration

```dart
const SyncRetryConfig(
  syncPolicy: RetryPolicy(
    type: RetryPolicyType.exponentialBackoff,
    maxRetries: 5,
    baseDelay: Duration(seconds: 2),
    maxDelay: Duration(minutes: 10),
  ),
)
```

### Retry Delay Calculation

| Attempt | Delay (seconds) |
|---------|----------------|
| 1       | 2s + jitter     |
| 2       | 4s + jitter     |
| 3       | 8s + jitter     |
| 4       | 16s + jitter    |
| 5       | 32s + jitter    |
| Max     | 10 minutes      |

*Jitter ditambahkan secara acak (±20%) untuk mencegah thundering herd problem.*

### Network-Aware Retry

```dart
// Adaptif berdasarkan jenis koneksi
final policy = NetworkAwareRetryPolicy.fromConnectionType(
  isMobileConnection: true, // Lebih lama delay untuk mobile
);
```

## 📊 Statistics & Monitoring

```dart
// Dapatkan statistik queue
final stats = await syncManager.getStats();

print('Total: ${stats.total}');
print('Pending: ${stats.pending}');
print('Failed: ${stats.failed}');
print('Conflicts: ${stats.conflict}');
print('Success Rate: ${(stats.successRate * 100).toStringAsFixed(1)}%');
```

## 🔧 Best Practices

### 1. Error Handling
```dart
try {
  await syncManager.addToQueue(...);
} catch (e) {
  // Log error dan tampilkan pesan ke user
  logger.e('Failed to add to sync queue', error: e);
  showErrorSnackBar('Gagal menyimpan data. Data akan disinkronkan nanti.');
}
```

### 2. Cleanup Completed Items
```dart
// Bersihkan item yang sudah selesai secara berkala
await syncManager.clearCompleted();
```

### 3. Connection Awareness
```dart
// Hanya sync saat ada koneksi
connectivity.onConnectivityChanged.listen((result) {
  if (result != ConnectivityResult.none) {
    syncManager.processQueue();
  }
});
```

### 4. User Feedback
```dart
// Berikan feedback visual ke user
StreamBuilder<SyncQueueStatus>(
  stream: syncManager.syncStatusStream,
  builder: (context, snapshot) {
    final status = snapshot.data ?? SyncQueueStatus.idle;
    
    if (status == SyncQueueStatus.pending) {
      return SyncPendingBadge(count: pendingCount);
    }
    
    return SizedBox.shrink();
  },
)
```

## 🧪 Testing

```dart
test('SyncQueueManager should process pending items', () async {
  final manager = SyncQueueManager(database: testDb);
  
  // Add item to queue
  await manager.addToQueue(
    tableName: 'test_table',
    recordId: 'test_1',
    operationType: SyncOperationType.create,
    payload: {'name': 'Test'},
  );
  
  // Process queue
  await manager.processQueue();
  
  // Verify stats
  final stats = await manager.getStats();
  expect(stats.completed, equals(1));
});
```

## 📝 Migration Notes

Jika Anda sudah memiliki sync queue yang lama:

1. Backup data lama
2. Jalankan migration schema
3. Test dengan data sample
4. Deploy ke production

## 🔗 Related Files

- `lib/core/database/database_helper.dart` - Database helper
- `lib/core/network/api_client.dart` - API client untuk sync
- `lib/core/connectivity/connectivity_service.dart` - Connectivity monitoring

## 📚 Resources

- [Offline-First Design](https://developer.android.com/topic/architecture/data-layer/offline-first)
- [Exponential Backoff](https://aws.amazon.com/id/blogs/architecture/exponential-backoff-and-jitter/)
- [Conflict Resolution Patterns](https://martinfowler.com/articles/patterns-of-distributed-systems/conflict-resolution.html)
