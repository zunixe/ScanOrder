import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import 'admin_provider.dart';

/// Daftar seluruh user terdaftar (dari RPC admin_list_users).
/// Data: email, tanggal daftar, jumlah scan, scan terakhir, tier.
class UsersListScreen extends StatefulWidget {
  const UsersListScreen({super.key});

  @override
  State<UsersListScreen> createState() => _UsersListScreenState();
}

class _UsersListScreenState extends State<UsersListScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AdminProvider>().fetchUsers();
    });
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

  String _formatLastScan(dynamic value) {
    if (value is! num || value <= 0) return 'belum pernah scan';
    final dt = DateTime.fromMillisecondsSinceEpoch(value.toInt()).toLocal();
    return 'scan terakhir ${DateFormat('dd MMM yyyy').format(dt)}';
  }

  Color _tierColor(String? tier) {
    switch (tier) {
      case 'unlimited':
        return Colors.deepPurple;
      case 'pro':
        return AppTheme.primaryColor;
      case 'basic':
        return AppTheme.successColor;
      case 'free':
        return Colors.grey;
      default:
        return Colors.grey.shade400;
    }
  }

  @override
  Widget build(BuildContext context) {
    final admin = context.watch<AdminProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Daftar User')),
      body: RefreshIndicator(
        onRefresh: () => admin.fetchUsers(),
        child: _buildBody(admin),
      ),
    );
  }

  Widget _buildBody(AdminProvider admin) {
    if (admin.usersLoading && admin.users.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (admin.usersError != null) {
      return ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              admin.usersError!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.dangerColor),
            ),
          ),
        ],
      );
    }
    if (admin.users.isEmpty) {
      return ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Tidak ada user.', textAlign: TextAlign.center),
          ),
        ],
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: admin.users.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final u = admin.users[i];
        final email = (u['email'] as String?) ?? '(tanpa email)';
        final tier = u['tier'] as String?;
        final totalScans = (u['total_scans'] as num?)?.toInt() ?? 0;

        return ListTile(
          leading: CircleAvatar(
            backgroundColor:
                _tierColor(tier).withValues(alpha: 0.15),
            child: Text(
              email.isNotEmpty ? email[0].toUpperCase() : '?',
              style: TextStyle(
                  color: _tierColor(tier), fontWeight: FontWeight.w600),
            ),
          ),
          title: Text(email,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(
            'daftar ${_formatDate(u['created_at'])} · $totalScans scan\n'
            '${_formatLastScan(u['last_scan_at'])}',
            style: TextStyle(
                fontSize: AppTheme.captionSize, height: 1.35),
          ),
          isThreeLine: true,
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: _tierColor(tier).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              (tier ?? '-').toUpperCase(),
              style: TextStyle(
                  fontSize: AppTheme.microSize, color: _tierColor(tier)),
            ),
          ),
        );
      },
    );
  }
}
