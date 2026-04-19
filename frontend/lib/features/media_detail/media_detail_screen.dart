import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../providers/media_provider.dart';
import '../../providers/download_provider.dart';
import '../../providers/settings_provider.dart';
import '../../shared/models/media_info.dart';
import '../../shared/widgets/download_options_modal.dart';

class MediaDetailScreen extends ConsumerWidget {
  const MediaDetailScreen({super.key, required this.url});
  final String url;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final infoAsync = ref.watch(mediaInfoProvider(url));

    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      body: infoAsync.when(
        loading: () => const _LoadingView(),
        error: (err, _) => _ErrorView(error: err.toString(), url: url),
        data: (info) => _MediaDetailContent(info: info),
      ),
    );
  }
}

class _MediaDetailContent extends ConsumerWidget {
  const _MediaDetailContent({required this.info});
  final MediaInfo info;

  String _formatDuration(int? seconds) {
    if (seconds == null) return '';
    final d = Duration(seconds: seconds);
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0)
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  String _formatCount(int? count) {
    if (count == null) return '';
    if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)}M';
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}K';
    return count.toString();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CustomScrollView(
      slivers: [
        // App bar with thumbnail
        SliverAppBar(
          expandedHeight: 240,
          pinned: true,
          backgroundColor: AppColors.darkBackground,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => context.go('/'),
          ),
          flexibleSpace: FlexibleSpaceBar(
            background: info.thumbnail != null
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.network(
                        info.thumbnail!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          color: AppColors.darkSurface,
                          child: const Icon(Icons.image_not_supported,
                              size: 64, color: AppColors.textHint),
                        ),
                      ),
                      // Gradient overlay
                      Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.transparent,
                              AppColors.darkBackground,
                            ],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            stops: [0.4, 1.0],
                          ),
                        ),
                      ),
                      // Duration chip
                      if (info.duration != null)
                        Positioned(
                          bottom: 12,
                          right: 12,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.7),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              _formatDuration(info.duration),
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 12),
                            ),
                          ),
                        ),
                    ],
                  )
                : Container(color: AppColors.darkSurface),
          ),
        ),

        // Content
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              // Platform chip
              if (info.platform != null)
                Chip(
                  label: Text(info.platform!.toUpperCase()),
                  avatar: const Icon(Icons.play_circle, size: 14),
                  padding: EdgeInsets.zero,
                ),
              const SizedBox(height: 8),

              // Title
              Text(info.title,
                  style: AppTextStyles.displayLarge.copyWith(fontSize: 22)),
              const SizedBox(height: 8),

              // Uploader
              if (info.uploader != null)
                Row(
                  children: [
                    const Icon(Icons.person,
                        size: 14, color: AppColors.textHint),
                    const SizedBox(width: 4),
                    Text(info.uploader!,
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 13)),
                  ],
                ),

              const SizedBox(height: 12),

              // Stats row
              Row(
                children: [
                  if (info.viewCount != null) ...[
                    const Icon(Icons.visibility,
                        size: 14, color: AppColors.textHint),
                    const SizedBox(width: 4),
                    Text(_formatCount(info.viewCount),
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 12)),
                    const SizedBox(width: 16),
                  ],
                  if (info.likeCount != null) ...[
                    const Icon(Icons.thumb_up,
                        size: 14, color: AppColors.textHint),
                    const SizedBox(width: 4),
                    Text(_formatCount(info.likeCount),
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 12)),
                  ],
                ],
              ),

              const SizedBox(height: 20),

              // Download button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    showModalBottomSheet<void>(
                      context: context,
                      backgroundColor: AppColors.darkSurface,
                      shape: const RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.vertical(top: Radius.circular(24)),
                      ),
                      isScrollControlled: true,
                      builder: (_) => DownloadOptionsModal(
                        mediaInfo: info,
                        onDownload: (req) async {
                          try {
                            await ref
                                .read(downloadProvider.notifier)
                                .startDownload(
                                  url: req['url'] as String,
                                  formatId: req['format_id'] as String?,
                                  audioOnly:
                                      req['audio_only'] as bool? ?? false,
                                  convertTo: req['convert_to'] as String?,
                                  embedThumbnail:
                                      req['embed_thumbnail'] as bool? ?? true,
                                  preferredQuality: ref
                                      .read(settingsProvider)
                                      .preferredQuality,
                                );
                            if (context.mounted) {
                              Navigator.of(context).pop();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('Download started!')),
                              );
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Download failed: $e')),
                              );
                            }
                          }
                        },
                      ),
                    );
                  },
                  icon: const Icon(Icons.download_rounded),
                  label: const Text('Download'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Description
              if (info.description != null && info.description!.isNotEmpty) ...[
                const Text('Description', style: AppTextStyles.titleMedium),
                const SizedBox(height: 8),
                _ExpandableText(text: info.description!),
                const SizedBox(height: 24),
              ],

              // Available formats
              if (info.formats.isNotEmpty) ...[
                const Text('Available Formats',
                    style: AppTextStyles.titleMedium),
                const SizedBox(height: 12),
                ...info.formats
                    .where((f) => f.vcodec != null && f.vcodec != 'none')
                    .take(8)
                    .map((f) => _FormatTile(format: f)),
              ],
            ]),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 80)),
      ],
    );
  }
}

class _ExpandableText extends StatefulWidget {
  const _ExpandableText({required this.text});
  final String text;

  @override
  State<_ExpandableText> createState() => _ExpandableTextState();
}

class _ExpandableTextState extends State<_ExpandableText> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.text,
          maxLines: _expanded ? null : 3,
          overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
          style: const TextStyle(
              color: AppColors.textSecondary, fontSize: 13, height: 1.5),
        ),
        const SizedBox(height: 4),
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Text(
            _expanded ? 'Show less' : 'Show more',
            style: const TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
                fontSize: 13),
          ),
        ),
      ],
    );
  }
}

class _FormatTile extends StatelessWidget {
  const _FormatTile({required this.format});
  final VideoFormat format;

  String _filesize() {
    final bytes = format.effectiveFilesize;
    if (bytes == null) return '';
    if (bytes >= 1073741824)
      return '${(bytes / 1073741824).toStringAsFixed(1)} GB';
    if (bytes >= 1048576) return '${(bytes / 1048576).toStringAsFixed(1)} MB';
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.darkCard,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              format.ext.toUpperCase(),
              style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: 10,
                  fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              [
                if (format.resolution != null) format.resolution,
                if (format.fps != null) '${format.fps!.toInt()}fps',
                if (format.formatNote != null) format.formatNote,
              ].join(' • '),
              style:
                  const TextStyle(color: AppColors.textPrimary, fontSize: 13),
            ),
          ),
          if (_filesize().isNotEmpty)
            Text(_filesize(),
                style:
                    const TextStyle(color: AppColors.textHint, fontSize: 11)),
        ],
      ),
    );
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Loading media info...',
              style: TextStyle(color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.url});
  final String error;
  final String url;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 64, color: AppColors.error),
            const SizedBox(height: 16),
            const Text('Failed to load media info',
                style: AppTextStyles.titleMedium),
            const SizedBox(height: 8),
            Text(error,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 12)),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => context.go('/'),
              icon: const Icon(Icons.arrow_back),
              label: const Text('Go Back'),
            ),
          ],
        ),
      ),
    );
  }
}
