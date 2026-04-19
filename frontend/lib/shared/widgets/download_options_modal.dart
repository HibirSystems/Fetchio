import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/models/media_info.dart';

class DownloadOptionsModal extends StatefulWidget {
  const DownloadOptionsModal({
    super.key,
    required this.mediaInfo,
    required this.onDownload,
  });

  final MediaInfo mediaInfo;
  final void Function(Map<String, dynamic> request) onDownload;

  @override
  State<DownloadOptionsModal> createState() => _DownloadOptionsModalState();
}

class _DownloadOptionsModalState extends State<DownloadOptionsModal> {
  String _mode = 'video'; // 'video' | 'audio'
  String? _selectedFormatId;
  String _audioFormat = 'mp3';
  final String _quality = 'best';
  bool _embedThumbnail = true;

  // Sensible video quality options derived from available formats
  List<_QualityOption> get _videoOptions {
    final seen = <String>{};
    final opts = <_QualityOption>[];

    for (final f in widget.mediaInfo.formats) {
      if (f.vcodec == null || f.vcodec == 'none') continue;
      final res = f.resolution ?? f.formatNote ?? f.formatId;
      if (seen.contains(res)) continue;
      seen.add(res);
      opts.add(_QualityOption(label: res, formatId: f.formatId));
    }

    if (opts.isEmpty) {
      opts.add(const _QualityOption(label: 'Best Available', formatId: null));
    }

    return opts;
  }

  void _startDownload() {
    final req = <String, dynamic>{
      'url': widget.mediaInfo.url.isNotEmpty
          ? widget.mediaInfo.url
          : widget.mediaInfo.webpageUrl ?? widget.mediaInfo.url,
      'audio_only': _mode == 'audio',
      if (_mode == 'audio') 'convert_to': _audioFormat,
      if (_mode == 'video' && _selectedFormatId != null)
        'format_id': _selectedFormatId,
      'embed_thumbnail': _embedThumbnail,
    };
    widget.onDownload(req);
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottomPadding),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.darkDivider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Title
          const Text('Download Options', style: AppTextStyles.headlineMedium),
          const SizedBox(height: 4),
          Text(
            widget.mediaInfo.title,
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 20),

          // Mode toggle
          Row(
            children: [
              Expanded(child: _ModeChip(
                label: 'Video',
                icon: Icons.videocam_outlined,
                selected: _mode == 'video',
                onTap: () => setState(() => _mode = 'video'),
              )),
              const SizedBox(width: 8),
              Expanded(child: _ModeChip(
                label: 'Audio Only',
                icon: Icons.audiotrack_outlined,
                selected: _mode == 'audio',
                onTap: () => setState(() => _mode = 'audio'),
              )),
            ],
          ),
          const SizedBox(height: 16),

          // Video quality picker
          if (_mode == 'video') ...[
            const Text('Quality', style: AppTextStyles.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _videoOptions.map((opt) {
                final selected = _selectedFormatId == opt.formatId;
                return ChoiceChip(
                  label: Text(opt.label),
                  selected: selected,
                  onSelected: (_) =>
                      setState(() => _selectedFormatId = opt.formatId),
                );
              }).toList(),
            ),
          ],

          // Audio format picker
          if (_mode == 'audio') ...[
            const Text('Format', style: AppTextStyles.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: ['mp3', 'm4a', 'opus', 'flac'].map((fmt) {
                return ChoiceChip(
                  label: Text(fmt.toUpperCase()),
                  selected: _audioFormat == fmt,
                  onSelected: (_) => setState(() => _audioFormat = fmt),
                );
              }).toList(),
            ),
          ],

          const SizedBox(height: 16),

          // Options row
          Row(
            children: [
              const Icon(Icons.image_outlined,
                  size: 16, color: AppColors.textHint),
              const SizedBox(width: 6),
              const Text('Embed thumbnail',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
              const Spacer(),
              Switch(
                value: _embedThumbnail,
                onChanged: (v) => setState(() => _embedThumbnail = v),
                activeThumbColor: AppColors.primary,
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Download button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _startDownload,
              icon: const Icon(Icons.download_rounded),
              label: const Text('Start Download'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary.withOpacity(0.15) : AppColors.darkCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.darkDivider,
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 18,
                color: selected ? AppColors.primary : AppColors.textHint),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected ? AppColors.primary : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QualityOption {
  const _QualityOption({required this.label, required this.formatId});
  final String label;
  final String? formatId;
}
