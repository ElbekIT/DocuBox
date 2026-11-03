import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:pdf/pdf.dart';
import 'package:share_plus/share_plus.dart';
import '../core/calibration/screen_calibrator.dart';
import '../core/theme/app_theme.dart';
import '../services/pdf_tools_service.dart';

class PdfToolsScreen extends StatefulWidget {
  const PdfToolsScreen({super.key});

  @override
  State<PdfToolsScreen> createState() => _PdfToolsScreenState();
}

class _PdfToolsScreenState extends State<PdfToolsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final List<Uint8List> _selectedPages = [];
  bool _isLoading = false;

  // Watermark state
  final TextEditingController _watermarkController = TextEditingController(text: 'NUSXA');
  double _watermarkOpacity = 0.25;

  // Signature state
  final List<Offset?> _signaturePoints = [];

  // Compression state
  double _compressionQuality = 50.0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _watermarkController.dispose();
    super.dispose();
  }

  Future<void> _pickDocumentPages() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
    );

    if (result != null && result.paths.isNotEmpty) {
      final List<Uint8List> bytesList = [];
      for (final p in result.paths) {
        if (p != null) {
          final file = File(p);
          if (await file.exists()) {
            bytesList.add(await file.readAsBytes());
          }
        }
      }

      setState(() {
        _selectedPages.clear();
        _selectedPages.addAll(bytesList);
      });
    }
  }

  Future<void> _applyWatermark() async {
    if (_selectedPages.isEmpty) {
      _showEmptyNotice();
      return;
    }

    setState(() => _isLoading = true);
    try {
      final file = await PdfToolsService.instance.addWatermark(
        pageImages: _selectedPages,
        watermarkText: _watermarkController.text.trim().isEmpty ? 'CONFIDENTIAL' : _watermarkController.text.trim(),
        opacity: _watermarkOpacity,
      );
      _showSuccess(file);
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _applySignature() async {
    if (_selectedPages.isEmpty) {
      _showEmptyNotice();
      return;
    }
    if (_signaturePoints.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please draw your signature first on the pad.')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final sigBytes = await _renderSignatureToBytes();
      if (sigBytes != null) {
        final file = await PdfToolsService.instance.addSignature(
          pageImages: _selectedPages,
          signatureBytes: sigBytes,
          targetPageIndex: _selectedPages.length - 1,
        );
        _showSuccess(file);
      }
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _applyCompression() async {
    if (_selectedPages.isEmpty) {
      _showEmptyNotice();
      return;
    }

    setState(() => _isLoading = true);
    try {
      final file = await PdfToolsService.instance.compressDocument(
        rawPageImages: _selectedPages,
        quality: _compressionQuality.toInt(),
        outputName: 'Compressed_${DateTime.now().millisecondsSinceEpoch}',
      );
      _showSuccess(file);
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _applyMerge() async {
    if (_selectedPages.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least 2 pages/images to merge.')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final file = await PdfToolsService.instance.mergeDocumentPages(
        allPages: _selectedPages,
        outputName: 'Merged_${DateTime.now().millisecondsSinceEpoch}',
      );
      _showSuccess(file);
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<Uint8List?> _renderSignatureToBytes() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, 300, 150));
    final paint = Paint()
      ..color = Colors.black
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3.0;

    for (int i = 0; i < _signaturePoints.length - 1; i++) {
      if (_signaturePoints[i] != null && _signaturePoints[i + 1] != null) {
        canvas.drawLine(_signaturePoints[i]!, _signaturePoints[i + 1]!, paint);
      }
    }

    final picture = recorder.endRecording();
    final img = await picture.toImage(300, 150);
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    return byteData?.buffer.asUint8List();
  }

  void _showSuccess(File file) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppTheme.cardSurfaceLight,
        content: Text('PDF Ready: ${file.path.split('/').last}'),
        action: SnackBarAction(
          label: 'OPEN',
          textColor: AppTheme.cyanAccent,
          onPressed: () => OpenFilex.open(file.path),
        ),
      ),
    );
  }

  void _showEmptyNotice() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('First pick or scan pages to apply PDF tool.')),
    );
  }

  void _showError(dynamic e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.roseAccent),
    );
  }

  @override
  Widget build(BuildContext context) {
    ScreenCalibrator.instance.calibrate(context);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Universal PDF Suite'),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppTheme.cyanAccent,
          labelColor: AppTheme.cyanAccent,
          unselectedLabelColor: AppTheme.textSecondary,
          isScrollable: true,
          tabs: const [
            Tab(icon: Icon(Icons.branding_watermark_outlined), text: 'Watermark'),
            Tab(icon: Icon(Icons.draw_outlined), text: 'Digital Sign'),
            Tab(icon: Icon(Icons.call_merge_outlined), text: 'Merge / Split'),
            Tab(icon: Icon(Icons.compress_outlined), text: 'Compress'),
          ],
        ),
      ),
      body: Stack(
        children: [
          Column(
            children: [
              // Page Source Selector Header
              Container(
                padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
                margin: EdgeInsets.all(14.w),
                decoration: BoxDecoration(
                  color: AppTheme.cardSurface,
                  borderRadius: BorderRadius.circular(14.r),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Loaded Document Pages',
                          style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 13.5.sp),
                        ),
                        SizedBox(height: 2.h),
                        Text(
                          '${_selectedPages.length} pages loaded for processing',
                          style: TextStyle(color: AppTheme.textMuted, fontSize: 11.5.sp),
                        ),
                      ],
                    ),
                    ElevatedButton.icon(
                      onPressed: _pickDocumentPages,
                      icon: const Icon(Icons.add_photo_alternate, size: 16),
                      label: Text(_selectedPages.isEmpty ? 'Select Pages' : 'Change Pages'),
                      style: ElevatedButton.styleFrom(
                        padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 8.h),
                      ),
                    ),
                  ],
                ),
              ),

              // Tab Views
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildWatermarkTab(),
                    _buildSignatureTab(),
                    _buildMergeSplitTab(),
                    _buildCompressTab(),
                  ],
                ),
              ),
            ],
          ),

          if (_isLoading)
            Container(
              color: Colors.black.withOpacity(0.65),
              child: const Center(
                child: CircularProgressIndicator(color: AppTheme.cyanAccent),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildWatermarkTab() {
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: 16.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Watermark Text', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 13.sp)),
          SizedBox(height: 8.h),
          TextField(
            controller: _watermarkController,
            decoration: const InputDecoration(
              hintText: 'e.g. NUSXA, CONFIDENTIAL, ORIGINAL',
            ),
          ),
          SizedBox(height: 18.h),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Opacity', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13.sp)),
              Text('${(_watermarkOpacity * 100).toInt()}%', style: const TextStyle(color: AppTheme.cyanAccent, fontWeight: FontWeight.bold)),
            ],
          ),
          Slider(
            value: _watermarkOpacity,
            min: 0.05,
            max: 0.8,
            activeColor: AppTheme.cyanAccent,
            onChanged: (val) => setState(() => _watermarkOpacity = val),
          ),
          SizedBox(height: 24.h),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _applyWatermark,
              icon: const Icon(Icons.verified_outlined),
              label: const Text('Stamp Watermark & Compile PDF'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSignatureTab() {
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: 16.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Draw Signature on Canvas', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 13.sp)),
              TextButton(
                onPressed: () => setState(() => _signaturePoints.clear()),
                child: const Text('Clear', style: TextStyle(color: AppTheme.roseAccent)),
              ),
            ],
          ),
          SizedBox(height: 8.h),
          Container(
            height: 160.h,
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12.r),
              border: Border.all(color: AppTheme.cyanAccent, width: 1.5),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12.r),
              child: GestureDetector(
                onPanUpdate: (details) {
                  final renderBox = context.findRenderObject() as RenderBox?;
                  final localPos = details.localPosition;
                  setState(() {
                    _signaturePoints.add(localPos);
                  });
                },
                onPanEnd: (_) {
                  setState(() {
                    _signaturePoints.add(null);
                  });
                },
                child: CustomPaint(
                  painter: _SignaturePainter(points: _signaturePoints),
                  size: Size.infinite,
                ),
              ),
            ),
          ),
          SizedBox(height: 24.h),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _applySignature,
              icon: const Icon(Icons.check),
              label: const Text('Embed Signature on Document'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMergeSplitTab() {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Merge Document Pages', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 14.sp)),
          SizedBox(height: 6.h),
          Text(
            'Combines multiple separate scans or document files into one unified multi-page PDF.',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 12.sp),
          ),
          SizedBox(height: 18.h),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _applyMerge,
              icon: const Icon(Icons.merge_type),
              label: Text('Merge All (${_selectedPages.length} Pages)'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompressTab() {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Optimize & Compress PDF', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 14.sp)),
          SizedBox(height: 6.h),
          Text(
            'Shrinks document file size for seamless sharing via Telegram, email, and chats.',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 12.sp),
          ),
          SizedBox(height: 18.h),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Compression Quality', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13.sp)),
              Text('${_compressionQuality.toInt()}%', style: const TextStyle(color: AppTheme.cyanAccent, fontWeight: FontWeight.bold)),
            ],
          ),
          Slider(
            value: _compressionQuality,
            min: 20,
            max: 90,
            divisions: 7,
            activeColor: AppTheme.cyanAccent,
            onChanged: (val) => setState(() => _compressionQuality = val),
          ),
          SizedBox(height: 24.h),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _applyCompression,
              icon: const Icon(Icons.speed),
              label: const Text('Compress & Save PDF'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SignaturePainter extends CustomPainter {
  final List<Offset?> points;

  _SignaturePainter({required this.points});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF0A0E17)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3.0;

    for (int i = 0; i < points.length - 1; i++) {
      if (points[i] != null && points[i + 1] != null) {
        canvas.drawLine(points[i]!, points[i + 1]!, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SignaturePainter oldDelegate) => true;
}
