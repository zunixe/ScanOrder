import 'package:flutter/material.dart';
import 'app.dart';
import 'core/supabase/supabase_service.dart';
import 'services/sync_queue.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SupabaseService().initialize();
  // Process any pending sync tasks from previous sessions
  SyncQueue().processPending();
  runApp(const ScanOrderApp());
}
