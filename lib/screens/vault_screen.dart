import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../core/calibration/screen_calibrator.dart';
import '../core/theme/app_theme.dart';
import '../services/archive_service.dart';

class VaultScreen extends StatefulWidget {
  const VaultScreen({super.key});

  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends State<VaultScreen> {
  final List<FileSystemEntity> _vaultFiles = [];
  bool _isLoading = false;
  String _statusMessage = '';

  @override
  void initState() {
    super.initState();
    _refreshVault();
  }

  Future<void> _refreshVault() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final vaultDir = Directory(p.join(docsDir.path, 'DocuBox_Vault'));
    if (!await vaultDir.exists()) {
      await vaultDir.create(recursive: true);
    }

    final entities = vaultDir.listSync();
    setState(() {
      _vaultFiles.clear();
      _vaultFiles.addAll(entities);
    });
  }

  Future<void> _encryptNewFile() async {
    final result = await FilePicker.platform.pickFiles();
    if (result == null || result.files.single.path == null) return;

    final filePath = result.files.single.path!;
    final passwordController = TextEditingController();

    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.cardSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Encrypt File with AES-256', style: TextStyle(color: AppTheme.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'File: ${p.basename(filePath)}',
              style: const TextStyle(color: AppTheme.cyanAccent, fontWeight: FontWeight.bold, fontSize: 13),
            ),
            const SizedBox(height: 12),
            const Text(
              'Armed with PBKDF2-HMAC-SHA256 (10,000 iterations) + AES-GCM 256. Zero cloud telemetry.',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: passwordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Master Encryption Password',
                prefixIcon: Icon(Icons.shield_outlined, color: AppTheme.emeraldAccent),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: AppTheme.textMuted)),
          ),
          ElevatedButton(
            onPressed: () {
              if (passwordController.text.trim().isNotEmpty) {
                Navigator.pop(ctx, true);
              }
            },
            child: const Text('Lock & Encrypt'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isLoading = true;
      _statusMessage = 'Encrypting container with AES-256...';
    });

    try {
      final sourceFile = File(filePath);

      // Bundle into archive format and encrypt container
      final createdArchive = await ArchiveService.instance.createArchive(
        sourceFilePaths: [filePath],
        outputArchiveName: 'Vault_${p.basenameWithoutExtension(filePath)}',
        password: passwordController.text,
        useAes256: true,
      );

      // Move into vault dir
      final docsDir = await getApplicationDocumentsDirectory();
      final vaultDir = Directory(p.join(docsDir.path, 'DocuBox_Vault'));
      final targetFile = File(p.join(vaultDir.path, p.basename(createdArchive.path)));
      await createdArchive.copy(targetFile.path);
      await createdArchive.delete();

      await _refreshVault();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.cardSurfaceLight,
            content: Text('File locked securely: ${p.basename(targetFile.path)}'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.cardSurface,
            content: Text('Encryption error: $e', style: const TextStyle(color: AppTheme.roseAccent)),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _statusMessage = '';
        });
      }
    }
  }

  Future<void> _unlockAndDecrypt(File file) async {
    final passwordController = TextEditingController();

    final pwd = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.cardSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Unlock Encrypted Container', style: TextStyle(color: AppTheme.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Container: ${p.basename(file.path)}', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
            const SizedBox(height: 16),
            TextField(
              controller: passwordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Enter Password',
                prefixIcon: Icon(Icons.key, color: AppTheme.cyanAccent),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('Cancel', style: TextStyle(color: AppTheme.textMuted)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, passwordController.text),
            child: const Text('Unlock'),
          ),
        ],
      ),
    );

    if (pwd == null || pwd.isEmpty) return;

    setState(() {
      _isLoading = true;
      _statusMessage = 'Verifying cryptographic authentication tag...';
    });

    try {
      final cipherBytes = await file.readAsBytes();
      final decryptedZipBytes = ArchiveService.instance.decryptContainerAes256(cipherBytes, pwd);

      final tempDir = await getTemporaryDirectory();
      final tempZip = File(p.join(tempDir.path, 'temp_unlocked.zip'));
      await tempZip.writeAsBytes(decryptedZipBytes);

      final outDir = await ArchiveService.instance.extractArchive(
        archivePath: tempZip.path,
        password: pwd,
      );

      await tempZip.delete();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.cardSurfaceLight,
            content: Text('Decrypted successfully to: $outDir'),
            action: SnackBarAction(
              label: 'OPEN',
              textColor: AppTheme.cyanAccent,
              onPressed: () => OpenFilex.open(outDir),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: AppTheme.cardSurface,
            content: Text('Decryption failed: Incorrect password or corrupted authentication tag.', style: TextStyle(color: AppTheme.roseAccent)),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _statusMessage = '';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ScreenCalibrator.instance.calibrate(context);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Encrypted Vault'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_moderator_outlined),
            tooltip: 'Encrypt New Document',
            onPressed: _encryptNewFile,
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              // Security Telemetry Banner
              Container(
                margin: EdgeInsets.all(16.w),
                padding: EdgeInsets.all(16.w),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppTheme.cardSurface,
                      AppTheme.emeraldAccent.withOpacity(0.08),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(16.r),
                  border: Border.all(color: AppTheme.emeraldAccent.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(10.r),
                      decoration: BoxDecoration(
                        color: AppTheme.emeraldAccent.withOpacity(0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.lock, color: AppTheme.emeraldAccent, size: 24.r),
                    ),
                    SizedBox(width: 14.w),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Military-Grade Local Vault',
                            style: TextStyle(
                              color: AppTheme.textPrimary,
                              fontSize: 14.5.sp,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 2.h),
                          Text(
                            'AES-GCM-256 • 10,000 PBKDF2 Rounds • 100% Offline',
                            style: TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 11.5.sp,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // File List
              Expanded(
                child: _vaultFiles.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.enhanced_encryption_outlined, size: 64.r, color: AppTheme.textMuted),
                            SizedBox(height: 16.h),
                            Text(
                              'Vault is Empty',
                              style: TextStyle(color: AppTheme.textPrimary, fontSize: 16.sp, fontWeight: FontWeight.bold),
                            ),
                            SizedBox(height: 6.h),
                            Text(
                              'No encrypted containers stored yet.',
                              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13.sp),
                            ),
                            SizedBox(height: 20.h),
                            ElevatedButton.icon(
                              onPressed: _encryptNewFile,
                              icon: const Icon(Icons.lock_outline),
                              label: const Text('Lock a Document'),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: EdgeInsets.symmetric(horizontal: 16.w),
                        itemCount: _vaultFiles.length,
                        itemBuilder: (ctx, idx) {
                          final file = _vaultFiles[idx] as File;
                          return Container(
                            margin: EdgeInsets.only(bottom: 10.h),
                            decoration: BoxDecoration(
                              color: AppTheme.cardSurface,
                              borderRadius: BorderRadius.circular(12.r),
                              border: Border.all(color: AppTheme.border),
                            ),
                            child: ListTile(
                              leading: const Icon(Icons.lock, color: AppTheme.emeraldAccent),
                              title: Text(
                                p.basename(file.path),
                                style: TextStyle(color: AppTheme.textPrimary, fontSize: 13.sp, fontWeight: FontWeight.bold),
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                '${(file.lengthSync() / 1024).toStringAsFixed(1)} KB • Encrypted Container',
                                style: TextStyle(color: AppTheme.textMuted, fontSize: 11.sp),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.lock_open_rounded, color: AppTheme.cyanAccent),
                                    tooltip: 'Unlock & Decrypt',
                                    onPressed: () => _unlockAndDecrypt(file),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.share_outlined, color: AppTheme.textSecondary),
                                    tooltip: 'Share',
                                    onPressed: () => Share.shareXFiles([XFile(file.path)]),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, color: AppTheme.roseAccent),
                                    tooltip: 'Delete',
                                    onPressed: () async {
                                      await file.delete();
                                      _refreshVault();
                                    },
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),

          if (_isLoading)
            Container(
              color: Colors.black.withOpacity(0.7),
              child: Center(
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 20.h),
                  decoration: BoxDecoration(
                    color: AppTheme.cardSurface,
                    borderRadius: BorderRadius.circular(16.r),
                    border: Border.all(color: AppTheme.emeraldAccent),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(color: AppTheme.emeraldAccent),
                      SizedBox(height: 16.h),
                      Text(
                        _statusMessage,
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 13.5.sp,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
