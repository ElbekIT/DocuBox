import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:in_app_update/in_app_update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';

class GitHubReleaseInfo {
  final String tagName;
  final String name;
  final String body;
  final String htmlUrl;
  final String? apkDownloadUrl;
  final int? apkSize;

  GitHubReleaseInfo({
    required this.tagName,
    required this.name,
    required this.body,
    required this.htmlUrl,
    this.apkDownloadUrl,
    this.apkSize,
  });

  factory GitHubReleaseInfo.fromJson(Map<String, dynamic> json) {
    String? apkUrl;
    int? size;
    final assets = json['assets'] as List<dynamic>?;
    if (assets != null) {
      for (final asset in assets) {
        final name = asset['name']?.toString() ?? '';
        if (name.endsWith('.apk')) {
          apkUrl = asset['browser_download_url']?.toString();
          size = asset['size'] as int?;
          break;
        }
      }
    }

    return GitHubReleaseInfo(
      tagName: json['tag_name']?.toString() ?? '',
      name: json['name']?.toString() ?? 'New Release',
      body: json['body']?.toString() ?? 'Bug fixes and performance improvements.',
      htmlUrl: json['html_url']?.toString() ?? '',
      apkDownloadUrl: apkUrl,
      apkSize: size,
    );
  }
}

class UpdateService {
  UpdateService._internal();
  static final UpdateService instance = UpdateService._internal();

  static const String gitHubOwner = 'docubox';
  static const String gitHubRepo = 'docubox';

  AppUpdateInfo? _playUpdateInfo;
  bool _flexibleUpdateInProgress = false;

  AppUpdateInfo? get playUpdateInfo => _playUpdateInfo;
  bool get isFlexibleUpdateInProgress => _flexibleUpdateInProgress;

  /// Primary Entry Point: Checks Google Play first, falls back gracefully to GitHub Releases.
  Future<void> checkForUpdates(BuildContext context, {bool silent = false}) async {
    bool playCheckSucceeded = false;

    // 1. Attempt Official Google Play In-App Update
    try {
      final info = await InAppUpdate.checkForUpdate();
      _playUpdateInfo = info;
      playCheckSucceeded = true;

      if (info.updateAvailability == UpdateAvailability.updateAvailable) {
        if (info.immediateUpdateAllowed) {
          await InAppUpdate.performImmediateUpdate();
          return;
        } else if (info.flexibleUpdateAllowed) {
          await _startFlexiblePlayUpdate(context);
          return;
        }
      }
    } catch (e) {
      // In-App update will throw when not installed via Google Play (e.g. Sideload, Debug, GitHub build)
      debugPrint('[UpdateService] Google Play In-App Update check bypassed: $e');
    }

    // 2. Direct Fallback: Check GitHub Releases API endpoint
    try {
      final release = await checkGitHubRelease();
      if (release != null) {
        final isNewer = await _isNewerVersion(release.tagName);
        if (isNewer && context.mounted) {
          _showGitHubUpdateDialog(context, release);
          return;
        }
      }

      if (!silent && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.cardSurfaceLight,
            behavior: SnackBarBehavior.floating,
            content: Row(
              children: const [
                Icon(Icons.check_circle_outline, color: AppTheme.emeraldAccent, size: 20),
                SizedBox(width: 10),
                Text(
                  'DocuBox is fully up to date.',
                  style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('[UpdateService] GitHub Release check failed: $e');
      if (!silent && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.cardSurface,
            content: Text(
              'Could not connect to update servers: $e',
              style: const TextStyle(color: AppTheme.roseAccent),
            ),
          ),
        );
      }
    }
  }

  /// Initiates Flexible Google Play Update with completion snackbar.
  Future<void> _startFlexiblePlayUpdate(BuildContext context) async {
    try {
      _flexibleUpdateInProgress = true;
      await InAppUpdate.startFlexibleUpdate();
      _flexibleUpdateInProgress = false;

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.cardSurfaceLight,
            duration: const Duration(days: 1),
            content: const Text(
              'An update has been downloaded. Restart to apply.',
              style: TextStyle(color: AppTheme.textPrimary),
            ),
            action: SnackBarAction(
              label: 'RESTART',
              textColor: AppTheme.cyanAccent,
              onPressed: () {
                InAppUpdate.completeFlexibleUpdate();
              },
            ),
          ),
        );
      }
    } catch (e) {
      _flexibleUpdateInProgress = false;
      debugPrint('[UpdateService] Flexible update failed: $e');
    }
  }

  /// Queries GitHub Releases API for the latest published tag.
  Future<GitHubReleaseInfo?> checkGitHubRelease() async {
    final uri = Uri.parse('https://api.github.com/repos/$gitHubOwner/$gitHubRepo/releases/latest');
    final response = await http.get(
      uri,
      headers: {'Accept': 'application/vnd.github.v3+json'},
    ).timeout(const Duration(seconds: 8));

    if (response.statusCode == 200) {
      final data = json.decode(response.body) as Map<String, dynamic>;
      return GitHubReleaseInfo.fromJson(data);
    }
    return null;
  }

  /// Compares semantic version strings (e.g., v1.1.0 vs 1.0.0)
  Future<bool> _isNewerVersion(String latestTag) async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      final cleanCurrent = currentVersion.replaceAll(RegExp(r'[^0-9.]'), '');
      final cleanLatest = latestTag.replaceAll(RegExp(r'[^0-9.]'), '');

      final currentParts = cleanCurrent.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      final latestParts = cleanLatest.split('.').map((e) => int.tryParse(e) ?? 0).toList();

      while (currentParts.length < 3) {
        currentParts.add(0);
      }
      while (latestParts.length < 3) {
        latestParts.add(0);
      }

      for (int i = 0; i < 3; i++) {
        if (latestParts[i] > currentParts[i]) return true;
        if (latestParts[i] < currentParts[i]) return false;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// Presents the cybernetic update prompt dialog for direct APK / GitHub install.
  void _showGitHubUpdateDialog(BuildContext context, GitHubReleaseInfo release) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        final sizeMb = release.apkSize != null
            ? ' (${(release.apkSize! / (1024 * 1024)).toStringAsFixed(1)} MB)'
            : '';

        return AlertDialog(
          backgroundColor: AppTheme.cardSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: AppTheme.cyanAccent, width: 1.2),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.cyanAccent.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.system_update_alt, color: AppTheme.cyanAccent, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Update Available',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Tag ${release.tagName}$sizeMb',
                      style: const TextStyle(
                        color: AppTheme.cyanAccent,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 280),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    release.name,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.background,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppTheme.borderSubtle),
                    ),
                    child: Text(
                      release.body.trim().isNotEmpty
                          ? release.body.trim()
                          : 'A new release is ready with performance upgrades and latest security patches.',
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12.5,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Later', style: TextStyle(color: AppTheme.textMuted)),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(ctx).pop();
                final targetUrl = release.apkDownloadUrl ?? release.htmlUrl;
                final uri = Uri.parse(targetUrl);
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
              child: const Text('Download Update'),
            ),
          ],
        );
      },
    );
  }
}
