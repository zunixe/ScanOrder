// ignore_for_file: depend_on_referenced_packages
import 'dart:async';

import 'package:supabase/supabase.dart';

/// Shared state passed between table/filter builders.
class FakeQueryState {
  Object? response;
  Object? error;
  final List<String> calls = [];

  FakeQueryState({this.response, this.error});
}

/// Fake implementing `SupabaseQueryBuilder` — returned by `client.from(table)`.
/// Its terminal starters (`select`, `insert`, ...) return a [FakeFilterBuilder].
class FakeTableBuilder implements SupabaseQueryBuilder {
  final FakeQueryState state;

  FakeTableBuilder({Object? response, Object? error})
      : state = FakeQueryState(response: response, error: error);

  List<String> get calls => state.calls;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final name = memberName(invocation);
    switch (name) {
      case 'toString':
        return 'FakeTableBuilder';
      case 'hashCode':
        return identityHashCode(this);
      case '==':
        return identical(this, invocation.positionalArguments.first);
      case 'runtimeType':
        return FakeTableBuilder;
    }
    state.calls.add(name);
    return FakeFilterBuilder(state);
  }
}

/// Fake implementing `PostgrestFilterBuilder<PostgrestList>` — returned by the
/// table builder's starters. Chain methods return `this`; awaiting resolves to
/// the shared response (or throws the shared error).
class FakeFilterBuilder implements PostgrestFilterBuilder<PostgrestList> {
  final FakeQueryState state;

  FakeFilterBuilder(this.state);

  List<String> get calls => state.calls;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final name = memberName(invocation);
    switch (name) {
      case 'toString':
        return 'FakeFilterBuilder';
      case 'hashCode':
        return identityHashCode(this);
      case '==':
        return identical(this, invocation.positionalArguments.first);
      case 'runtimeType':
        return FakeFilterBuilder;
    }
    state.calls.add(name);
    return this;
  }

  Future<PostgrestList> _baseFuture() {
    if (state.error != null) {
      return Future<PostgrestList>.error(state.error!);
    }
    final raw = state.response;
    // The declaration types the awaited value as PostgrestList. Non-list
    // responses (e.g. `int` rowcount from delete) are coerced to an empty list
    // because callers of those methods ignore the value.
    final value = raw is PostgrestList ? raw : <Map<String, dynamic>>[];
    return Future<PostgrestList>.value(value);
  }

  @override
  Future<R> then<R>(FutureOr<R> Function(PostgrestList value) onValue, {Function? onError}) =>
      _baseFuture().then(onValue, onError: onError);

  @override
  Future<PostgrestList> catchError(Function onError, {bool Function(Object error)? test}) =>
      _baseFuture().catchError(onError, test: test);

  @override
  Future<PostgrestList> whenComplete(FutureOr<void> Function() action) =>
      _baseFuture().whenComplete(action);

  @override
  Future<PostgrestList> timeout(Duration timeLimit,
          {FutureOr<PostgrestList> Function()? onTimeout}) =>
      _baseFuture().timeout(timeLimit, onTimeout: onTimeout);
}

String memberName(Invocation invocation) => invocation.memberName
    .toString()
    .replaceAll('Symbol("', '')
    .replaceAll('")', '');
