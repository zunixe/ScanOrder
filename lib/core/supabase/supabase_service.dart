import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/order.dart';

/// Service untuk sinkronisasi data ke Supabase backend.
/// 
/// Setup:
/// 1. Buat project di https://supabase.com (gratis tier)
/// 2. Buat table `orders` dengan kolom: id, device_id, resi, marketplace, scanned_at, date, photo_url
/// 3. Copy Supabase URL dan anon key ke [supabaseUrl] dan [supabaseKey]
/// 4. Buka Storage di Supabase, buat bucket `scan-photos` (public)
class SupabaseService {
  static final SupabaseService _instance = SupabaseService._internal();
  factory SupabaseService() => _instance;
  SupabaseService._internal();

  // GANTI INI dengan URL dan key dari Supabase project Anda:
  static const String _supabaseUrl = 'https://rnithriviguzbfpvzrwa.supabase.co';
  static const String _supabaseKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJuaXRocml2aWd1emJmcHZ6cndxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzc0NjQwNDksImV4cCI6MjA5MzA0MDA0OX0.3dMU23uT_9uEGHirs0PieViE7k1M_ezlCJ8wjryf2lc';

  bool get _isConfigured =>
      !_supabaseUrl.contains('YOUR_PROJECT') && !_supabaseKey.contains('YOUR_ANON_KEY');

  Future<void> initialize() async {
    if (!_isConfigured) {
      // Belum dikonfigurasi — skip supabase
      return;
    }
    await Supabase.initialize(
      url: _supabaseUrl,
      anonKey: _supabaseKey,
    );
  }

  SupabaseClient? get _client {
    if (!_isConfigured) return null;
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  /// Upload foto scan ke Supabase Storage, return public URL
  Future<String?> uploadPhoto(File file, String fileName) async {
    final client = _client;
    if (client == null) return null;
    try {
      await client.storage.from('scan-photos').upload(fileName, file);
      return client.storage.from('scan-photos').getPublicUrl(fileName);
    } catch (e) {
      return null;
    }
  }

  /// Kirim order yang baru di-scan ke Supabase
  Future<void> insertOrder(ScannedOrder order, {String? deviceId}) async {
    final client = _client;
    if (client == null) return;
    try {
      await client.from('orders').insert({
        'device_id': deviceId ?? 'unknown',
        'resi': order.resi,
        'marketplace': order.marketplace,
        'scanned_at': order.scannedAt.millisecondsSinceEpoch,
        'date': order.date,
        'photo_url': order.photoPath,
      });
    } catch (e) {
      // Silently fail untuk tidak mengganggu UX scan
    }
  }

  /// Ambil semua orders dari Supabase (untuk debug)
  Future<List<Map<String, dynamic>>> fetchOrders() async {
    final client = _client;
    if (client == null) return [];
    try {
      final response = await client.from('orders').select().order('scanned_at', ascending: false);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      return [];
    }
  }
}
