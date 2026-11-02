import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import '../core/calibration/screen_calibrator.dart';
import '../core/theme/app_theme.dart';
import '../services/archive_service.dart';

class ArchiveScreen extends StatefulWidget {
  final String? initialArchivePath;

  const ArchiveScreen({super.key, this.initialArchivePath});

  @override
  State<ArchiveScreen> createState() => _ArchiveScreenState();
}

class _ArchiveScreenState extends State<ArchiveScreen> {
  String? _currentArchivePath;
  ArchiveMetadata? _metadata;
  bool _isLoading = false;
  String _loadingMessage = '';
  double _extractProgress = 0.0;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    if (widget.initialArchivePath != null) {
      _loadArchive(widget.initialArchivePath!);
    }
  }

  Future<void> _pickAndOpenArchive() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip', '7z', 'rar', 'tar', 'gz', 'tgz', 'bz2', 'aes'],
    );

    if (result != null && result.files.single.path != null) {
      _loadArchive(result.files.single.path!);
    }
  }

  Future<void> _loadArchive(String path, {String? password}) async {
    setState(() {
      _isLoading = true;
      _loadingMessage = 'Inspecting archive structure...';
      _currentArchivePath = path;
    });

    try {
      final meta = await ArchiveService.instance.inspectArchive(path, password: password);
      setState(() {
        _metadata = meta;
      });
    } catch (e) {
      if (mounted) {
        // If error indicates password required, show password dialog
        final errStr = e.toString().toLowerCase();
        if (errStr.contains('password') || errStr.contains('encrypted') || errStr.contains('corrupt')) {
          _promptPasswordAndReload(path);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: AppTheme.cardSurface,
              content: Text('Failed to read archive: $e', style: const TextStyle(color: AppTheme.roseAccent)),
            ),
          );
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadingMessage = '';
        });
      }
    }
  }

  Future<void> _promptPasswordAndReload(String path) async {
    final controller = TextEditingController();
    final pwd = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.cardSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Password Protected Archive', style: TextStyle(color: AppTheme.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This archive is encrypted with military-grade AES / ZIP encryption. Enter password to inspect contents:',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Password',
                prefixIcon: Icon(Icons.lock_outline, color: AppTheme.cyanAccent),
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
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Unlock'),
          ),
        ],
      ),
    );

    if (pwd != null) {
      _loadArchive(path, password: pwd);
    }
  }

  Future<void> _extractArchive() async {
    if (_currentArchivePath == null) return;

    setState(() {
      _isLoading = true;
      _loadingMessage = 'Extracting files...';
      _extractProgress = 0.0;
    });

    try {
      final outDir = await ArchiveService.instance.extractArchive(
        archivePath: _currentArchivePath!,
        onProgress: (progress, currentFile) {
          if (mounted) {
            setState(() {
              _extractProgress = progress;
              _loadingMessage = 'Extracting: ${p.basename(currentFile)}';
            });
          }
        },
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.cardSurfaceLight,
            content: Text('Extracted to: $outDir'),
            action: SnackBarAction(
              label: 'OPEN FOLDER',
              textColor: AppTheme.cyanAccent,
              onPressed: () => OpenFilex.open(outDir),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.cardSurface,
            content: Text('Extraction failed: $e', style: const TextStyle(color: AppTheme.roseAccent)),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadingMessage = '';
          _extractProgress = 0.0;
        });
      }
    }
  }

  Future<void> _showCreateArchiveDialog() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
    );

    if (result == null || result.paths.isEmpty) return;
    final filePaths = result.paths.whereType<String>().toList();

    final nameController = TextEditingController(text: 'Archive_${DateTime.now().millisecondsSinceEpoch}');
    final passwordController = TextEditingController();
    bool useAes256 = true;

    if (!mounted) return;

    final shouldCreate = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            backgroundColor: AppTheme.cardSurface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('Create Protected Archive', style: TextStyle(color: AppTheme.textPrimary)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Compressing ${filePaths.length} items with ZArchiver-grade engine.',
                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: 'Archive Name'),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Password (Optional)',
                      prefixIcon: Icon(Icons.vpn_key_outlined, color: AppTheme.cyanAccent),
                    ),
                  ),
                  const SizedBox(height: 14),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Military-Grade AES-256', style: TextStyle(fontSize: 14, color: AppTheme.textPrimary)),
                    subtitle: const Text('PBKDF2-HMAC-SHA256 + AES-GCM 256 Container', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                    value: useAes256,
                    activeColor: AppTheme.cyanAccent,
                    onChanged: (val) {
                      setDialogState(() {
                        useAes256 = val;
                      });
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel', style: TextStyle(color: AppTheme.textMuted)),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Compress & Save'),
              ),
            ],
          );
        },
      ),
    );

    if (shouldCreate != true) return;

    setState(() {
      _isLoading = true;
      _loadingMessage = 'Compressing and securing archive...';
    });

    try {
      final createdArchive = await ArchiveService.instance.createArchive(
        sourceFilePaths: filePaths,
        outputArchiveName: nameController.text.trim(),
        password: passwordController.text.isNotEmpty ? passwordController.text : null,
        useAes256: useAes256,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.cardSurfaceLight,
            content: Text('Archive Created: ${p.basename(createdArchive.path)}'),
            action: SnackBarAction(
              label: 'SHARE',
              textColor: AppTheme.cyanAccent,
              onPressed: () => Share.shareXFiles([XFile(createdArchive.path)]),
            ),
          ),
        );
        _loadArchive(createdArchive.path);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.cardSurface,
            content: Text('Compression failed: $e', style: const TextStyle(color: AppTheme.roseAccent)),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadingMessage = '';
        });
      }
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  @override
  Widget build(BuildContext context) {
    ScreenCalibrator.instance.calibrate(context);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Universal Archiver'),
        actions: [
          IconButton(
            icon: const Icon(Icons.create_new_folder_outlined),
            tooltip: 'Create New Archive',
            onPressed: _showCreateArchiveDialog,
          ),
          IconButton(
            icon: const Icon(Icons.file_open_outlined),
            tooltip: 'Open Archive File',
            onPressed: _pickAndOpenArchive,
          ),
        ],
      ),
      body: Stack(
        children: [
          _metadata == null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.inventory_2_outlined, size: 70.r, color: AppTheme.cyanAccent.withOpacity(0.6)),
                      SizedBox(height: 16.h),
                      Text(
                        'ZArchiver-Grade Engine',
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 18.sp,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 8.h),
                      Text(
                        'Open, inspect, create, and extract ZIP, 7Z, RAR, TAR, GZ',
                        style: TextStyle(color: AppTheme.textSecondary, fontSize: 13.sp),
                      ),
                      SizedBox(height: 24.h),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ElevatedButton.icon(
                            onPressed: _pickAndOpenArchive,
                            icon: const Icon(Icons.folder_open),
                            label: const Text('Open Archive'),
                          ),
                          SizedBox(width: 12.w),
                          OutlinedButton.icon(
                            onPressed: _showCreateArchiveDialog,
                            icon: const Icon(Icons.archive_outlined),
                            label: const Text('Create Archive'),
                          ),
                        ],
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    // Archive Header Telemetry Card
                    Container(
                      margin: EdgeInsets.all(16.w),
                      padding: EdgeInsets.all(16.w),
                      decoration: BoxDecoration(
                        color: AppTheme.cardSurface,
                        borderRadius: BorderRadius.circular(16.r),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                                decoration: BoxDecoration(
                                  color: AppTheme.cyanAccent.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(6.r),
                                ),
                                child: Text(
                                  _metadata!.format,
                                  style: TextStyle(
                                    color: AppTheme.cyanAccent,
                                    fontSize: 11.sp,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              SizedBox(width: 10.w),
                              Expanded(
                                child: Text(
                                  p.basename(_currentArchivePath ?? ''),
                                  style: TextStyle(
                                    color: AppTheme.textPrimary,
                                    fontSize: 14.sp,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 12.h),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _buildMetricItem('Files', '${_metadata!.totalFiles}'),
                              _buildMetricItem('Folders', '${_metadata!.totalDirectories}'),
                              _buildMetricItem('Uncompressed', _formatBytes(_metadata!.totalUncompressedBytes)),
                              _buildMetricItem('Packed', _formatBytes(_metadata!.totalCompressedBytes)),
                            ],
                          ),
                          SizedBox(height: 14.h),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: _extractArchive,
                                  icon: const Icon(Icons.unarchive_outlined),
                                  label: const Text('Extract All'),
                                ),
                              ),
                              SizedBox(width: 10.w),
                              IconButton.outlined(
                                icon: const Icon(Icons.share_outlined, color: AppTheme.cyanAccent),
                                onPressed: () {
                                  if (_currentArchivePath != null) {
                                    Share.shareXFiles([XFile(_currentArchivePath!)]);
                                  }
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Search / Filter inside Archive
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16.w),
                      child: TextField(
                        decoration: InputDecoration(
                          hintText: 'Filter archive files...',
                          prefixIcon: const Icon(Icons.search, color: AppTheme.textMuted),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
                        ),
                        onChanged: (val) {
                          setState(() {
                            _searchQuery = val.trim().toLowerCase();
                          });
                        },
                      ),
                    ),
                    SizedBox(height: 8.h),

                    // Hierarchy Tree View
                    Expanded(
                      child: ListView.builder(
                        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
                        itemCount: _filteredNodes.length,
                        itemBuilder: (ctx, idx) {
                          return _buildNodeTile(_filteredNodes[idx], 0);
                        },
                      ),
                    ),
                  ],
                ),

          // Loading & Progress Indicator
          if (_isLoading)
            Container(
              color: Colors.black.withOpacity(0.7),
              child: Center(
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 20.h),
                  decoration: BoxDecoration(
                    color: AppTheme.cardSurface,
                    borderRadius: BorderRadius.circular(16.r),
                    border: Border.all(color: AppTheme.cyanAccent),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(color: AppTheme.cyanAccent),
                      SizedBox(height: 16.h),
                      Text(
                        _loadingMessage,
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 13.5.sp,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (_extractProgress > 0) ...[
                        SizedBox(height: 10.h),
                        LinearProgressIndicator(
                          value: _extractProgress,
                          backgroundColor: AppTheme.surface,
                          color: AppTheme.cyanAccent,
                        ),
                        SizedBox(height: 6.h),
                        Text(
                          '${(_extractProgress * 100).toInt()}%',
                          style: TextStyle(color: AppTheme.textSecondary, fontSize: 11.sp),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<ArchiveNode> get _filteredNodes {
    if (_metadata == null) return [];
    if (_searchQuery.isEmpty) return _metadata!.rootNodes;

    List<ArchiveNode> filterRecursive(List<ArchiveNode> list) {
      final List<ArchiveNode> res = [];
      for (final n in list) {
        if (n.name.toLowerCase().contains(_searchQuery)) {
          res.add(n);
        } else if (n.isDirectory) {
          final matchedKids = filterRecursive(n.children);
          if (matchedKids.isNotEmpty) {
            res.add(ArchiveNode(
              path: n.path,
              name: n.name,
              isDirectory: true,
              uncompressedSize: n.uncompressedSize,
              compressedSize: n.compressedSize,
              children: matchedKids,
            ));
          }
        }
      }
      return res;
    }

    return filterRecursive(_metadata!.rootNodes);
  }

  Widget _buildMetricItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: AppTheme.textMuted, fontSize: 10.5.sp)),
        SizedBox(height: 2.h),
        Text(value, style: TextStyle(color: AppTheme.textPrimary, fontSize: 12.sp, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildNodeTile(ArchiveNode node, int depth) {
    if (node.isDirectory) {
      return ExpansionTile(
        tilePadding: EdgeInsets.only(left: (depth * 16.0) + 8.0, right: 8.0),
        leading: Icon(Icons.folder_rounded, color: AppTheme.amberAccent, size: 20.r),
        title: Text(
          node.name,
          style: TextStyle(color: AppTheme.textPrimary, fontSize: 13.sp, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${node.children.length} items',
          style: TextStyle(color: AppTheme.textMuted, fontSize: 10.5.sp),
        ),
        children: node.children.map((child) => _buildNodeTile(child, depth + 1)).toList(),
      );
    } else {
      return ListTile(
        contentPadding: EdgeInsets.only(left: (depth * 16.0) + 8.0, right: 8.0),
        leading: Icon(
          _getFileIcon(node.name),
          color: _getFileColor(node.name),
          size: 18.r,
        ),
        title: Text(
          node.name,
          style: TextStyle(color: AppTheme.textPrimary, fontSize: 12.5.sp),
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${_formatBytes(node.uncompressedSize)} • Ratio: ${node.compressionRatio.toStringAsFixed(0)}%',
          style: TextStyle(color: AppTheme.textMuted, fontSize: 10.5.sp),
        ),
        trailing: node.isEncrypted
            ? const Icon(Icons.lock, color: AppTheme.cyanAccent, size: 14)
            : null,
      );
    }
  }

  IconData _getFileIcon(String filename) {
    final ext = p.extension(filename).toLowerCase();
    switch (ext) {
      case '.pdf':
        return Icons.picture_as_pdf;
      case '.docx':
      case '.doc':
        return Icons.description;
      case '.xlsx':
      case '.xls':
      case '.csv':
        return Icons.table_chart;
      case '.png':
      case '.jpg':
      case '.jpeg':
        return Icons.image;
      case '.txt':
      case '.json':
      case '.xml':
        return Icons.code;
      default:
        return Icons.insert_drive_file_outlined;
    }
  }

  Color _getFileColor(String filename) {
    final ext = p.extension(filename).toLowerCase();
    switch (ext) {
      case '.pdf':
        return AppTheme.roseAccent;
      case '.docx':
      case '.doc':
        return AppTheme.blueAccent;
      case '.xlsx':
      case '.xls':
      case '.csv':
        return AppTheme.emeraldAccent;
      case '.png':
      case '.jpg':
      case '.jpeg':
        return AppTheme.purpleAccent;
      default:
        return AppTheme.cyanAccent;
    }
  }
}
