import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import '../core/admin_gate.dart';
import 'admin_dashboard_screen.dart';
import 'admin_provider.dart';

/// Pasang semua modul admin ke AdminGate. Dipanggil HANYA dari
/// lib/main_admin.dart — build rilis user tidak pernah meng-import
/// file ini, sehingga kode admin dibuang total dari AAB `play`.
void wireAdmin() {
  debugPrint('[ADMIN] wiring panel admin…');
  AdminGate.panelBuilder = (_) => const AdminDashboardScreen();
  AdminGate.extraProviders = <SingleChildWidget>[
    ChangeNotifierProvider(create: (_) => AdminProvider()),
  ];
  debugPrint('[ADMIN] wiring selesai');
}
