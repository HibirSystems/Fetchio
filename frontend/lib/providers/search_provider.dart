import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/engine/local_media_repository.dart';
import '../shared/models/search_result.dart';

// ── Repository provider ───────────────────────────────────────────────────────

final searchRepositoryProvider = Provider<LocalSearchRepository>((ref) {
  return const LocalSearchRepository();
});

// ── State ─────────────────────────────────────────────────────────────────────

class SearchState {
  const SearchState({
    this.query = '',
    this.results = const [],
    this.isLoading = false,
    this.error,
    this.page = 1,
    this.total = 0,
    this.hasMore = false,
  });

  final String query;
  final List<SearchResultItem> results;
  final bool isLoading;
  final String? error;
  final int page;
  final int total;
  final bool hasMore;

  SearchState copyWith({
    String? query,
    List<SearchResultItem>? results,
    bool? isLoading,
    String? error,
    int? page,
    int? total,
    bool? hasMore,
  }) {
    return SearchState(
      query: query ?? this.query,
      results: results ?? this.results,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      page: page ?? this.page,
      total: total ?? this.total,
      hasMore: hasMore ?? this.hasMore,
    );
  }
}

class SearchNotifier extends StateNotifier<SearchState> {
  SearchNotifier(this._repo) : super(const SearchState());

  final LocalSearchRepository _repo;
  static const int _perPage = 20;

  Future<void> search(String query) async {
    if (query.trim().isEmpty) return;
    state = SearchState(query: query, isLoading: true);
    try {
      final response =
          await _repo.search(query: query, page: 1, perPage: _perPage);
      state = state.copyWith(
        results: response.results,
        isLoading: false,
        page: 1,
        total: response.total,
        hasMore: response.results.length == _perPage,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> loadMore() async {
    if (!state.hasMore || state.isLoading) return;
    final nextPage = state.page + 1;
    state = state.copyWith(isLoading: true);
    try {
      final response = await _repo.search(
        query: state.query,
        page: nextPage,
        perPage: _perPage,
      );
      state = state.copyWith(
        results: [...state.results, ...response.results],
        isLoading: false,
        page: nextPage,
        hasMore: response.results.length == _perPage,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  void clear() => state = const SearchState();
}

final searchProvider = StateNotifierProvider<SearchNotifier, SearchState>((ref) {
  return SearchNotifier(ref.watch(searchRepositoryProvider));
});
