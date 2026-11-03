import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../core/calibration/screen_calibrator.dart';
import '../core/services/update_service.dart';
import '../core/theme/app_theme.dart';
import 'archive_screen.dart';
import 'document_viewer_screen.dart';
import 'ocr_screen.dart';
import 'pdf_tools_screen.dart';
import 'qr_barcode_screen.dart';
import 'scanner_screen.dart';
import 'vault_screen.dart';

class HomeDashboardScreen extends StatefulWidget {
  const HomeDashboardScreen({super.key});

  @override
  State<HomeDashboardScreen> createState() => _HomeDashboardScreenState();
}

class _HomeDashboardScreenState extends State<HomeDashboardScreen> {
  final List<FileSystemEntity> _recentFiles = [];
  bool _isLoadingRecents = true;

  @override
  void initState() {
    super.initState();
    _loadRecentFiles();

    // Proactive background update check (silent)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      UpdateService.instance.checkForUpdates(context, silent: true);
    });
  }

  Future<void> _loadRecentFiles() async {
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final List<FileSystemEntity> found = [];

      final scanDir = Directory(p.join(docsDir.path, 'DocuBox_Scans'));
      if (await scanDir.exists()) found.addAll(scanDir.listSync());

      final archiveDir = Directory(p.join(docsDir.path, 'DocuBox_Archives'));
      if (await archiveDir.exists()) found.addAll(archiveDir.listSync());

      final convertedDir = Directory(p.join(docsDir.path, 'DocuBox_Converted'));
      if (await convertedDir.exists()) found.addAll(convertedDir.listSync());

      final vaultDir = Directory(p.join(docsDir.path, 'DocuBox_Vault'));
      if (await vaultDir.exists()) found.addAll(vaultDir.listSync());

      final ocrDir = Directory(p.join(docsDir.path, 'DocuBox_OCR'));
      if (await ocrDir.exists()) found.addAll(ocrDir.listSync());

      final pdfToolsDir = Directory(p.join(docsDir.path, 'DocuBox_PdfTools'));
      if (await pdfToolsDir.exists()) found.addAll(pdfToolsDir.listSync());

      // Sort by modified time descending
      found.sort((a, b) {
        final aTime = (a is File) ? a.lastModifiedSync() : DateTime(1970);
        final bTime = (b is File) ? b.lastModifiedSync() : DateTime(1970);
        return bTime.compareTo(aTime);
      });

      setState(() {
        _recentFiles.clear();
        _recentFiles.addAll(found.take(15));
        _isLoadingRecents = false;
      });
    } catch (e) {
      debugPrint('Error loading recents: $e');
      setState(() {
        _isLoadingRecents = false;
      });
    }
  }

  void _openFile(String filePath) {
    final ext = p.extension(filePath).toLowerCase();
    if (ext == '.zip' || ext == '.7z' || ext == '.rar' || ext == '.tar' || ext == '.gz' || ext == '.aes') {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ArchiveScreen(initialArchivePath: filePath)),
      ).then((_) => _loadRecentFiles());
    } else if (ext == '.pdf' || ext == '.docx' || ext == '.xlsx' || ext == '.xls' || ext == '.csv') {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => DocumentViewerScreen(initialFilePath: filePath)),
      ).then((_) => _loadRecentFiles());
    } else {
      OpenFilex.open(filePath);
    }
  }

  Future<void> _pickAnyFileToHandle() async {
    final result = await FilePicker.platform.pickFiles();
    if (result != null && result.files.single.path != null) {
      _openFile(result.files.single.path!);
    }
  }

  void _showCalibrationDialog() {
    final diagnostics = ScreenCalibrator.instance.getDiagnostics();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.cardSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16.r),
          side: const BorderSide(color: AppTheme.cyanAccent),
        ),
        title: Row(
          children: [
            const Icon(Icons.settings_input_composite, color: AppTheme.cyanAccent),
            SizedBox(width: 10.w),
            const Text('Hardware Calibration Matrix', style: TextStyle(color: AppTheme.textPrimary, fontSize: 16)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: diagnostics.entries.map((entry) {
              return Padding(
                padding: EdgeInsets.symmetric(vertical: 4.h),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      entry.key,
                      style: TextStyle(color: AppTheme.textMuted, fontSize: 12.sp),
                    ),
                    Text(
                      entry.value.toString(),
                      style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 12.sp),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ScreenCalibrator.instance.calibrate(context);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 32.r,
              height: 32.r,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8.r),
              ),
              clipBehavior: Clip.antiAlias,
              child: Image.asset('assets/icons/app_icon.png', fit: BoxFit.cover),
            ),
            SizedBox(width: 10.w),
            Text(
              'DocuBox',
              style: TextStyle(
                fontSize: 20.sp,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.system_update_alt_rounded, color: AppTheme.cyanAccent),
            tooltip: 'Check Updates',
            onPressed: () => UpdateService.instance.checkForUpdates(context, silent: false),
          ),
          IconButton(
            icon: const Icon(Icons.tune_rounded, color: AppTheme.textSecondary),
            tooltip: 'Hardware Diagnostics',
            onPressed: _showCalibrationDialog,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ScannerScreen()),
          ).then((_) => _loadRecentFiles());
        },
        backgroundColor: AppTheme.cyanAccent,
        foregroundColor: const Color(0xFF0A0E17),
        icon: const Icon(Icons.camera_alt_rounded),
        label: Text(
          'Quick Scan',
          style: TextStyle(fontSize: 13.5.sp, fontWeight: FontWeight.bold),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _loadRecentFiles,
        color: AppTheme.cyanAccent,
        backgroundColor: AppTheme.cardSurface,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.symmetric(horizontal: 18.w, vertical: 12.h),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Hardware Synergy Status Banner
              GestureDetector(
                onTap: _showCalibrationDialog,
                child: Container(
                  width: double.infinity,
                  padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(14.r),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: EdgeInsets.all(8.r),
                        decoration: BoxDecoration(
                          color: AppTheme.cyanAccent.withOpacity(0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.verified, color: AppTheme.cyanAccent, size: 18.r),
                      ),
                      SizedBox(width: 12.w),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  'CALIBRATION ACTIVE',
                                  style: TextStyle(
                                    color: AppTheme.cyanAccent,
                                    fontSize: 10.5.sp,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                                SizedBox(width: 6.w),
                                Text(
                                  '• ${ScreenCalibrator.instance.formFactor.name}',
                                  style: TextStyle(
                                    color: AppTheme.textMuted,
                                    fontSize: 10.5.sp,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 2.h),
                            Text(
                              'Zero Cutoff Guaranteed • ${ScreenCalibrator.instance.screenWidth.toInt()}x${ScreenCalibrator.instance.screenHeight.toInt()} dp (${ScreenCalibrator.instance.pixelRatio.toStringAsFixed(1)}x)',
                              style: TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 11.5.sp,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right, color: AppTheme.textMuted, size: 20.r),
                    ],
                  ),
                ),
              ),
              SizedBox(height: 20.h),

              // Core Capabilities Section Header
              Text(
                'SUITE CAPABILITIES',
                style: TextStyle(
                  color: AppTheme.textMuted,
                  fontSize: 11.sp,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.0,
                ),
              ),
              SizedBox(height: 12.h),

              // Suite Feature Grid (Expanded Suite)
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                crossAxisSpacing: 12.w,
                mainAxisSpacing: 12.h,
                childAspectRatio: 1.10,
                children: [
                  _buildSuiteCard(
                    title: 'Intelligent Scanner',
                    description: 'Edge correction, shadow removal & PDF compile',
                    icon: Icons.document_scanner_rounded,
                    accentColor: AppTheme.cyanAccent,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const ScannerScreen()),
                      ).then((_) => _loadRecentFiles());
                    },
                  ),
                  _buildSuiteCard(
                    title: 'Universal Archiver',
                    description: 'ZIP, 7Z, RAR, TAR, GZ with AES-256 create/extract',
                    icon: Icons.inventory_2_rounded,
                    accentColor: AppTheme.amberAccent,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const ArchiveScreen()),
                      ).then((_) => _loadRecentFiles());
                    },
                  ),
                  _buildSuiteCard(
                    title: 'Document Reader',
                    description: 'DOCX, XLSX/CSV, PDF & 1-tap PDF converter',
                    icon: Icons.auto_stories_rounded,
                    accentColor: AppTheme.blueAccent,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const DocumentViewerScreen()),
                      ).then((_) => _loadRecentFiles());
                    },
                  ),
                  _buildSuiteCard(
                    title: 'Military Vault',
                    description: '100% offline AES-256 local encrypted container locker',
                    icon: Icons.lock_rounded,
                    accentColor: AppTheme.emeraldAccent,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const VaultScreen()),
                      ).then((_) => _loadRecentFiles());
                    },
                  ),
                  _buildSuiteCard(
                    title: 'Offline OCR Engine',
                    description: 'Extract text on-device from photos & export TXT/PDF',
                    icon: Icons.text_snippet_rounded,
                    accentColor: AppTheme.purpleAccent,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const OcrScreen()),
                      ).then((_) => _loadRecentFiles());
                    },
                  ),
                  _buildSuiteCard(
                    title: 'PDF Studio & Sign',
                    description: 'Watermark, digital sign pad & compress PDF',
                    icon: Icons.draw_rounded,
                    accentColor: AppTheme.roseAccent,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const PdfToolsScreen()),
                      ).then((_) => _loadRecentFiles());
                    },
                  ),
                  _buildSuiteCard(
                    title: 'QR & Wi-Fi Key Hub',
                    description: 'Reveal Wi-Fi passwords from QR & generate codes',
                    icon: Icons.qr_code_scanner_rounded,
                    accentColor: AppTheme.cyanAccent,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const QrBarcodeScreen()),
                      ).then((_) => _loadRecentFiles());
                    },
                  ),
                  _buildSuiteCard(
                    title: 'Hardware Matrix',
                    description: 'Screen calibration & zero-cutoff diagnostics',
                    icon: Icons.tune_rounded,
                    accentColor: AppTheme.amberAccent,
                    onTap: _showCalibrationDialog,
                  ),
                ],
              ),
              SizedBox(height: 24.h),

              // Recent Documents & Archives
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'RECENT SUITE ACTIVITY',
                    style: TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 11.sp,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.0,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _pickAnyFileToHandle,
                    icon: const Icon(Icons.file_open, size: 16),
                    label: const Text('Open File'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.cyanAccent,
                      padding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 8.h),

              if (_isLoadingRecents)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32.0),
                    child: CircularProgressIndicator(color: AppTheme.cyanAccent),
                  ),
                )
              else if (_recentFiles.isEmpty)
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.symmetric(vertical: 36.h, horizontal: 20.w),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(16.r),
                    border: Border.all(color: AppTheme.borderSubtle),
                  ),
                  child: Column(
                    children: [
                      Icon(Icons.folder_open_rounded, size: 48.r, color: AppTheme.textMuted),
                      SizedBox(height: 12.h),
                      Text(
                        'No Recent Documents',
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 14.5.sp,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 4.h),
                      Text(
                        'Scan a document or create an archive to begin.',
                        style: TextStyle(color: AppTheme.textSecondary, fontSize: 12.sp),
                      ),
                    ],
                  ),
                )
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _recentFiles.length,
                  itemBuilder: (ctx, idx) {
                    final item = _recentFiles[idx];
                    final name = p.basename(item.path);
                    final ext = p.extension(item.path).toLowerCase();
                    final stat = item.statSync();

                    return Container(
                      margin: EdgeInsets.only(bottom: 8.h),
                      decoration: BoxDecoration(
                        color: AppTheme.cardSurface,
                        borderRadius: BorderRadius.circular(12.r),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: ListTile(
                        onTap: () => _openFile(item.path),
                        leading: Container(
                          padding: EdgeInsets.all(8.r),
                          decoration: BoxDecoration(
                            color: _getFileBadgeColor(ext).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(8.r),
                          ),
                          child: Icon(_getFileIcon(ext), color: _getFileBadgeColor(ext), size: 20.r),
                        ),
                        title: Text(
                          name,
                          style: TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 13.sp,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${(stat.size / 1024).toStringAsFixed(1)} KB • ${_formatDate(stat.modified)}',
                          style: TextStyle(color: AppTheme.textMuted, fontSize: 11.sp),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.share_outlined, color: AppTheme.textSecondary, size: 18),
                          onPressed: () => Share.shareXFiles([XFile(item.path)]),
                        ),
                      ),
                    );
                  },
                ),
              SizedBox(height: 60.h), // Spacing for floating action button
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSuiteCard({
    required String title,
    required String description,
    required IconData icon,
    required Color accentColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.all(14.w),
        decoration: BoxDecoration(
          color: AppTheme.cardSurface,
          borderRadius: BorderRadius.circular(16.r),
          border: Border.all(color: AppTheme.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              padding: EdgeInsets.all(8.r),
              decoration: BoxDecoration(
                color: accentColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10.r),
              ),
              child: Icon(icon, color: accentColor, size: 22.r),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 13.5.sp,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 2.h),
                Text(
                  description,
                  style: TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 10.5.sp,
                    height: 1.25,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  IconData _getFileIcon(String ext) {
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
      case '.zip':
      case '.7z':
      case '.rar':
      case '.tar':
      case '.gz':
        return Icons.inventory_2;
      case '.aes':
        return Icons.lock;
      case '.txt':
        return Icons.text_snippet;
      default:
        return Icons.insert_drive_file;
    }
  }

  Color _getFileBadgeColor(String ext) {
    switch (ext) {
      case '.pdf':
        return AppTheme.roseAccent;
      case '.docx':
        return AppTheme.blueAccent;
      case '.xlsx':
      case '.csv':
        return AppTheme.emeraldAccent;
      case '.zip':
      case '.7z':
      case '.tar':
        return AppTheme.amberAccent;
      case '.aes':
        return AppTheme.cyanAccent;
      case '.txt':
        return AppTheme.purpleAccent;
      default:
        return AppTheme.textMuted;
    }
  }

  String _formatDate(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
