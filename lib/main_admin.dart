// ============================================================
// Entry BUILD ADMIN — JANGAN PERNAH dipakai untuk rilis store.
//
// Build:
//   flutter build apk --release --flavor admin -t lib/main_admin.dart \
//     --dart-define-from-file=.env
//
// Build rilis Play (app user) memakai entry default lib/main.dart —
// tanpa flag -t apa pun, dengan flavor `play`.
// ============================================================
import 'package:flutter/widgets.dart';

import 'admin/admin_wiring.dart';
import 'main.dart' show bootstrap;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  wireAdmin();
  await bootstrap();
}

// MARKER-XYZ-1234 diagnostic
