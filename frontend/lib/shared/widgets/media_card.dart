import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/models/search_result.dart';

class MediaCard extends StatelessWidget {
  const MediaCard({super.key, required this.item, required this.onTap});

  final SearchResultItem item;
  final VoidCallback onTap;

  String _formatDuration(int? seconds) {
    if (seconds == null) return '';
    final d = Duration(seconds: seconds);
    final m = d.inMinutes;
    final s = d.inSeconds.remainder(60);
    if (d.inHours > 0) {
      return '${d.inHours}:${(d.inMinutes.remainder(60)).toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  String _formatViews(int? count) {
    if (count == null) return '';
    if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)}M views';
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(0)}K views';
    return '$count views';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.darkCard,
          borderRadius: BorderRadius.circular(16),
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          children: [
            // Thumbnail
            Stack(
              children: [
                if (item.thumbnail != null)
                  Image.network(
                    item.thumbnail!,
                    width: 120,
                    height: 80,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 120,
                      height: 80,
                      color: AppColors.darkDivider,
                      child: const Icon(Icons.image, color: AppColors.textHint),
                    ),
                  )
                else
                  Container(
                    width: 120,
                    height: 80,
                    color: AppColors.darkDivider,
                    child: const Icon(Icons.play_circle_outline,
                        color: AppColors.textHint),
                  ),
                if (item.duration != null)
                  Positioned(
                    bottom: 4,
                    right: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.75),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _formatDuration(item.duration),
                        style: const TextStyle(
                            color: Colors.white, fontSize: 10),
                      ),
                    ),
                  ),
              ],
            ),
            // Info
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    if (item.uploader != null)
                      Text(
                        item.uploader!,
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.textHint),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (item.platform != null) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              item.platform!,
                              style: const TextStyle(
                                  fontSize: 9,
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        if (_formatViews(item.viewCount).isNotEmpty)
                          Text(
                            _formatViews(item.viewCount),
                            style: const TextStyle(
                                fontSize: 10, color: AppColors.textHint),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shimmer placeholder while search loads
class MediaCardSkeleton extends StatelessWidget {
  const MediaCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppColors.darkCard,
      highlightColor: AppColors.darkDivider,
      child: Container(
        height: 80,
        decoration: BoxDecoration(
          color: AppColors.darkCard,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(width: 120, height: 80, color: AppColors.darkSurface),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                      height: 12,
                      width: double.infinity,
                      color: AppColors.darkSurface),
                  const SizedBox(height: 6),
                  Container(height: 10, width: 100, color: AppColors.darkSurface),
                  const SizedBox(height: 6),
                  Container(height: 8, width: 60, color: AppColors.darkSurface),
                ],
              ),
            ),
            const SizedBox(width: 12),
          ],
        ),
      ),
    );
  }
}
