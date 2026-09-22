// ignore_for_file: depend_on_referenced_packages
import 'package:mocktail/mocktail.dart';
import 'package:supabase/supabase.dart';

import 'fake_supabase.dart';

/// Minimal fake [SupabaseClient] implementing only what [SupabaseService]
/// exercises through its query/RPC surface:
///   - `from(table)`   → a [FakeTableBuilder]
///   - `rpc(fn, ...)`  → a [FakeFilterBuilder] resolving to a preset value
///
/// `currentUser` is injected via `SupabaseService.overrideCurrentUser`.
class FakeSupabaseClient extends Fake implements SupabaseClient {
  final Map<String, FakeTableBuilder> tables = {};
  final Map<String, FakeQueryState> rpcs = {};

  /// Fallback builder for any unconfigured table.
  FakeTableBuilder? defaultTable;

  FakeTableBuilder builderFor(String table) {
    final existing = tables[table];
    if (existing != null) return existing;
    final d = defaultTable;
    if (d != null) return d;
    final fallback = FakeTableBuilder(response: const <Map<String, dynamic>>[]);
    tables[table] = fallback;
    return fallback;
  }

  void setTable(String table, {Object? response, Object? error}) {
    tables[table] = FakeTableBuilder(response: response, error: error);
  }

  void setRpc(String fn, {Object? response, Object? error}) {
    rpcs[fn] = FakeQueryState(response: response, error: error);
  }

  @override
  SupabaseQueryBuilder from(String table) => builderFor(table);

  @override
  PostgrestFilterBuilder<T> rpc<T>(
    String fn, {
    Object? params,
    Object? get,
  }) {
    final state = rpcs[fn] ?? FakeQueryState(response: null);
    return FakeFilterBuilder(state) as PostgrestFilterBuilder<T>;
  }

  @override
  GoTrueClient get auth => _FakeAuth();
}

/// Fake auth client exposing only the members SupabaseService touches.
class _FakeAuth extends Fake implements GoTrueClient {
  @override
  Stream<AuthState> get onAuthStateChange => const Stream<AuthState>.empty();

  @override
  User? get currentUser => null;
}
