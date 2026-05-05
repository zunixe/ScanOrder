import 'package:flutter_test/flutter_test.dart';
import 'package:scanorder/core/state/async_state.dart';

void main() {
  group('AsyncState', () {
    test('idle state', () {
      const state = AsyncState<int>.idle();
      expect(state.isLoading, isFalse);
      expect(state.hasData, isFalse);
      expect(state.hasError, isFalse);
      expect(state.dataOrNull, isNull);
      expect(state.errorOrNull, isNull);
    });

    test('loading state without previous data', () {
      const state = AsyncState<int>.loading();
      expect(state.isLoading, isTrue);
      expect(state.hasData, isFalse);
      expect(state.dataOrNull, isNull);
    });

    test('loading state with previous data', () {
      const state = AsyncState<int>.loading(previousData: 42);
      expect(state.isLoading, isTrue);
      expect(state.dataOrNull, 42);
    });

    test('data state', () {
      const state = AsyncState<int>.data(42);
      expect(state.hasData, isTrue);
      expect(state.isLoading, isFalse);
      expect(state.dataOrNull, 42);
    });

    test('error state', () {
      final state = AsyncState<int>.error('Something went wrong', retry: () {});
      expect(state.hasError, isTrue);
      expect(state.isLoading, isFalse);
      expect(state.errorOrNull, 'Something went wrong');
      expect(state.dataOrNull, isNull);
    });

    test('when pattern matches correctly', () {
      const idle = AsyncState<String>.idle();
      expect(
        idle.when(idle: () => 'idle', loading: (_) => 'loading', data: (d) => 'data:$d', error: (e, s, r) => 'error:$e'),
        'idle',
      );

      const loading = AsyncState<String>.loading(previousData: 'old');
      expect(
        loading.when(idle: () => 'idle', loading: (prev) => 'loading:$prev', data: (d) => 'data:$d', error: (e, s, r) => 'error:$e'),
        'loading:old',
      );

      const data = AsyncState<String>.data('hello');
      expect(
        data.when(idle: () => 'idle', loading: (_) => 'loading', data: (d) => 'data:$d', error: (e, s, r) => 'error:$e'),
        'data:hello',
      );

      final error = AsyncState<String>.error('fail');
      expect(
        error.when(idle: () => 'idle', loading: (_) => 'loading', data: (d) => 'data:$d', error: (e, s, r) => 'error:$e'),
        'error:fail',
      );
    });

    test('maybeWhen falls back to orElse', () {
      const state = AsyncState<int>.idle();
      expect(
        state.maybeWhen(data: (d) => 'data:$d', orElse: () => 'other'),
        'other',
      );
    });

    test('maybeWhen matches specific state', () {
      const state = AsyncState<int>.data(99);
      expect(
        state.maybeWhen(data: (d) => 'data:$d', orElse: () => 'other'),
        'data:99',
      );
    });
  });

  group('runAsync', () {
    test('returns data on success', () async {
      final result = await runAsync(() async => [1, 2, 3]);
      expect(result, isA<AsyncStateData<List<int>>>());
      expect((result as AsyncStateData<List<int>>).value, [1, 2, 3]);
    });

    test('returns error on failure', () async {
      final result = await runAsync<int>(() async => throw Exception('boom'));
      expect(result, isA<AsyncStateError<int>>());
      expect((result as AsyncStateError<int>).message, contains('boom'));
    });

    test('retry callback is preserved', () async {
      var attempt = 0;
      Future<int> operation() async {
        attempt++;
        if (attempt < 2) throw Exception('not yet');
        return 42;
      }
      final result = await runAsync(operation, retry: operation);
      expect(result, isA<AsyncStateError<int>>());
      final errResult = result as AsyncStateError<int>;
      expect(errResult.retry, isNotNull);
    });
  });

  group('AsyncState equality', () {
    test('idle states are equal', () {
      const a = AsyncState<int>.idle();
      const b = AsyncState<int>.idle();
      expect(a, b);
    });

    test('data states with same value are equal', () {
      const a = AsyncState<int>.data(5);
      const b = AsyncState<int>.data(5);
      expect(a, b);
    });

    test('data states with different values are not equal', () {
      const a = AsyncState<int>.data(5);
      const b = AsyncState<int>.data(10);
      expect(a, isNot(equals(b)));
    });

    test('loading states with same previous data are equal', () {
      const a = AsyncState<int>.loading(previousData: 5);
      const b = AsyncState<int>.loading(previousData: 5);
      expect(a, b);
    });

    test('loading without previous data differs from loading with', () {
      const a = AsyncState<int>.loading();
      const b = AsyncState<int>.loading(previousData: 5);
      expect(a, isNot(equals(b)));
    });
  });

  group('AsyncState whenOrElse', () {
    test('maybeWhen with loading match', () {
      const state = AsyncState<int>.loading();
      expect(
        state.maybeWhen(loading: (_) => 'loading', orElse: () => 'other'),
        'loading',
      );
    });

    test('maybeWhen with error match', () {
      final state = AsyncState<int>.error('fail');
      expect(
        state.maybeWhen(error: (e, s, r) => 'err:$e', orElse: () => 'other'),
        'err:fail',
      );
    });

    test('maybeWhen with idle match', () {
      const state = AsyncState<int>.idle();
      expect(
        state.maybeWhen(idle: () => 'idle', orElse: () => 'other'),
        'idle',
      );
    });
  });

  group('runAsync edge cases', () {
    test('returns data immediately for fast operations', () async {
      final result = await runAsync(() async => 'quick');
      expect(result, isA<AsyncStateData<String>>());
      expect((result as AsyncStateData<String>).value, 'quick');
    });

    test('error message contains exception text', () async {
      final result = await runAsync<int>(() async => throw FormatException('bad format'));
      expect(result, isA<AsyncStateError<int>>());
      expect((result as AsyncStateError<int>).message, contains('bad format'));
    });

    test('error state has stack trace', () async {
      final result = await runAsync<int>(() async => throw Exception('err'));
      final errResult = result as AsyncStateError<int>;
      expect(errResult.stackTrace, isNotNull);
    });
  });
}
