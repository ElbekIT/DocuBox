import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

enum ScanFilterType {
  original,
  magicColor,
  grayscale,
  blackAndWhite,
  enhancedContrast,
}

class ScannedPage {
  final String originalPath;
  String processedPath;
  ScanFilterType activeFilter;
  int rotationDegrees;

  ScannedPage({
    required this.originalPath,
    required this.processedPath,
    this.activeFilter = ScanFilterType.original,
    this.rotationDegrees = 0,
  });
}

class ScannerService {
  ScannerService._internal();
  static final ScannerService instance = ScannerService._internal();

  /// Starts the Google ML Kit Document Scanner flow.
  /// Handles auto edge detection, camera scanning, perspective rectification, and shadow removal.
  Future<List<String>> startMLKitScan({int pageLimit = 50}) async {
    try {
      final options = DocumentScannerOptions(
        documentFormat: DocumentFormat.jpeg,
        mode: ScannerMode.full,
        pageLimit: pageLimit,
      );

      final documentScanner = DocumentScanner(options: options);
      final documents = await documentScanner.scanDocument();

      if (documents.images.isNotEmpty) {
        return documents.images;
      }
      return [];
    } catch (e) {
      debugPrint('[ScannerService] ML Kit Document Scanner error: $e');
      return [];
    }
  }

  /// Applies high-fidelity image enhancement filters (Shadow cleaning, Contrast, B&W, Grayscale, Magic Color)
  Future<String> applyFilter({
    required String imagePath,
    required ScanFilterType filterType,
    int rotationDegrees = 0,
  }) async {
    final file = File(imagePath);
    if (!await file.exists()) {
      throw Exception('Image not found: $imagePath');
    }

    final bytes = await file.readAsBytes();
    img.Image? decoded = img.decodeImage(bytes);

    if (decoded == null) {
      throw Exception('Failed to decode image data.');
    }

    // Apply rotation if required
    if (rotationDegrees % 360 != 0) {
      decoded = img.copyRotate(decoded, angle: rotationDegrees.toDouble());
    }

    img.Image processed;
    switch (filterType) {
      case ScanFilterType.original:
        processed = decoded;
        break;

      case ScanFilterType.magicColor:
        // Enhance saturation, contrast, and clarity for documents
        processed = img.adjustColor(
          decoded,
          saturation: 1.25,
          contrast: 1.2,
          brightness: 1.05,
        );
        break;

      case ScanFilterType.grayscale:
        processed = img.grayscale(decoded);
        processed = img.adjustColor(processed, contrast: 1.15, brightness: 1.02);
        break;

      case ScanFilterType.blackAndWhite:
        // High contrast binarization with adaptive thresholding emulation
        final gray = img.grayscale(decoded);
        processed = img.contrast(gray, contrast: 160);
        // Clean shadows: push high values to white
        for (int y = 0; y < processed.height; y++) {
          for (int x = 0; x < processed.width; x++) {
            final pixel = processed.getPixel(x, y);
            final lum = img.getLuminance(pixel);
            if (lum > 155) {
              processed.setPixelRgba(x, y, 255, 255, 255, 255);
            } else if (lum < 95) {
              processed.setPixelRgba(x, y, 0, 0, 0, 255);
            }
          }
        }
        break;

      case ScanFilterType.enhancedContrast:
        // Shadow cleaning filter: boost contrast and equalize brightness
        processed = img.contrast(decoded, contrast: 130);
        processed = img.adjustColor(processed, brightness: 1.08);
        break;
    }

    // Save processed image to cache/scans directory
    final tempDir = await getTemporaryDirectory();
    final scansDir = Directory(p.join(tempDir.path, 'docubox_scans'));
    if (!await scansDir.exists()) {
      await scansDir.create(recursive: true);
    }

    final filename = 'proc_${DateTime.now().millisecondsSinceEpoch}_${p.basename(imagePath)}';
    final targetPath = p.join(scansDir.path, filename);
    final outputBytes = img.encodeJpg(processed, quality: 92);
    await File(targetPath).writeAsBytes(outputBytes);

    return targetPath;
  }

  /// Compiles multiple scanned images into a production-grade multi-page PDF document.
  Future<File> compileToPdf({
    required List<String> imagePaths,
    String? outputFileName,
    PdfPageFormat pageFormat = PdfPageFormat.a4,
  }) async {
    if (imagePaths.isEmpty) {
      throw Exception('Cannot compile empty scan list to PDF.');
    }

    final pdf = pw.Document(
      title: outputFileName ?? 'DocuBox_Scan_${DateTime.now().millisecondsSinceEpoch}',
      author: 'DocuBox Universal Suite',
      creator: 'DocuBox Military-Grade Scanner Engine',
    );

    for (int i = 0; i < imagePaths.length; i++) {
      final imgPath = imagePaths[i];
      final imgFile = File(imgPath);
      if (!await imgFile.exists()) continue;

      final imageBytes = await imgFile.readAsBytes();
      final pdfImage = pw.MemoryImage(imageBytes);

      pdf.addPage(
        pw.Page(
          pageFormat: pageFormat,
          margin: const pw.EdgeInsets.all(16),
          build: (pw.Context context) {
            return pw.Center(
              child: pw.Image(
                pdfImage,
                fit: pw.BoxFit.contain,
              ),
            );
          },
        ),
      );
    }

    final docsDir = await getApplicationDocumentsDirectory();
    final outputDir = Directory(p.join(docsDir.path, 'DocuBox_Scans'));
    if (!await outputDir.exists()) {
      await outputDir.create(recursive: true);
    }

    final baseName = outputFileName ?? 'DocuBox_Scan_${DateTime.now().millisecondsSinceEpoch}';
    final finalPath = p.join(outputDir.path, '$baseName.pdf');
    final pdfBytes = await pdf.save();

    final outputFile = File(finalPath);
    await outputFile.writeAsBytes(pdfBytes);

    return outputFile;
  }
}
