import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:percent_indicator/linear_percent_indicator.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../../providers/download_provider.dart';
import '../../shared/models/download_item.dart';
import '../../core/storage/device_media.dart';

final deviceMediaProvider = Provider<DeviceMedia>((ref) => DeviceMedia());

Future<void> _runAction(
    BuildContext context, Future<void> Function() action) async {
  try {
    await action();
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Action failed: $error')),
      );
    }
  }
}

class DownloadManagerScreen extends ConsumerStatefulWidget {
  const DownloadManagerScreen({super.key});

  @override
  ConsumerState<DownloadManagerScreen> createState() =>
      _DownloadManagerScreenState();
}

class _DownloadManagerScreenState extends ConsumerState<DownloadManagerScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(downloadProvider.notifier).loadAll();
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final downloads = ref.watch(downloadProvider);
    final sync = ref.watch(downloadSyncProvider);
    final active = downloads.where((d) => d.isActive).toList();
    final completed =
        downloads.where((d) => d.status == DownloadStatus.completed).toList();
    final history = downloads
        .where((d) =>
            d.status == DownloadStatus.failed ||
            d.status == DownloadStatus.cancelled)
        .toList();

    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      appBar: AppBar(
        title: const Text('Downloads'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.go('/'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.cleaning_services_rounded),
            tooltip: 'Clear finished history',
            onPressed: () => _runAction(context, () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Clear finished history?'),
                  content: const Text(
                      'Removes completed, failed and cancelled entries. Downloaded files remain on the server.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Keep history')),
                    FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Clear history')),
                  ],
                ),
              );
              if (confirmed == true) {
                await ref.read(downloadProvider.notifier).clearCompleted();
              }
            }),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textHint,
          indicatorColor: AppColors.primary,
          tabs: [
            Tab(
                text:
                    'Active${active.isNotEmpty ? ' (${active.length})' : ''}'),
            Tab(
                text:
                    'Completed${completed.isNotEmpty ? ' (${completed.length})' : ''}'),
            const Tab(text: 'History'),
          ],
        ),
      ),
      body: Column(
        children: [
          if (sync.hasError)
            MaterialBanner(
              content: const Text(
                  'Cannot reach the backend. Showing the last known downloads.'),
              actions: [
                TextButton(
                  onPressed: () =>
                      ref.read(downloadProvider.notifier).loadAll(),
                  child: const Text('Retry connection'),
                )
              ],
            ),
          if (sync.isLoading && downloads.isEmpty)
            const LinearProgressIndicator(),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text(
                'Completed means ready on the server. Save to device copies it to Downloads/Fetchio; tap a completed item to save and play.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          ),
          Expanded(
              child: TabBarView(
            controller: _tabs,
            children: [
              _DownloadList(items: active, emptyMessage: 'No active downloads'),
              _DownloadList(
                  items: completed, emptyMessage: 'No completed downloads'),
              _DownloadList(
                  items: history, emptyMessage: 'No download history'),
            ],
          )),
        ],
      ),
    );
  }
}

class _DownloadList extends StatelessWidget {
  const _DownloadList({required this.items, required this.emptyMessage});
  final List<DownloadItem> items;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.download_done_outlined,
                size: 64, color: AppColors.textHint),
            const SizedBox(height: 12),
            Text(emptyMessage,
                style: const TextStyle(color: AppColors.textSecondary)),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _DownloadCard(
              key: ValueKey(items[index].downloadId), item: items[index]),
        );
      },
    );
  }
}

class _DownloadCard extends ConsumerStatefulWidget {
  const _DownloadCard({super.key, required this.item});
  final DownloadItem item;

  @override
  ConsumerState<_DownloadCard> createState() => _DownloadCardState();
}

class _DownloadCardState extends ConsumerState<_DownloadCard> {
  DownloadItem get item => widget.item;
  SavedMedia? _saved;
  bool _saving = false;
  double? _progress;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSaved());
  }

  Future<void> _loadSaved() async {
    if (!mounted) return;
    final service = ref.read(deviceMediaProvider);
    if (!service.supportsLocalFiles) return;
    try {
      final saved = await service
          .find(ref.read(downloadProvider.notifier).fileUri(item.downloadId));
      if (mounted) setState(() => _saved = saved);
    } catch (_) {
      // A failed lookup must not prevent retrying a device save.
    }
  }

  Future<void> _saveOrPlay({required bool play}) async {
    if (_saving) return;
    final service = ref.read(deviceMediaProvider);
    final source = ref.read(downloadProvider.notifier).fileUri(item.downloadId);
    if (!service.supportsLocalFiles) {
      if (!await launchUrl(source, mode: LaunchMode.externalApplication)) {
        throw Exception('Could not open the file download');
      }
      return;
    }
    setState(() {
      _saving = true;
      _progress = null;
    });
    try {
      final saved = await service.save(item, source, onProgress: (value) {
        if (mounted) setState(() => _progress = value);
      });
      if (!mounted) return;
      setState(() => _saved = saved);
      if (play) {
        await service.open(saved);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Saved to Downloads/Fetchio on this device.')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Color _statusColor() {
    switch (item.status) {
      case DownloadStatus.completed:
        return AppColors.success;
      case DownloadStatus.failed:
        return AppColors.error;
      case DownloadStatus.cancelled:
        return AppColors.textSecondary;
      default:
        return AppColors.primary;
    }
  }

  String _speedLabel() {
    if (item.speed == null) return '';
    final s = item.speed!;
    if (s >= 1048576) return '${(s / 1048576).toStringAsFixed(1)} MB/s';
    if (s >= 1024) return '${(s / 1024).toStringAsFixed(0)} KB/s';
    return '${s.toStringAsFixed(0)} B/s';
  }

  String _etaLabel() {
    if (item.eta == null) return '';
    final eta = item.eta!;
    if (eta >= 3600) {
      return '${(eta / 3600).floor()}h ${((eta % 3600) / 60).floor()}m';
    }
    if (eta >= 60) return '${(eta / 60).floor()}m ${eta % 60}s';
    return '${eta}s';
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
        onTap: item.status == DownloadStatus.completed && !_saving
            ? () => _runAction(context, () => _saveOrPlay(play: true))
            : null,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.darkCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: item.isActive
                  ? AppColors.primary.withOpacity(0.3)
                  : AppColors.darkDivider,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (item.thumbnail != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        item.thumbnail!,
                        width: 72,
                        height: 48,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: 72,
                          height: 48,
                          color: AppColors.darkDivider,
                        ),
                      ),
                    )
                  else
                    Container(
                      width: 72,
                      height: 48,
                      decoration: BoxDecoration(
                        color: AppColors.darkDivider,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.movie, color: AppColors.textHint),
                    ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title ?? item.url,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: _statusColor(),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              item.status.name.toUpperCase(),
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: _statusColor(),
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (item.isActive)
                    IconButton(
                      icon: const Icon(Icons.cancel_outlined,
                          color: AppColors.error, size: 20),
                      tooltip: 'Cancel download',
                      onPressed: () => _runAction(
                          context,
                          () => ref
                              .read(downloadProvider.notifier)
                              .cancel(item.downloadId)),
                    ),
                ],
              ),

              if (item.status == DownloadStatus.completed ||
                  item.status == DownloadStatus.failed ||
                  item.status == DownloadStatus.cancelled) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: item.status == DownloadStatus.completed
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            if (_saving) ...[
                              LinearProgressIndicator(value: _progress),
                              Text(_progress == null
                                  ? 'Saving to device…'
                                  : 'Saving to device: ${(_progress! * 100).round()}%'),
                            ] else ...[
                              if (_saved != null)
                                const Text('On device: Downloads/Fetchio',
                                    style: TextStyle(
                                        color: AppColors.success,
                                        fontSize: 12)),
                              Wrap(
                                spacing: 8,
                                children: [
                                  TextButton.icon(
                                    icon: const Icon(Icons.save_alt_rounded),
                                    label: Text(_saved == null
                                        ? (ref
                                                .watch(deviceMediaProvider)
                                                .supportsLocalFiles
                                            ? 'Save to device'
                                            : 'Save file')
                                        : 'Saved on device'),
                                    onPressed: () => _runAction(context,
                                        () => _saveOrPlay(play: false)),
                                  ),
                                  TextButton.icon(
                                    icon: const Icon(Icons.play_circle_outline),
                                    label: const Text('Open player'),
                                    onPressed: () => _runAction(
                                        context, () => _saveOrPlay(play: true)),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        )
                      : TextButton.icon(
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Retry download'),
                          onPressed: () => _runAction(context, () async {
                            await ref
                                .read(downloadProvider.notifier)
                                .retry(item.downloadId);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text(
                                        'Download queued again. Check the Active tab.')),
                              );
                            }
                          }),
                        ),
                ),
              ],

              // Progress bar for active downloads
              if (item.isActive) ...[
                const SizedBox(height: 12),
                LinearPercentIndicator(
                  percent: (item.percent / 100).clamp(0.0, 1.0),
                  lineHeight: 6,
                  backgroundColor: AppColors.darkDivider,
                  progressColor: AppColors.primary,
                  barRadius: const Radius.circular(4),
                  padding: EdgeInsets.zero,
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${item.percent.toStringAsFixed(1)}%',
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 11),
                    ),
                    Row(
                      children: [
                        if (_speedLabel().isNotEmpty) ...[
                          const Icon(Icons.speed,
                              size: 11, color: AppColors.textHint),
                          const SizedBox(width: 2),
                          Text(_speedLabel(),
                              style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 11)),
                        ],
                        if (_etaLabel().isNotEmpty) ...[
                          const SizedBox(width: 8),
                          const Icon(Icons.timer_outlined,
                              size: 11, color: AppColors.textHint),
                          const SizedBox(width: 2),
                          Text(_etaLabel(),
                              style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 11)),
                        ],
                      ],
                    ),
                  ],
                ),
              ],

              // Error message
              if (item.status == DownloadStatus.failed &&
                  item.error != null) ...[
                const SizedBox(height: 8),
                Text(
                  item.error!,
                  style: const TextStyle(color: AppColors.error, fontSize: 11),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ));
  }
}
