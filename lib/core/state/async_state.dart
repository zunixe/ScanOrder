import 'package:flutter/foundation.dart';

/// Unified async state pattern for all providers.
/// Inspired by Riverpod's AsyncValue but usable with ChangeNotifier/Provider.
///
/// Usage:
///   AsyncState<List<ScanRecord>> scansState = const AsyncState.idle();
///   scansState = const AsyncState.loading();
///   scansState = AsyncState.data(myList);
///   scansState = AsyncState.error('Failed to load', stackTrace);
///
/// In UI:
///   state.when(
///     idle: () => Text('No data yet'),
///     loading: () => CircularProgressIndicator(),
///     data: (data) => Text(data.toString()),
///     error: (msg, retry) => ErrorWidget(msg, onRetry: retry),
///   );
sealed class AsyncState<T> {
  const AsyncState();

  /// No operation has been performed yet
  const factory AsyncState.idle() = AsyncStateIdle<T>;

  /// Operation is in progress
  const factory AsyncState.loading({T? previousData}) = AsyncStateLoading<T>;

  /// Operation completed successfully
  const factory AsyncState.data(T value) = AsyncStateData<T>;

  /// Operation failed
  const factory AsyncState.error(String message, {StackTrace? stackTrace, VoidCallback? retry}) = AsyncStateError<T>;

  /// Whether this state is loading
  bool get isLoading => this is AsyncStateLoading<T>;

  /// Whether this state has data
  bool get hasData => this is AsyncStateData<T>;

  /// Whether this state has error
  bool get hasError => this is AsyncStateError<T>;

  /// Get data if available, null otherwise
  T? get dataOrNull => switch (this) {
    AsyncStateData<T>(:final value) => value,
    AsyncStateLoading<T>(:final previousData) => previousData,
    _ => null,
  };

  /// Get error message if available
  String? get errorOrNull => switch (this) {
    AsyncStateError<T>(:final message) => message,
    _ => null,
  };

  /// Pattern match on all states
  R when<R>({
    required R Function() idle,
    required R Function(T? previousData) loading,
    required R Function(T data) data,
    required R Function(String message, StackTrace? stackTrace, VoidCallback? retry) error,
  }) => switch (this) {
    AsyncStateIdle<T>() => idle(),
    AsyncStateLoading<T>(:final previousData) => loading(previousData),
    AsyncStateData<T>(:final value) => data(value),
    AsyncStateError<T>(:final message, :final stackTrace, :final retry) => error(message, stackTrace, retry),
  };

  /// Pattern match with optional handlers (defaults to no-op)
  R maybeWhen<R>({
    R Function()? idle,
    R Function(T? previousData)? loading,
    R Function(T data)? data,
    R Function(String message, StackTrace? stackTrace, VoidCallback? retry)? error,
    required R Function() orElse,
  }) => switch (this) {
    AsyncStateIdle<T>() => idle != null ? idle() : orElse(),
    AsyncStateLoading<T>(:final previousData) => loading != null ? loading(previousData) : orElse(),
    AsyncStateData<T>(:final value) => data != null ? data(value) : orElse(),
    AsyncStateError<T>(:final message, :final stackTrace, :final retry) => error != null ? error(message, stackTrace, retry) : orElse(),
  };
}

class AsyncStateIdle<T> extends AsyncState<T> {
  const AsyncStateIdle();
}

class AsyncStateLoading<T> extends AsyncState<T> {
  final T? previousData;
  const AsyncStateLoading({this.previousData});
}

class AsyncStateData<T> extends AsyncState<T> {
  final T value;
  const AsyncStateData(this.value);
}

class AsyncStateError<T> extends AsyncState<T> {
  final String message;
  final StackTrace? stackTrace;
  final VoidCallback? retry;
  const AsyncStateError(this.message, {this.stackTrace, this.retry});
}

/// Helper to run an async operation and update an AsyncState.
/// Usage:
///   scansState = await runAsync(() => _db.getAllScans(userId: userId));
/// Or with notifyListeners:
///   scansState = const AsyncState.loading();
///   notifyListeners();
///   scansState = await runAsync(() => _db.getAllScans(userId: userId));
///   notifyListeners();
Future<AsyncState<T>> runAsync<T>(Future<T> Function() operation, {VoidCallback? retry}) async {
  try {
    final result = await operation();
    return AsyncState.data(result);
  } catch (e, stack) {
    return AsyncState.error(e.toString(), stackTrace: stack, retry: retry);
  }
}
