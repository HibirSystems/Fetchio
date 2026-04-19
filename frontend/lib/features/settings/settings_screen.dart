import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/engine/binary_manager.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/settings_provider.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  String _appVersion = '';

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _appVersion = info.version);
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      appBar: AppBar(
        title: const Text('Settings'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.go('/'),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Appearance ────────────────────────────────────────────────────
          const _SectionHeader(title: 'Appearance'),
          _SettingsTile(
            icon: Icons.dark_mode_outlined,
            title: 'Theme',
            subtitle: settings.themeMode == 'dark' ? 'Dark' : 'Light',
            trailing: Switch(
              value: settings.themeMode == 'dark',
              onChanged: (v) =>
                  notifier.setThemeMode(v ? 'dark' : 'light'),
              activeColor: AppColors.primary,
            ),
          ),

          const SizedBox(height: 16),

          // ── Downloads ─────────────────────────────────────────────────────
          const _SectionHeader(title: 'Downloads'),
          _SettingsTile(
            icon: Icons.audiotrack_outlined,
            title: 'Audio Only',
            subtitle: 'Download audio instead of video by default',
            trailing: Switch(
              value: settings.audioOnly,
              onChanged: notifier.setAudioOnly,
              activeColor: AppColors.primary,
            ),
          ),
          _SettingsTile(
            icon: Icons.high_quality_outlined,
            title: 'Preferred Quality',
            subtitle: settings.preferredQuality == '1080'
                ? '1080p (Full HD)'
                : settings.preferredQuality == '720'
                    ? '720p (HD)'
                    : settings.preferredQuality == '480'
                        ? '480p (SD)'
                        : 'Best Available',
            onTap: () => _showQualityPicker(context, settings, notifier),
          ),
          _SettingsTile(
            icon: Icons.image_outlined,
            title: 'Embed Thumbnail',
            subtitle: 'Add thumbnail to downloaded files',
            trailing: Switch(
              value: settings.embedThumbnail,
              onChanged: notifier.setEmbedThumbnail,
              activeColor: AppColors.primary,
            ),
          ),

          const SizedBox(height: 16),

          // ── Engine ────────────────────────────────────────────────────────
          const _SectionHeader(title: 'Engine'),
          _SettingsTile(
            icon: Icons.settings_applications_outlined,
            title: 'yt-dlp (bundled)',
            subtitle: BinaryManager.instance.isReady
                ? 'Binary ready — runs fully on-device'
                : 'Binary not yet extracted',
            trailing: Icon(
              BinaryManager.instance.isReady
                  ? Icons.check_circle
                  : Icons.hourglass_empty,
              color: BinaryManager.instance.isReady
                  ? AppColors.success
                  : AppColors.warning,
            ),
          ),

          const SizedBox(height: 16),

          // ── About ─────────────────────────────────────────────────────────
          const _SectionHeader(title: 'About'),
          _SettingsTile(
            icon: Icons.info_outline,
            title: 'Version',
            subtitle: _appVersion.isNotEmpty ? _appVersion : '1.0.0',
          ),
          const _SettingsTile(
            icon: Icons.code_outlined,
            title: 'Powered by yt-dlp',
            subtitle: 'Open-source media extraction engine — 1000+ sites',
          ),
        ],
      ),
    );
  }

  void _showQualityPicker(
    BuildContext context,
    AppSettings settings,
    SettingsNotifier notifier,
  ) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.darkSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) {
        final options = [
          ('best', 'Best Available'),
          ('1080', '1080p (Full HD)'),
          ('720', '720p (HD)'),
          ('480', '480p (SD)'),
          ('360', '360p'),
        ];
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Preferred Quality',
                  style: AppTextStyles.headlineMedium),
              const SizedBox(height: 16),
              ...options.map(
                (opt) => RadioListTile<String>(
                  value: opt.$1,
                  groupValue: settings.preferredQuality,
                  title: Text(opt.$2,
                      style:
                          const TextStyle(color: AppColors.textPrimary)),
                  activeColor: AppColors.primary,
                  onChanged: (v) {
                    if (v != null) {
                      notifier.setPreferredQuality(v);
                      Navigator.of(context).pop();
                    }
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          color: AppColors.primary,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: AppColors.darkCard,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: Icon(icon, color: AppColors.primary, size: 22),
        title: Text(title,
            style: const TextStyle(
                color: AppColors.textPrimary, fontSize: 14)),
        subtitle: subtitle != null
            ? Text(subtitle!,
                style: const TextStyle(
                    color: AppColors.textHint, fontSize: 12))
            : null,
        trailing: trailing ??
            (onTap != null
                ? const Icon(Icons.chevron_right,
                    color: AppColors.textHint)
                : null),
        onTap: onTap,
      ),
    );
  }
}
