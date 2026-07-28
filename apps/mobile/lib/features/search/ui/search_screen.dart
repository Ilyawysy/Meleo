import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/design/app_colors.dart';
import '../../../core/design/app_typography.dart';
import '../data/search_service.dart';
import '../models/search_result.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  final _searchService = SearchService();
  List<SearchResult> _results = [];
  bool _isLoading = false;
  Timer? _debounce;

  @override
  void dispose() {
    _controller.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onQueryChanged(String query) {
    setState(() {}); // Update UI immediately
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _performSearch(query);
    });
  }

  Future<void> _performSearch(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _results = [];
        _isLoading = false;
      });
      return;
    }

    setState(() => _isLoading = true);
    try {
      final results = await _searchService.search(
        query,
        trashed: false,
      );
      if (mounted) {
        setState(() {
          _results = results;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        child: Column(
          children: [
            // Search bar
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 44,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: AppColors.greyBgDarker,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.search,
                              size: 18, color: AppColors.textLight),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _controller,
                              autofocus: true,
                              style: AppTypography.body15(),
                              decoration: InputDecoration(
                                hintText: 'Search tasks...',
                                hintStyle: AppTypography.body15(
                                    color: AppColors.textLight),
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.zero,
                                isDense: true,
                              ),
                              onChanged: _onQueryChanged,
                            ),
                          ),
                          if (_controller.text.isNotEmpty)
                            GestureDetector(
                              onTap: () {
                                _controller.clear();
                                setState(() => _results = []);
                              },
                              child: const Icon(Icons.close,
                                  size: 16, color: AppColors.textLight),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Text(
                      'Cancel',
                      style: AppTypography.body15(
                          color: AppColors.primaryBlue),
                    ),
                  ),
                ],
              ),
            ),
            // Results
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                          color: AppColors.primaryBlue))
                  : _results.isEmpty
                      ? Center(
                          child: Text(
                            _controller.text.isEmpty
                                ? 'Type to search'
                                : 'No results found',
                            style: AppTypography.body15(
                                color: AppColors.textLight),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          itemCount: _results.length,
                          itemBuilder: (context, i) {
                            final result = _results[i];
                            return _buildResultItem(result);
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultItem(SearchResult result) {
    return GestureDetector(
      onTap: () => Navigator.pop(context, result),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: AppColors.greyBgDarker, width: 1),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title
            result.highlightedTitle != null
                ? RichText(
                    text: TextSpan(
                      children: result.highlightedTitle,
                      style: AppTypography.heading16(),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  )
                : Text(
                    result.title,
                    style: AppTypography.heading16(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
            // Subtitle/description
            if (result.subtitle != null || result.highlightedBody != null) ...[
              const SizedBox(height: 4),
              result.highlightedBody != null
                  ? RichText(
                      text: TextSpan(
                        children: result.highlightedBody,
                        style: AppTypography.body13(
                            color: AppColors.textMedium),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    )
                  : Text(
                      result.subtitle!,
                      style: AppTypography.body13(
                          color: AppColors.textMedium),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
            ],
          ],
        ),
      ),
    );
  }
}
