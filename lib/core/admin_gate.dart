import 'package:flutter/material.dart';
import 'package:provider/single_child_widget.dart';

/// Jembatan netral antara build USER dan build ADMIN.
///
/// ATURAN WAJIB: file ini TIDAK BOLEH meng-import modul admin mana pun
/// (lib/admin/*).
///
/// Build rilis user (flavor `play`, entry default `lib/main.dart`) tidak
/// pernah mengisi field di sini → graph import user tidak pernah menyentuh
/// kode admin → tree shaker membuangnya TOTAL dari AAB rilis.
/// Entry admin (`lib/main_admin.dart`) mengisi semua field via wireAdmin().
class AdminGate {
  /// Builder halaman Admin Panel. Null pada build user.
  static WidgetBuilder? panelBuilder;

  /// Provider tambahan untuk MultiProvider di app.dart (mis. AdminProvider).
  static List<SingleChildWidget> extraProviders = const [];

  /// Tile "Admin Panel" untuk halaman Settings. Null/kosong pada build user.
  static List<Widget> Function(BuildContext)? settingsTiles;

  /// Dipanggil bootstrap SETELAH Supabase.initialize — tempat aman untuk
  /// hal yang butuh client Supabase sudah siap.
  static Future<void> Function()? postInit;

  /// True hanya pada build admin.
  static bool get enabled => panelBuilder != null;

  /// Email akun super admin tunggal — sumber kebenaran yang sama dengan
  /// guard SQL is_super_admin() di Supabase.
  static const String superAdminEmail = 'zunixe@gmail.com';

  /// Sesi aktif adalah super admin? Anon/guest & user biasa = false →
  /// seluruh UI admin (menu, panel) disembunyikan walau berada di build admin.
  static bool isSuperAdmin(String? email) =>
      email != null && email.toLowerCase() == superAdminEmail;
}
