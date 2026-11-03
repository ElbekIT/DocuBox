import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class PdfToolsService {
  PdfToolsService._internal();
  static final PdfToolsService instance = PdfToolsService._internal();

  /// Creates a watermarked PDF by stamping watermark text across pages
  Future<File> addWatermark({
    required List<Uint8List> pageImages,
    required String watermarkText,
    double opacity = 0.22,
    double angleDegrees = -30.0,
    PdfColor color = PdfColors.red700,
    String? outputName,
  }) async {
    final pdf = pw.Document(
      title: outputName ?? 'Watermarked_Document',
      author: 'DocuBox PDF Engine',
    );

    final fontBold = pw.Font.helveticaBold();
    final angleRad = angleDegrees * (math.pi / 180.0);

    for (final imgBytes in pageImages) {
      final pdfImage = pw.MemoryImage(imgBytes);

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.zero,
          build: (pw.Context context) {
            return pw.Stack(
              fit: pw.StackFit.expand,
              children: [
                pw.Center(
                  child: pw.Image(pdfImage, fit: pw.BoxFit.contain),
                ),
                pw.Center(
                  child: pw.Transform.rotate(
                    angle: angleRad,
                    child: pw.Opacity(
                      opacity: opacity,
                      child: pw.Text(
                        watermarkText,
                        style: pw.TextStyle(
                          font: fontBold,
                          fontSize: 54,
                          color: color,
                        ),
                        textAlign: pw.TextAlign.center,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      );
    }

    return _savePdfDocument(pdf, outputName ?? 'Watermarked_${DateTime.now().millisecondsSinceEpoch}');
  }

  /// Adds a digital drawn signature onto a specific page
  Future<File> addSignature({
    required List<Uint8List> pageImages,
    required Uint8List signatureBytes,
    required int targetPageIndex,
    double signatureWidth = 140,
    double signatureHeight = 60,
    String? outputName,
  }) async {
    final pdf = pw.Document(
      title: outputName ?? 'Signed_Document',
      author: 'DocuBox PDF Engine',
    );

    final sigImage = pw.MemoryImage(signatureBytes);

    for (int i = 0; i < pageImages.length; i++) {
      final pageImage = pw.MemoryImage(pageImages[i]);
      final isSignedPage = (i == targetPageIndex);

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(16),
          build: (pw.Context context) {
            return pw.Stack(
              fit: pw.StackFit.expand,
              children: [
                pw.Center(child: pw.Image(pageImage, fit: pw.BoxFit.contain)),
                if (isSignedPage)
                  pw.Positioned(
                    bottom: 40,
                    right: 40,
                    child: pw.Container(
                      width: signatureWidth,
                      height: signatureHeight,
                      decoration: pw.BoxDecoration(
                        border: pw.Border.all(color: PdfColors.blueGrey300, width: 0.5),
                      ),
                      child: pw.Image(sigImage, fit: pw.BoxFit.contain),
                    ),
                  ),
              ],
            );
          },
        ),
      );
    }

    return _savePdfDocument(pdf, outputName ?? 'Signed_${DateTime.now().millisecondsSinceEpoch}');
  }

  /// Merges multiple scanned image lists / documents into a single compiled PDF
  Future<File> mergeDocumentPages({
    required List<Uint8List> allPages,
    required String outputName,
  }) async {
    final pdf = pw.Document(
      title: outputName,
      author: 'DocuBox PDF Engine',
    );

    for (final pageBytes in allPages) {
      final img = pw.MemoryImage(pageBytes);
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(16),
          build: (pw.Context context) {
            return pw.Center(child: pw.Image(img, fit: pw.BoxFit.contain));
          },
        ),
      );
    }

    return _savePdfDocument(pdf, outputName);
  }

  /// Splits document by extracting selected page indices into a new PDF
  Future<File> splitDocument({
    required List<Uint8List> allPages,
    required List<int> selectedIndices,
    required String outputName,
  }) async {
    final pdf = pw.Document(
      title: outputName,
      author: 'DocuBox PDF Engine',
    );

    for (final idx in selectedIndices) {
      if (idx >= 0 && idx < allPages.length) {
        final img = pw.MemoryImage(allPages[idx]);
        pdf.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.all(16),
            build: (pw.Context context) {
              return pw.Center(child: pw.Image(img, fit: pw.BoxFit.contain));
            },
          ),
        );
      }
    }

    return _savePdfDocument(pdf, outputName);
  }

  /// Compresses images and generates an optimized compact PDF
  Future<File> compressDocument({
    required List<Uint8List> rawPageImages,
    int quality = 55,
    required String outputName,
  }) async {
    final pdf = pw.Document(
      title: outputName,
      author: 'DocuBox PDF Engine',
    );

    for (final rawBytes in rawPageImages) {
      final decoded = img.decodeImage(rawBytes);
      if (decoded != null) {
        // Resize down if excessively large
        img.Image scaled = decoded;
        if (decoded.width > 1200) {
          scaled = img.copyResize(decoded, width: 1200);
        }
        final compressedJpg = Uint8List.fromList(img.encodeJpg(scaled, quality: quality));
        final pdfImage = pw.MemoryImage(compressedJpg);

        pdf.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.all(16),
            build: (pw.Context context) {
              return pw.Center(child: pw.Image(pdfImage, fit: pw.BoxFit.contain));
            },
          ),
        );
      }
    }

    return _savePdfDocument(pdf, outputName);
  }

  Future<File> _savePdfDocument(pw.Document pdf, String baseName) async {
    final docsDir = await getApplicationDocumentsDirectory();
    final outDir = Directory(p.join(docsDir.path, 'DocuBox_PdfTools'));
    if (!await outDir.exists()) {
      await outDir.create(recursive: true);
    }

    final sanitized = baseName.endsWith('.pdf') ? baseName : '$baseName.pdf';
    final targetPath = p.join(outDir.path, sanitized);
    final bytes = await pdf.save();
    final file = File(targetPath);
    await file.writeAsBytes(bytes);
    return file;
  }
}
