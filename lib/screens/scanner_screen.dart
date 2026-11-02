import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
import '../core/calibration/screen_calibrator.dart';
import '../core/theme/app_theme.dart';
import '../services/scanner_service.dart';

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  final List<ScannedPage> _pages = [];
  int _selectedPageIndex = 0;
  bool _isProcessing = false;
  String _statusMessage = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _triggerScan();
    });
  }

  Future<void> _triggerScan() async {
    setState(() {
      _isProcessing = true;
      _statusMessage = 'Launching Intelligent Scanner...';
    });

    try {
      final imagePaths = await ScannerService.instance.startMLKitScan();
      if (imagePaths.isNotEmpty) {
        for (final path in imagePaths) {
          _pages.add(ScannedPage(
            originalPath: path,
            processedPath: path,
            activeFilter: ScanFilterType.original,
          ));
        }
        _selectedPageIndex = _pages.length - 1;
      }
    } catch (e) {
      debugPrint('Scan error: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _statusMessage = '';
        });
      }
    }
  }

  Future<void> _pickImagesFromGallery() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
    );

    if (result != null && result.paths.isNotEmpty) {
      setState(() {
        for (final p in result.paths) {
          if (p != null) {
            _pages.add(ScannedPage(
              originalPath: p,
              processedPath: p,
              activeFilter: ScanFilterType.original,
            ));
          }
        }
        if (_pages.isNotEmpty) {
          _selectedPageIndex = _pages.length - 1;
        }
      });
    }
  }

  Future<void> _applyFilterToCurrent(ScanFilterType filter) async {
    if (_pages.isEmpty) return;

    final currentPage = _pages[_selectedPageIndex];
    if (currentPage.activeFilter == filter && currentPage.rotationDegrees == 0) return;

    setState(() {
      _isProcessing = true;
      _statusMessage = 'Applying ${filter.name} filter...';
    });

    try {
      final processedPath = await ScannerService.instance.applyFilter(
        imagePath: currentPage.originalPath,
        filterType: filter,
        rotationDegrees: currentPage.rotationDegrees,
      );

      setState(() {
        currentPage.processedPath = processedPath;
        currentPage.activeFilter = filter;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Filter error: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _statusMessage = '';
        });
      }
    }
  }

  Future<void> _rotateCurrentPage() async {
    if (_pages.isEmpty) return;
    final page = _pages[_selectedPageIndex];
    page.rotationDegrees = (page.rotationDegrees + 90) % 360;

    setState(() {
      _isProcessing = true;
      _statusMessage = 'Rotating page...';
    });

    try {
      final rotatedPath = await ScannerService.instance.applyFilter(
        imagePath: page.originalPath,
        filterType: page.activeFilter,
        rotationDegrees: page.rotationDegrees,
      );
      setState(() {
        page.processedPath = rotatedPath;
      });
    } catch (e) {
      debugPrint('Rotate error: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _statusMessage = '';
        });
      }
    }
  }

  void _deleteCurrentPage() {
    if (_pages.isEmpty) return;
    setState(() {
      _pages.removeAt(_selectedPageIndex);
      if (_selectedPageIndex >= _pages.length && _pages.isNotEmpty) {
        _selectedPageIndex = _pages.length - 1;
      }
    });
  }

  Future<void> _exportToPdf() async {
    if (_pages.isEmpty) return;

    final controller = TextEditingController(
      text: 'Scan_${DateTime.now().year}${DateTime.now().month.toString().padLeft(2, '0')}${DateTime.now().day.toString().padLeft(2, '0')}_${DateTime.now().hour}${DateTime.now().minute}',
    );

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.cardSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Compile Multi-Page PDF', style: TextStyle(color: AppTheme.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Compiling ${_pages.length} scanned pages into a vectorized PDF document.',
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Document Name',
                suffixText: '.pdf',
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
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Compile & Save'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isProcessing = true;
      _statusMessage = 'Compiling vector PDF document...';
    });

    try {
      final paths = _pages.map((p) => p.processedPath).toList();
      final pdfFile = await ScannerService.instance.compileToPdf(
        imagePaths: paths,
        outputFileName: controller.text.trim(),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.cardSurfaceLight,
            content: Text('Saved: ${pdfFile.path.split('/').last}'),
            action: SnackBarAction(
              label: 'SHARE',
              textColor: AppTheme.cyanAccent,
              onPressed: () {
                Share.shareXFiles([XFile(pdfFile.path)], text: 'Scanned with DocuBox');
              },
            ),
          ),
        );

        OpenFilex.open(pdfFile.path);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF Compilation error: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
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
        title: const Text('Intelligent Scanner'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_photo_alternate_outlined),
            tooltip: 'Import from Gallery',
            onPressed: _pickImagesFromGallery,
          ),
          IconButton(
            icon: const Icon(Icons.camera_alt_outlined),
            tooltip: 'Scan New Page',
            onPressed: _triggerScan,
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              // Main Preview Area
              Expanded(
                child: _pages.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.document_scanner_rounded, size: 72.r, color: AppTheme.textMuted),
                            SizedBox(height: 16.h),
                            Text(
                              'No Scanned Pages',
                              style: TextStyle(
                                color: AppTheme.textPrimary,
                                fontSize: 18.sp,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(height: 8.h),
                            Text(
                              'Tap the camera button to start scanning documents.',
                              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13.sp),
                            ),
                            SizedBox(height: 24.h),
                            ElevatedButton.icon(
                              onPressed: _triggerScan,
                              icon: const Icon(Icons.camera),
                              label: const Text('Start Camera Scan'),
                            ),
                          ],
                        ),
                      )
                    : Container(
                        margin: EdgeInsets.all(16.w),
                        decoration: BoxDecoration(
                          color: AppTheme.surface,
                          borderRadius: BorderRadius.circular(16.r),
                          border: Border.all(color: AppTheme.border),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            InteractiveViewer(
                              maxScale: 4.0,
                              child: Image.file(
                                File(_pages[_selectedPageIndex].processedPath),
                                fit: BoxFit.contain,
                              ),
                            ),
                            Positioned(
                              top: 12.h,
                              right: 12.w,
                              child: Row(
                                children: [
                                  IconButton.filledTonal(
                                    icon: const Icon(Icons.rotate_right_rounded),
                                    onPressed: _rotateCurrentPage,
                                    tooltip: 'Rotate 90°',
                                  ),
                                  SizedBox(width: 8.w),
                                  IconButton.filledTonal(
                                    icon: const Icon(Icons.delete_outline, color: AppTheme.roseAccent),
                                    onPressed: _deleteCurrentPage,
                                    tooltip: 'Delete Page',
                                  ),
                                ],
                              ),
                            ),
                            Positioned(
                              bottom: 12.h,
                              left: 12.w,
                              child: Container(
                                padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
                                decoration: BoxDecoration(
                                  color: AppTheme.background.withOpacity(0.85),
                                  borderRadius: BorderRadius.circular(8.r),
                                  border: Border.all(color: AppTheme.borderSubtle),
                                ),
                                child: Text(
                                  'Page ${_selectedPageIndex + 1} of ${_pages.length}',
                                  style: TextStyle(
                                    color: AppTheme.textPrimary,
                                    fontSize: 12.sp,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
              ),

              // Filter Presets Bar
              if (_pages.isNotEmpty)
                Container(
                  height: 48.h,
                  margin: EdgeInsets.symmetric(vertical: 4.h),
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: EdgeInsets.symmetric(horizontal: 16.w),
                    children: [
                      _buildFilterChip('Original', ScanFilterType.original),
                      _buildFilterChip('Magic Color', ScanFilterType.magicColor),
                      _buildFilterChip('B&W Clean', ScanFilterType.blackAndWhite),
                      _buildFilterChip('Grayscale', ScanFilterType.grayscale),
                      _buildFilterChip('High Contrast', ScanFilterType.enhancedContrast),
                    ],
                  ),
                ),

              // Bottom Thumbnails Strip & Export Action
              if (_pages.isNotEmpty)
                Container(
                  padding: EdgeInsets.all(16.w),
                  decoration: const BoxDecoration(
                    color: AppTheme.surface,
                    border: Border(top: BorderSide(color: AppTheme.border)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        height: 70.h,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: _pages.length,
                          itemBuilder: (ctx, idx) {
                            final isSel = idx == _selectedPageIndex;
                            return GestureDetector(
                              onTap: () {
                                setState(() {
                                  _selectedPageIndex = idx;
                                });
                              },
                              child: Container(
                                width: 50.w,
                                margin: EdgeInsets.only(right: 10.w),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8.r),
                                  border: Border.all(
                                    color: isSel ? AppTheme.cyanAccent : AppTheme.border,
                                    width: isSel ? 2 : 1,
                                  ),
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: Image.file(
                                  File(_pages[idx].processedPath),
                                  fit: BoxFit.cover,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      SizedBox(height: 14.h),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _triggerScan,
                              icon: const Icon(Icons.add),
                              label: const Text('Add Page'),
                            ),
                          ),
                          SizedBox(width: 12.w),
                          Expanded(
                            flex: 2,
                            child: ElevatedButton.icon(
                              onPressed: _exportToPdf,
                              icon: const Icon(Icons.picture_as_pdf),
                              label: Text('Compile PDF (${_pages.length})'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
            ],
          ),

          // Processing Overlay
          if (_isProcessing)
            Container(
              color: Colors.black.withOpacity(0.65),
              child: Center(
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 20.h),
                  decoration: BoxDecoration(
                    color: AppTheme.cardSurface,
                    borderRadius: BorderRadius.circular(16.r),
                    border: Border.all(color: AppTheme.cyanAccent.withOpacity(0.4)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(color: AppTheme.cyanAccent),
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

  Widget _buildFilterChip(String label, ScanFilterType type) {
    if (_pages.isEmpty) return const SizedBox.shrink();
    final isSelected = _pages[_selectedPageIndex].activeFilter == type;

    return Padding(
      padding: EdgeInsets.only(right: 8.w),
      child: FilterChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (_) => _applyFilterToCurrent(type),
        selectedColor: AppTheme.cyanAccent.withOpacity(0.2),
        checkmarkColor: AppTheme.cyanAccent,
        backgroundColor: AppTheme.cardSurface,
        labelStyle: TextStyle(
          color: isSelected ? AppTheme.cyanAccent : AppTheme.textSecondary,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          fontSize: 12.sp,
        ),
        side: BorderSide(
          color: isSelected ? AppTheme.cyanAccent : AppTheme.border,
        ),
      ),
    );
  }
}
