import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
import '../core/calibration/screen_calibrator.dart';
import '../core/theme/app_theme.dart';
import '../services/ocr_service.dart';
import '../services/scanner_service.dart';

class OcrScreen extends StatefulWidget {
  final String? initialImagePath;

  const OcrScreen({super.key, this.initialImagePath});

  @override
  State<OcrScreen> createState() => _OcrScreenState();
}

class _OcrScreenState extends State<OcrScreen> {
  String? _selectedImagePath;
  OcrResult? _ocrResult;
  bool _isProcessing = false;
  String _searchQuery = '';
  final TextEditingController _textController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.initialImagePath != null) {
      _processImage(widget.initialImagePath!);
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
    );

    if (result != null && result.files.single.path != null) {
      _processImage(result.files.single.path!);
    }
  }

  Future<void> _scanWithCamera() async {
    final scannedPaths = await ScannerService.instance.startMLKitScan(pageLimit: 1);
    if (scannedPaths.isNotEmpty) {
      _processImage(scannedPaths.first);
    }
  }

  Future<void> _processImage(String path) async {
    setState(() {
      _selectedImagePath = path;
      _isProcessing = true;
    });

    try {
      final res = await OcrService.instance.extractText(path);
      setState(() {
        _ocrResult = res;
        _textController.text = res.fullText;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.cardSurface,
            content: Text('OCR Error: $e', style: const TextStyle(color: AppTheme.roseAccent)),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  void _copyToClipboard() {
    if (_textController.text.trim().isEmpty) return;
    Clipboard.setData(ClipboardData(text: _textController.text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        backgroundColor: AppTheme.cardSurfaceLight,
        content: Row(
          children: [
            Icon(Icons.check_circle, color: AppTheme.emeraldAccent, size: 20),
            SizedBox(width: 10),
            Text('Copied text to clipboard!'),
          ],
        ),
      ),
    );
  }

  Future<void> _exportAsTxt() async {
    if (_textController.text.trim().isEmpty) return;
    final file = await OcrService.instance.exportToTxt(_textController.text);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppTheme.cardSurfaceLight,
          content: Text('Saved TXT: ${file.path.split('/').last}'),
          action: SnackBarAction(
            label: 'SHARE',
            textColor: AppTheme.cyanAccent,
            onPressed: () => Share.shareXFiles([XFile(file.path)]),
          ),
        ),
      );
    }
  }

  Future<void> _exportAsPdf() async {
    if (_textController.text.trim().isEmpty) return;
    final file = await OcrService.instance.exportToPdf(_textController.text);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppTheme.cardSurfaceLight,
          content: Text('Saved PDF: ${file.path.split('/').last}'),
          action: SnackBarAction(
            label: 'VIEW',
            textColor: AppTheme.cyanAccent,
            onPressed: () => OpenFilex.open(file.path),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    ScreenCalibrator.instance.calibrate(context);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Offline OCR Text Extractor'),
        actions: [
          IconButton(
            icon: const Icon(Icons.camera_alt_outlined),
            tooltip: 'Camera Scan',
            onPressed: _scanWithCamera,
          ),
          IconButton(
            icon: const Icon(Icons.photo_library_outlined),
            tooltip: 'Pick Image',
            onPressed: _pickImage,
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              if (_selectedImagePath == null)
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.document_scanner, size: 70.r, color: AppTheme.cyanAccent.withOpacity(0.6)),
                        SizedBox(height: 16.h),
                        Text(
                          'On-Device ML Kit OCR',
                          style: TextStyle(color: AppTheme.textPrimary, fontSize: 18.sp, fontWeight: FontWeight.bold),
                        ),
                        SizedBox(height: 8.h),
                        Text(
                          'Extract text from images, receipts, and documents 100% offline.',
                          style: TextStyle(color: AppTheme.textSecondary, fontSize: 13.sp),
                          textAlign: TextAlign.center,
                        ),
                        SizedBox(height: 24.h),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ElevatedButton.icon(
                              onPressed: _scanWithCamera,
                              icon: const Icon(Icons.camera),
                              label: const Text('Scan Document'),
                            ),
                            SizedBox(width: 12.w),
                            OutlinedButton.icon(
                              onPressed: _pickImage,
                              icon: const Icon(Icons.image),
                              label: const Text('Pick Image'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                )
              else ...[
                // Image preview & metrics strip
                Container(
                  padding: EdgeInsets.all(12.w),
                  margin: EdgeInsets.all(14.w),
                  decoration: BoxDecoration(
                    color: AppTheme.cardSurface,
                    borderRadius: BorderRadius.circular(14.r),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8.r),
                        child: Image.file(
                          File(_selectedImagePath!),
                          width: 50.r,
                          height: 50.r,
                          fit: BoxFit.cover,
                        ),
                      ),
                      SizedBox(width: 12.w),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _selectedImagePath!.split('/').last,
                              style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 13.sp),
                              overflow: TextOverflow.ellipsis,
                            ),
                            SizedBox(height: 4.h),
                            Text(
                              _ocrResult != null
                                  ? '${_ocrResult!.lines.length} lines • ${_ocrResult!.blockCount} blocks'
                                  : 'Processing image...',
                              style: TextStyle(color: AppTheme.textMuted, fontSize: 11.5.sp),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy, color: AppTheme.cyanAccent),
                        tooltip: 'Copy All',
                        onPressed: _copyToClipboard,
                      ),
                    ],
                  ),
                ),

                // Action Bar (Copy, TXT, PDF, Share)
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 14.w),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _exportAsTxt,
                          icon: const Icon(Icons.text_snippet_outlined, size: 16),
                          label: const Text('Export TXT'),
                        ),
                      ),
                      SizedBox(width: 10.w),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _exportAsPdf,
                          icon: const Icon(Icons.picture_as_pdf, size: 16),
                          label: const Text('Export PDF'),
                        ),
                      ),
                      SizedBox(width: 10.w),
                      IconButton.filledTonal(
                        icon: const Icon(Icons.share),
                        tooltip: 'Share Text',
                        onPressed: () {
                          if (_textController.text.isNotEmpty) {
                            Share.share(_textController.text);
                          }
                        },
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 12.h),

                // Editable Recognized Text Box
                Expanded(
                  child: Container(
                    margin: EdgeInsets.symmetric(horizontal: 14.w, vertical: 6.h),
                    padding: EdgeInsets.all(14.w),
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(14.r),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: TextField(
                      controller: _textController,
                      maxLines: null,
                      expands: true,
                      style: TextStyle(color: AppTheme.textPrimary, fontSize: 14.sp, height: 1.45),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        hintText: 'Recognized text will appear here...',
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),

          if (_isProcessing)
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
}
