import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/skeleton_loader.dart';
import '../providers/search_provider.dart';

class SearchScreen extends ConsumerWidget {
  const SearchScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ref.watch(searchQueryProvider);
    final resultsState = ref.watch(searchResultsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Global Search'),
        backgroundColor: AppColors.surfaceLowest,
        elevation: 1,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(70),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              onChanged: (val) => ref.read(searchResultsProvider.notifier).onQueryChanged(val),
              decoration: InputDecoration(
                hintText: 'Search PRN, Names, Document IDs...',
                prefixIcon: const Icon(Icons.search, color: AppColors.textSecondary),
                suffixIcon: query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: AppColors.textSecondary),
                        onPressed: () {
                          // Note: Needs a controller to fully clear text field, 
                          // but will clear query state for now.
                          ref.read(searchResultsProvider.notifier).onQueryChanged('');
                        },
                      )
                    : null,
                filled: true,
                fillColor: AppColors.surfaceLow,
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: resultsState.when(
          loading: () => ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: 5,
            separatorBuilder: (_, _) => const SizedBox(height: 16),
            itemBuilder: (context, index) => Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonLoader(width: 200, height: 20, borderRadius: 4),
                      const SizedBox(height: 8),
                      SkeletonLoader(width: double.infinity, height: 16, borderRadius: 4),
                      const SizedBox(height: 4),
                      SkeletonLoader(width: 150, height: 16, borderRadius: 4),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                const SkeletonLoader(width: 60, height: 40, borderRadius: 8),
              ],
            ),
          ),
          error: (err, _) => Center(child: Text('Error: $err')),
          data: (results) {
            if (query.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.manage_search_rounded, size: 80, color: AppColors.outlineVariant),
                    const SizedBox(height: 16),
                    Text('Start typing to search documents.', style: AppTextStyles.bodyLg.copyWith(color: AppColors.textSecondary)),
                  ],
                ),
              );
            }

            if (results.isEmpty) {
              return CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverFillRemaining(
                    child: Center(
                      child: Text('No results found for "$query"', style: AppTextStyles.bodyLg),
                    ),
                  )
                ],
              );
            }

            return RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(searchResultsProvider);
              },
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: results.length,
                separatorBuilder: (context, index) => const Divider(color: AppColors.outlineVariant),
                itemBuilder: (context, index) {
                  final item = results[index];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(item.title, style: AppTextStyles.h2),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(item.snippet, style: AppTextStyles.bodySm, maxLines: 2, overflow: TextOverflow.ellipsis),
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(color: AppColors.secondaryContainer, borderRadius: BorderRadius.circular(12)),
                          child: Text(item.type, style: AppTextStyles.labelMd.copyWith(color: AppColors.primary)),
                        ),
                        const SizedBox(height: 4),
                        Text('${(item.confidence * 100).toInt()}% Match', style: AppTextStyles.labelMd),
                      ],
                    ),
                    onTap: () => context.push('/result/${item.id}'),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}
