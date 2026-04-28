import 'package:shared_preferences/shared_preferences.dart';
import '../core/db/database_helper.dart';

class QuotaService {
  static const int freeQuota = 50;
  static const String _proKey = 'is_pro_user';

  final DatabaseHelper _db = DatabaseHelper.instance;

  Future<bool> isPro() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_proKey) ?? false;
  }

  Future<void> setPro(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_proKey, value);
  }

  Future<int> getTotalScanned() async {
    return await _db.getTotalOrderCount();
  }

  Future<int> getRemainingFreeScans() async {
    final total = await getTotalScanned();
    final remaining = freeQuota - total;
    return remaining > 0 ? remaining : 0;
  }

  Future<bool> canScan() async {
    if (await isPro()) return true;
    final total = await getTotalScanned();
    return total < freeQuota;
  }
}
