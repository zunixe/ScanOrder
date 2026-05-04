import 'package:flutter/material.dart';

/// Paginated list view for large datasets
class PaginatedListView<T> extends StatefulWidget {
  final Future<List<T>> Function(int page, int pageSize) fetchItems;
  final Widget Function(BuildContext context, T item, int index) itemBuilder;
  final String? emptyMessage;
  final int initialPageSize;
  final int maxPageSize;
  final bool showLoadingIndicator;
  final PullToRefreshCallback? onRefresh;
  final ScrollNotificationPredicate? scrollNotificationPredicate;

  const PaginatedListView({
    super.key,
    required this.fetchItems,
    required this.itemBuilder,
    this.emptyMessage,
    this.initialPageSize = 20,
    this.maxPageSize = 100,
    this.showLoadingIndicator = true,
    this.onRefresh,
    this.scrollNotificationPredicate,
  });

  @override
  State<PaginatedListView<T>> createState() => _PaginatedListViewState<T>();
}

typedef PullToRefreshCallback = Future<void> Function();

class _PaginatedListViewState<T> extends State<PaginatedListView<T>> {
  List<T> _items = [];
  int _currentPage = 0;
  bool _isLoading = false;
  bool _hasMore = true;
  bool _isRefreshing = false;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadMore();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= 
        _scrollController.position.maxScrollExtent - 200) {
      if (!_isLoading && _hasMore) {
        _loadMore();
      }
    }
  }

  Future<void> _loadMore() async {
    if (_isLoading || !_hasMore) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final newItems = await widget.fetchItems(_currentPage, widget.initialPageSize);
      
      setState(() {
        if (newItems.isEmpty || newItems.length < widget.initialPageSize) {
          _hasMore = false;
        }
        
        if (_currentPage == 0) {
          _items = newItems;
        } else {
          _items.addAll(newItems);
        }
        
        _currentPage++;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      // Handle error silently or show snackbar
      debugPrint('Error loading items: $e');
    }
  }

  Future<void> _refresh() async {
    if (_isRefreshing) return;

    setState(() {
      _isRefreshing = true;
      _currentPage = 0;
      _hasMore = true;
    });

    try {
      if (widget.onRefresh != null) {
        await widget.onRefresh!();
      }
      
      await _loadMore();
    } finally {
      setState(() {
        _isRefreshing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty && !_isLoading && !_isRefreshing) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.inbox_outlined,
              size: 64,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              widget.emptyMessage ?? 'No items found',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        controller: _scrollController,
        itemCount: _items.length + (_hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= _items.length) {
            if (widget.showLoadingIndicator) {
              return Padding(
                padding: const EdgeInsets.all(16.0),
                child: Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                  ),
                ),
              );
            }
            return const SizedBox.shrink();
          }
          return widget.itemBuilder(context, _items[index], index);
        },
      ),
    );
  }
}

/// Simple pagination controller for manual control
class PaginationController extends ChangeNotifier {
  int _currentPage = 0;
  int _pageSize = 20;
  bool _isLoading = false;
  bool _hasMore = true;
  List<dynamic> _items = [];

  int get currentPage => _currentPage;
  int get pageSize => _pageSize;
  bool get isLoading => _isLoading;
  bool get hasMore => _hasMore;
  List<dynamic> get items => _items;

  void setPageSize(int size) {
    _pageSize = size;
    notifyListeners();
  }

  void setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  void setHasMore(bool hasMore) {
    _hasMore = hasMore;
    notifyListeners();
  }

  void addItems(List<dynamic> newItems) {
    if (_currentPage == 0) {
      _items = newItems;
    } else {
      _items.addAll(newItems);
    }
    notifyListeners();
  }

  void clear() {
    _items.clear();
    _currentPage = 0;
    _hasMore = true;
    notifyListeners();
  }

  void nextPage() {
    _currentPage++;
    notifyListeners();
  }

  void reset() {
    _currentPage = 0;
    _items.clear();
    _hasMore = true;
    notifyListeners();
  }
}
