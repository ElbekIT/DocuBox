import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class OcrResult {
  final String fullText;
  final List<String> lines;
  final int blockCount;

  OcrResult({
    required this.fullText,
    required this.lines,
    required this.blockCount,
  });
}

class OcrService {
  OcrService._internal();
  static final OcrService instance = OcrService._internal();

  /// Extracts text from an image completely offline using Google ML Kit on-device model.
  Future<OcrResult> extractText(String imagePath) async {
    final file = File(imagePath);
    if (!await file.exists()) {
      throw Exception('Image not found: $imagePath');
    }

    final inputImage = InputImage.fromFilePath(imagePath);
    final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);

    try {
      final RecognizedText recognizedText = await textRecognizer.processImage(inputImage);
      final List<String> extractedLines = [];

      for (final block in recognizedText.blocks) {
        for (final line in block.lines) {
          extractedLines.add(line.text);
        }
      }

      return OcrResult(
        fullText: recognizedText.text,
        lines: extractedLines,
        blockCount: recognizedText.blocks.length,
      );
    } finally {
      textRecognizer.close();
    }
  }

  /// Exports extracted OCR text to a standalone .txt file.
  Future<File> exportToTxt(String text, {String? fileName}) async {
    final docsDir = await getApplicationDocumentsDirectory();
    final outDir = Directory(p.join(docsDir.path, 'DocuBox_OCR'));
    if (!await outDir.exists()) {
      await outDir.create(recursive: true);
    }

    final base = fileName ?? 'OCR_${DateTime.now().millisecondsSinceEpoch}';
    final targetPath = p.join(outDir.path, '$base.txt');
    final file = File(targetPath);
    await file.writeAsString(text);
    return file;
  }

  /// Exports extracted OCR text into a formatted PDF document.
  Future<File> exportToPdf(String text, {String? title}) async {
    final pdf = pw.Document(
      title: title ?? 'Extracted Text Document',
      author: 'DocuBox OCR Engine',
    );

    final fontRegular = pw.Font.helvetica();
    final fontBold = pw.Font.helveticaBold();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        header: (pw.Context context) {
          return pw.Container(
            padding: const pw.EdgeInsets.only(bottom: 8),
            decoration: const pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300)),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('DocuBox OCR Extract', style: pw.TextStyle(font: fontBold, fontSize: 10, color: PdfColors.blueGrey800)),
                pw.Text('Page ${context.pageNumber} of ${context.pagesCount}', style: pw.TextStyle(font: fontRegular, fontSize: 9, color: PdfColors.grey600)),
              ],
            ),
          );
        },
        build: (pw.Context context) {
          return [
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 8),
              child: pw.Text(
                title ?? 'Recognized Document Content',
                style: pw.TextStyle(font: fontBold, fontSize: 16, color: PdfColors.blueGrey900),
              ),
            ),
            pw.SizedBox(height: 12),
            pw.Text(
              text,
              style: pw.TextStyle(font: fontRegular, fontSize: 11, lineSpacing: 1.4),
            ),
          ];
        },
      ),
    );

    final docsDir = await getApplicationDocumentsDirectory();
    final outDir = Directory(p.join(docsDir.path, 'DocuBox_OCR'));
    if (!await outDir.exists()) {
      await outDir.create(recursive: true);
    }

    final base = title ?? 'OCR_Document_${DateTime.now().millisecondsSinceEpoch}';
    final targetPath = p.join(outDir.path, '$base.pdf');
    final pdfBytes = await pdf.save();
    final outputFile = File(targetPath);
    await outputFile.writeAsBytes(pdfBytes);
    return outputFile;
  }
}
