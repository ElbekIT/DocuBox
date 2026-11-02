import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import '../core/calibration/screen_calibrator.dart';
import '../core/theme/app_theme.dart';
import '../services/document_service.dart';

enum DocumentType {
  pdf,
  docx,
  excel,
  csv,
  unknown,
}

class DocumentViewerScreen extends StatefulWidget {
  final String? initialFilePath;

  const DocumentViewerScreen({super.key, this.initialFilePath});

  @override
  State<DocumentViewerScreen> createState() => _DocumentViewerScreenState();
}

class _DocumentViewerScreenState extends State<DocumentViewerScreen> with SingleTickerProviderStateMixin {
  String? _filePath;
  DocumentType _docType = DocumentType.unknown;
  bool _isLoading = false;
  String _loadingMessage = '';

  // PDF Viewer State
  int _pdfTotalPages = 0;
  int _pdfCurrentPage = 0;
  PDFViewController? _pdfViewController;

  // Excel / CSV State
  WorkbookData? _workbookData;
  int _activeSheetIndex = 0;
  String _sheetSearchQuery = '';

  // Word DOCX State
  DocxDocumentData? _docxData;

  @override
  void initState() {
    super.initState();
    if (widget.initialFilePath != null) {
      _openDocument(widget.initialFilePath!);
    }
  }

  Future<void> _pickDocument() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'docx', 'xlsx', 'xls', 'csv'],
    );

    if (result != null && result.files.single.path != null) {
      _openDocument(result.files.single.path!);
    }
  }

  Future<void> _openDocument(String path) async {
    setState(() {
      _filePath = path;
      _isLoading = true;
      _loadingMessage = 'Parsing document structure...';
    });

    final ext = p.extension(path).toLowerCase();
    try {
      if (ext == '.pdf') {
        _docType = DocumentType.pdf;
      } else if (ext == '.docx') {
        _docType = DocumentType.docx;
        final docx = await DocumentService.instance.parseDocx(path);
        setState(() {
          _docxData = docx;
        });
      } else if (ext == '.xlsx' || ext == '.xls') {
        _docType = DocumentType.excel;
        final workbook = await DocumentService.instance.parseExcel(path);
        setState(() {
          _workbookData = workbook;
          _activeSheetIndex = 0;
        });
      } else if (ext == '.csv') {
        _docType = DocumentType.csv;
        final csvWb = await DocumentService.instance.parseCsv(path);
        setState(() {
          _workbookData = csvWb;
          _activeSheetIndex = 0;
        });
      } else {
        _docType = DocumentType.unknown;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.cardSurface,
            content: Text('Failed to parse document: $e', style: const TextStyle(color: AppTheme.roseAccent)),
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

  Future<void> _convertToPdf() async {
    if (_filePath == null) return;

    setState(() {
      _isLoading = true;
      _loadingMessage = 'Synthesizing vector PDF document...';
    });

    try {
      File? generatedPdf;
      if (_docType == DocumentType.docx && _docxData != null) {
        generatedPdf = await DocumentService.instance.convertDocxToPdf(_docxData!);
      } else if ((_docType == DocumentType.excel || _docType == DocumentType.csv) &&
          _workbookData != null &&
          _workbookData!.sheets.isNotEmpty) {
        final currentSheet = _workbookData!.sheets[_activeSheetIndex];
        generatedPdf = await DocumentService.instance.convertSheetToPdf(
          sheet: currentSheet,
          workbookName: _workbookData!.fileName,
        );
      }

      if (generatedPdf != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.cardSurfaceLight,
            content: Text('PDF Generated: ${p.basename(generatedPdf.path)}'),
            action: SnackBarAction(
              label: 'VIEW PDF',
              textColor: AppTheme.cyanAccent,
              onPressed: () {
                _openDocument(generatedPdf!.path);
              },
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.cardSurface,
            content: Text('Conversion failed: $e', style: const TextStyle(color: AppTheme.roseAccent)),
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

  @override
  Widget build(BuildContext context) {
    ScreenCalibrator.instance.calibrate(context);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(_filePath != null ? p.basename(_filePath!) : 'Document Viewer'),
        actions: [
          if (_docType == DocumentType.docx || _docType == DocumentType.excel || _docType == DocumentType.csv)
            TextButton.icon(
              icon: const Icon(Icons.picture_as_pdf, color: AppTheme.cyanAccent, size: 18),
              label: const Text('To PDF', style: TextStyle(color: AppTheme.cyanAccent, fontWeight: FontWeight.bold)),
              onPressed: _convertToPdf,
            ),
          if (_filePath != null)
            IconButton(
              icon: const Icon(Icons.share_outlined),
              tooltip: 'Share Document',
              onPressed: () {
                Share.shareXFiles([XFile(_filePath!)]);
              },
            ),
          IconButton(
            icon: const Icon(Icons.file_open_outlined),
            tooltip: 'Open Another File',
            onPressed: _pickDocument,
          ),
        ],
      ),
      body: Stack(
        children: [
          if (_filePath == null)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.auto_stories_outlined, size: 70.r, color: AppTheme.blueAccent.withOpacity(0.6)),
                  SizedBox(height: 16.h),
                  Text(
                    'Universal Document Reader',
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 18.sp,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 8.h),
                  Text(
                    'Native DOCX, Excel XLSX/CSV & PDF Viewer with 1-Tap PDF Converter',
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 13.sp),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 24.h),
                  ElevatedButton.icon(
                    onPressed: _pickDocument,
                    icon: const Icon(Icons.folder_open),
                    label: const Text('Open Document'),
                  ),
                ],
              ),
            )
          else ...[
            if (_docType == DocumentType.pdf) _buildPdfViewer(),
            if (_docType == DocumentType.docx) _buildDocxViewer(),
            if (_docType == DocumentType.excel || _docType == DocumentType.csv) _buildSpreadsheetViewer(),
          ],

          // Loading Overlay
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
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPdfViewer() {
    return Stack(
      children: [
        PDFView(
          filePath: _filePath,
          enableSwipe: true,
          swipeHorizontal: false,
          autoSpacing: true,
          pageFling: true,
          pageSnap: true,
          fitPolicy: FitPolicy.WIDTH,
          onRender: (pages) {
            setState(() {
              _pdfTotalPages = pages ?? 0;
            });
          },
          onViewCreated: (controller) {
            _pdfViewController = controller;
          },
          onPageChanged: (page, total) {
            setState(() {
              _pdfCurrentPage = page ?? 0;
              _pdfTotalPages = total ?? 0;
            });
          },
        ),
        // Floating Page Indicator
        if (_pdfTotalPages > 0)
          Positioned(
            bottom: 20.h,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
                decoration: BoxDecoration(
                  color: AppTheme.background.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(20.r),
                  border: Border.all(color: AppTheme.border),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: Text(
                  'Page ${_pdfCurrentPage + 1} of $_pdfTotalPages',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 12.5.sp,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildDocxViewer() {
    if (_docxData == null) return const SizedBox.shrink();

    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 16.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // DOCX Header Banner
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(16.w),
            decoration: BoxDecoration(
              color: AppTheme.cardSurface,
              borderRadius: BorderRadius.circular(12.r),
              border: Border.all(color: AppTheme.border),
            ),
            child: Row(
              children: [
                Icon(Icons.description, color: AppTheme.blueAccent, size: 28.r),
                SizedBox(width: 12.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _docxData!.title,
                        style: TextStyle(color: AppTheme.textPrimary, fontSize: 15.sp, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Parsed natively without external word processor',
                        style: TextStyle(color: AppTheme.textMuted, fontSize: 11.sp),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 20.h),

          // Render Elements
          ..._docxData!.blocks.map((block) {
            switch (block.type) {
              case DocxElementType.heading1:
                return Padding(
                  padding: EdgeInsets.only(top: 18.h, bottom: 8.h),
                  child: Text(
                    block.fullText,
                    style: TextStyle(color: AppTheme.textPrimary, fontSize: 22.sp, fontWeight: FontWeight.w800),
                  ),
                );

              case DocxElementType.heading2:
                return Padding(
                  padding: EdgeInsets.only(top: 14.h, bottom: 6.h),
                  child: Text(
                    block.fullText,
                    style: TextStyle(color: AppTheme.textPrimary, fontSize: 18.sp, fontWeight: FontWeight.w700),
                  ),
                );

              case DocxElementType.heading3:
                return Padding(
                  padding: EdgeInsets.only(top: 10.h, bottom: 4.h),
                  child: Text(
                    block.fullText,
                    style: TextStyle(color: AppTheme.textPrimary, fontSize: 15.sp, fontWeight: FontWeight.w600),
                  ),
                );

              case DocxElementType.bulletItem:
                return Padding(
                  padding: EdgeInsets.symmetric(vertical: 3.h),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: EdgeInsets.only(top: 6.h, right: 8.w),
                        child: Container(
                          width: 5.r,
                          height: 5.r,
                          decoration: const BoxDecoration(
                            color: AppTheme.cyanAccent,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          block.fullText,
                          style: TextStyle(color: AppTheme.textPrimary, fontSize: 13.5.sp, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                );

              case DocxElementType.paragraph:
                return Padding(
                  padding: EdgeInsets.only(bottom: 10.h),
                  child: Text.rich(
                    TextSpan(
                      children: block.spans.map((s) {
                        return TextSpan(
                          text: s.text,
                          style: TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 13.5.sp,
                            height: 1.45,
                            fontWeight: s.isBold ? FontWeight.bold : FontWeight.normal,
                            fontStyle: s.isItalic ? FontStyle.italic : FontStyle.normal,
                            decoration: s.isUnderline ? TextDecoration.underline : TextDecoration.none,
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                );

              case DocxElementType.table:
                return Container(
                  margin: EdgeInsets.symmetric(vertical: 12.h),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppTheme.border),
                    borderRadius: BorderRadius.circular(8.r),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Table(
                      defaultColumnWidth: const IntrinsicColumnWidth(),
                      border: TableBorder.all(color: AppTheme.borderSubtle),
                      children: block.tableData.map((row) {
                        return TableRow(
                          children: row.map((cellText) {
                            return Padding(
                              padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                              child: Text(
                                cellText,
                                style: TextStyle(color: AppTheme.textPrimary, fontSize: 12.sp),
                              ),
                            );
                          }).toList(),
                        );
                      }).toList(),
                    ),
                  ),
                );
            }
          }),
        ],
      ),
    );
  }

  Widget _buildSpreadsheetViewer() {
    if (_workbookData == null || _workbookData!.sheets.isEmpty) {
      return const Center(child: Text('Empty Spreadsheet', style: TextStyle(color: AppTheme.textMuted)));
    }

    final currentSheet = _workbookData!.sheets[_activeSheetIndex];

    return Column(
      children: [
        // Sheet Tabs if workbook has multiple sheets
        if (_workbookData!.sheets.length > 1)
          Container(
            height: 42.h,
            color: AppTheme.surface,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _workbookData!.sheets.length,
              itemBuilder: (ctx, idx) {
                final isSelected = idx == _activeSheetIndex;
                final sheet = _workbookData!.sheets[idx];
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _activeSheetIndex = idx;
                    });
                  },
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 16.w),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: isSelected ? AppTheme.emeraldAccent : Colors.transparent,
                          width: 2.5,
                        ),
                      ),
                    ),
                    child: Text(
                      sheet.name,
                      style: TextStyle(
                        color: isSelected ? AppTheme.emeraldAccent : AppTheme.textSecondary,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        fontSize: 12.5.sp,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

        // Search Bar for Spreadsheet
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 8.h),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Search within sheet...',
                    prefixIcon: const Icon(Icons.search, size: 18, color: AppTheme.textMuted),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                  ),
                  onChanged: (val) {
                    setState(() {
                      _sheetSearchQuery = val.trim().toLowerCase();
                    });
                  },
                ),
              ),
              SizedBox(width: 10.w),
              Text(
                '${currentSheet.rowCount} R × ${currentSheet.columnCount} C',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 11.5.sp, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),

        // 2D Scrollable Grid
        Expanded(
          child: Container(
            color: AppTheme.surface,
            child: SingleChildScrollView(
              scrollDirection: Axis.vertical,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowColor: MaterialStateProperty.all(AppTheme.cardSurfaceLight),
                  border: TableBorder.all(color: AppTheme.borderSubtle, width: 0.5),
                  columns: List.generate(currentSheet.columnCount, (colIdx) {
                    final colName = _columnNumberToLetters(colIdx + 1);
                    return DataColumn(
                      label: Text(
                        colName,
                        style: TextStyle(
                          color: AppTheme.cyanAccent,
                          fontWeight: FontWeight.bold,
                          fontSize: 12.sp,
                        ),
                      ),
                    );
                  }),
                  rows: currentSheet.rows.asMap().entries.where((entry) {
                    if (_sheetSearchQuery.isEmpty) return true;
                    return entry.value.any((cell) => cell.toLowerCase().contains(_sheetSearchQuery));
                  }).map((entry) {
                    final rowData = entry.value;
                    return DataRow(
                      cells: List.generate(currentSheet.columnCount, (colIdx) {
                        final text = colIdx < rowData.length ? rowData[colIdx] : '';
                        final isMatch = _sheetSearchQuery.isNotEmpty && text.toLowerCase().contains(_sheetSearchQuery);

                        return DataCell(
                          Container(
                            color: isMatch ? AppTheme.amberAccent.withOpacity(0.25) : Colors.transparent,
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Text(
                              text,
                              style: TextStyle(
                                color: isMatch ? AppTheme.amberAccent : AppTheme.textPrimary,
                                fontSize: 12.sp,
                              ),
                            ),
                          ),
                        );
                      }),
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _columnNumberToLetters(int columnNumber) {
    String dividend = '';
    int num = columnNumber;
    while (num > 0) {
      int modulo = (num - 1) % 26;
      dividend = String.fromCharCode(65 + modulo) + dividend;
      num = ((num - modulo) / 26).floor();
    }
    return dividend;
  }
}
