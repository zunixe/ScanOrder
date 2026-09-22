import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import 'admin_provider.dart';

/// Daftar pendaftar yang menunggu persetujuan admin.
/// Approve → user bisa login; Reject → user ditolak (dengan alasan opsional).
class ApprovalsScreen extends StatefulWidget {
  const ApprovalsScreen({super.key});

  @override
  State<ApprovalsScreen> createState() => _ApprovalsScreenState();
}

class _ApprovalsScreenState extends State<ApprovalsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AdminProvider>().fetchPendingApprovals();
    });
  }

  Future<void> _decide(AdminProvider admin, Map<String, dynamic> row, String action) async {
    final email = (row['email'] as String?) ?? '(tanpa email)';
    final userId = row['user_id'] as String;

    // Konfirmasi
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(action == 'approved' ? 'Setujui pendaftar?' : 'Tolak pendaftar?'),
        content: Text(action == 'approved'
            ? 'Akun $email akan diizinkan login.'
            : 'Akun $email tidak akan diizinkan login.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: action == 'approved'
                ? null
                : FilledButton.styleFrom(backgroundColor: AppTheme.dangerColor),
            child: Text(action == 'approved' ? 'Setujui' : 'Tolak'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    // Minta alasan saat menolak (opsional)
    String? note;
    if (action == 'rejected') {
      final controller = TextEditingController();
      note = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Alasan penolakan (opsional)'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'Contoh: email tidak valid…',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Lewati')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim().isEmpty ? null : controller.text.trim()),
              child: const Text('Kirim'),
            ),
          ],
        ),
      );
    }

    final ok = await admin.decideApproval(userId, action, note: note);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok
            ? (action == 'approved'
                ? '$email disetujui — user akan diberi tahu.'
                : '$email ditolak.')
            : 'Gagal memproses. Coba lagi.'),
        backgroundColor: ok
            ? (action == 'approved' ? AppTheme.successColor : AppTheme.warningColor)
            : AppTheme.dangerColor,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _formatDate(dynamic value) {
    if (value == null) return '-';
    try {
      final dt = DateTime.parse(value.toString()).toLocal();
      return DateFormat('dd MMM yyyy HH:mm').format(dt);
    } catch (_) {
      return value.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    final admin = context.watch<AdminProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Persetujuan Pendaftar'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Muat ulang',
            onPressed: () => admin.fetchPendingApprovals(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => admin.fetchPendingApprovals(),
        child: _buildBody(admin),
      ),
    );
  }

  Widget _buildBody(AdminProvider admin) {
    if (admin.approvalsLoading && admin.pendingApprovals.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (admin.approvalsError != null) {
      return ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              '${admin.approvalsError}\nPastikan SQL approval sudah dijalankan di Supabase.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.dangerColor),
            ),
          ),
        ],
      );
    }
    if (admin.pendingApprovals.isEmpty) {
      return ListView(
        children: const [
          Padding(
            padding: EdgeInsets.all(40),
            child: Column(
              children: [
                Icon(Icons.how_to_reg_outlined, size: 64, color: Colors.grey),
                SizedBox(height: 12),
                Text(
                  'Tidak ada pendaftar menunggu.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
                SizedBox(height: 4),
                Text(
                  'Notifikasi muncul otomatis saat ada yang mendaftar.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: admin.pendingApprovals.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final row = admin.pendingApprovals[i];
        final email = (row['email'] as String?) ?? '(tanpa email)';
        final userId = row['user_id'] as String;

        return ListTile(
          leading: CircleAvatar(
            backgroundColor: AppTheme.warningColor.withValues(alpha: 0.15),
            child: Text(
              email.isNotEmpty ? email[0].toUpperCase() : '?',
              style: const TextStyle(
                  color: AppTheme.warningColor, fontWeight: FontWeight.w600),
            ),
          ),
          title: Text(email,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text('daftar ${_formatDate(row['requested_at'])}',
              style: TextStyle(fontSize: AppTheme.captionSize)),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.close, color: AppTheme.dangerColor),
                tooltip: 'Tolak',
                onPressed: () => _decide(admin, row, 'rejected'),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.check_circle, color: AppTheme.successColor),
                tooltip: 'Setujui',
                onPressed: () => _decide(admin, row, 'approved'),
              ),
            ],
          ),
          // key unik per user untuk keamanan aksi
          key: ValueKey('approval_$userId'),
        );
      },
    );
  }
}
