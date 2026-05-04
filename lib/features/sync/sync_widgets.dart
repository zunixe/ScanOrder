import 'package:flutter/material.dart';

import '../../core/offline/offline.dart';

/// Widget untuk menampilkan status sync dan konflik
class SyncStatusWidget extends StatelessWidget {
  final Stream<SyncQueueStatus>? statusStream;
  final Stream<SyncItemProgress>? progressStream;
  final VoidCallback? onRetry;
  final Function(String itemId, bool useLocalVersion)? onResolveConflict;

  const SyncStatusWidget({
    super.key,
    this.statusStream,
    this.progressStream,
    this.onRetry,
    this.onResolveConflict,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SyncQueueStatus>(
      stream: statusStream,
      initialData: SyncQueueStatus.idle,
      builder: (context, statusSnapshot) {
        final status = statusSnapshot.data ?? SyncQueueStatus.idle;

        if (status == SyncQueueStatus.idle) {
          return const SizedBox.shrink();
        }

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: _getStatusColor(status).withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              _buildStatusIcon(status),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _getStatusText(status),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: _getStatusColor(status),
                      ),
                    ),
                    if (status == SyncQueueStatus.syncing) ...[
                      const SizedBox(height: 4),
                      StreamBuilder<SyncItemProgress>(
                        stream: progressStream,
                        builder: (context, progressSnapshot) {
                          final progress = progressSnapshot.data;
                          if (progress == null) {
                            return const SizedBox.shrink();
                          }
                          return Text(
                            progress.message ?? 'Syncing...',
                            style: Theme.of(context).textTheme.bodySmall,
                          );
                        },
                      ),
                    ],
                  ],
                ),
              ),
              if (status == SyncQueueStatus.error || 
                  status == SyncQueueStatus.pending) ...[
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: onRetry,
                  tooltip: 'Retry Sync',
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatusIcon(SyncQueueStatus status) {
    switch (status) {
      case SyncQueueStatus.idle:
        return const Icon(Icons.cloud_done, size: 24);
      case SyncQueueStatus.syncing:
        return const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case SyncQueueStatus.pending:
        return const Icon(Icons.cloud_queue, size: 24);
      case SyncQueueStatus.error:
        return const Icon(Icons.cloud_off, size: 24, color: Colors.red);
    }
  }

  String _getStatusText(SyncQueueStatus status) {
    switch (status) {
      case SyncQueueStatus.idle:
        return 'Semua data tersinkronisasi';
      case SyncQueueStatus.syncing:
        return 'Menyinkronkan data...';
      case SyncQueueStatus.pending:
        return 'Menunggu sinkronisasi';
      case SyncQueueStatus.error:
        return 'Sinkronisasi gagal';
    }
  }

  Color _getStatusColor(SyncQueueStatus status) {
    switch (status) {
      case SyncQueueStatus.idle:
        return Colors.green;
      case SyncQueueStatus.syncing:
        return Colors.blue;
      case SyncQueueStatus.pending:
        return Colors.orange;
      case SyncQueueStatus.error:
        return Colors.red;
    }
  }
}

/// Dialog untuk resolusi konflik manual
class ConflictResolutionDialog extends StatefulWidget {
  final String itemId;
  final String tableName;
  final String recordId;
  final Map<String, dynamic> localData;
  final Map<String, dynamic> serverData;
  final DateTime localUpdatedAt;
  final DateTime serverUpdatedAt;

  const ConflictResolutionDialog({
    super.key,
    required this.itemId,
    required this.tableName,
    required this.recordId,
    required this.localData,
    required this.serverData,
    required this.localUpdatedAt,
    required this.serverUpdatedAt,
  });

  @override
  State<ConflictResolutionDialog> createState() =>
      _ConflictResolutionDialogState();
}

class _ConflictResolutionDialogState extends State<ConflictResolutionDialog> {
  ConflictResolutionOption _selectedOption = ConflictResolutionOption.local;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Konflik Data Terdeteksi'),
      content: SingleChildScrollView(
        scrollDirection: Axis.vertical,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Terjadi perbedaan antara data lokal dan server untuk ${widget.tableName}.${widget.recordId}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            _buildComparisonCard(),
            const SizedBox(height: 16),
            _buildResolutionOptions(),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        ElevatedButton(
          onPressed: _resolveConflict,
          child: const Text('Simpan Pilihan'),
        ),
      ],
    );
  }

  Widget _buildComparisonCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            _buildDataColumn(
              title: 'Data Lokal',
              data: widget.localData,
              updatedAt: widget.localUpdatedAt,
              isSelected: _selectedOption == ConflictResolutionOption.local,
            ),
            const Divider(),
            _buildDataColumn(
              title: 'Data Server',
              data: widget.serverData,
              updatedAt: widget.serverUpdatedAt,
              isSelected: _selectedOption == ConflictResolutionOption.server,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDataColumn({
    required String title,
    required Map<String, dynamic> data,
    required DateTime updatedAt,
    required bool isSelected,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isSelected ? Colors.blue : null,
                ),
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_circle, color: Colors.blue, size: 20),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Diperbarui: ${_formatDateTime(updatedAt)}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            _formatDataPreview(data),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }

  Widget _buildResolutionOptions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Pilih versi yang akan digunakan:',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        RadioListTile<ConflictResolutionOption>(
          title: const Text('Gunakan Data Lokal'),
          subtitle: const Text('Data dari perangkat Anda akan menggantikan data server'),
          value: ConflictResolutionOption.local,
          groupValue: _selectedOption,
          onChanged: (value) {
            setState(() {
              _selectedOption = value!;
            });
          },
        ),
        RadioListTile<ConflictResolutionOption>(
          title: const Text('Gunakan Data Server'),
          subtitle: const Text('Data dari server akan menggantikan data lokal'),
          value: ConflictResolutionOption.server,
          groupValue: _selectedOption,
          onChanged: (value) {
            setState(() {
              _selectedOption = value!;
            });
          },
        ),
        RadioListTile<ConflictResolutionOption>(
          title: const Text('Gabungkan Secara Manual'),
          subtitle: const Text('Edit data sebelum menyimpan'),
          value: ConflictResolutionOption.merge,
          groupValue: _selectedOption,
          onChanged: (value) {
            setState(() {
              _selectedOption = value!;
            });
          },
        ),
      ],
    );
  }

  void _resolveConflict() {
    if (widget.onResolveConflict != null) {
      final useLocal = _selectedOption == ConflictResolutionOption.local;
      widget.onResolveConflict!(widget.itemId, useLocal);
    }
    Navigator.pop(context);
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
  }

  String _formatDataPreview(Map<String, dynamic> data) {
    final entries = data.entries.take(5).map((e) => '${e.key}: ${e.value}');
    return entries.join('\n');
  }
}

enum ConflictResolutionOption {
  local,
  server,
  merge,
}

/// Widget badge untuk menampilkan jumlah item yang pending sync
class SyncPendingBadge extends StatelessWidget {
  final int count;
  final VoidCallback? onTap;

  const SyncPendingBadge({
    super.key,
    required this.count,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (count <= 0) {
      return const SizedBox.shrink();
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.orange,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_upload, size: 14, color: Colors.white),
            const SizedBox(width: 4),
            Text(
              '$count',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
