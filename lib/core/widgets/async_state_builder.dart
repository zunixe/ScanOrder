import 'package:flutter/material.dart';
import '../../core/state/async_state.dart';
import '../../core/l10n/app_localizations.dart';

/// Generic widget that renders AsyncState<T> with proper loading/error/data UI.
///
/// Usage:
///   AsyncStateBuilder<List<ScanRecord>>(
///     state: historyProvider.scansState,
///     onRetry: () => historyProvider.loadScans(),
///     builder: (context, scans) => ListView(...),
///   );
class AsyncStateBuilder<T> extends StatelessWidget {
  final AsyncState<T> state;
  final Widget Function(BuildContext context, T data) builder;
  final VoidCallback? onRetry;
  final Widget? loadingWidget;
  final Widget Function(String message, VoidCallback? retry)? errorBuilder;
  final Widget? idleWidget;

  const AsyncStateBuilder({
    super.key,
    required this.state,
    required this.builder,
    this.onRetry,
    this.loadingWidget,
    this.errorBuilder,
    this.idleWidget,
  });

  @override
  Widget build(BuildContext context) {
    return state.when(
      idle: () => idleWidget ?? const SizedBox.shrink(),
      loading: (previousData) {
        if (previousData != null) {
          // Show previous data while loading (with optional overlay)
          return Stack(
            children: [
              builder(context, previousData),
              if (loadingWidget != null) loadingWidget!,
            ],
          );
        }
        return loadingWidget ?? const Center(child: CircularProgressIndicator());
      },
      data: (data) => builder(context, data),
      error: (message, stackTrace, retry) {
        if (errorBuilder != null) {
          return errorBuilder!(message, retry ?? onRetry);
        }
        return _DefaultErrorWidget(message: message, onRetry: retry ?? onRetry);
      },
    );
  }
}

/// Default error widget with retry button
class _DefaultErrorWidget extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const _DefaultErrorWidget({required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: onRetry,
                child: Text(l10n.retry),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Inline loading indicator for AppBar actions or small areas
class InlineLoadingIndicator extends StatelessWidget {
  final bool isLoading;
  final Widget child;

  const InlineLoadingIndicator({
    super.key,
    required this.isLoading,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (!isLoading) return child;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2, color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(width: 8),
        child,
      ],
    );
  }
}

/// Snackbar helper for showing errors from providers
void showErrorSnackBar(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
      action: SnackBarAction(
        label: 'OK',
        onPressed: ScaffoldMessenger.of(context).hideCurrentSnackBar,
      ),
    ),
  );
}
