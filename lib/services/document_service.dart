import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart' as xl;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:xml/xml.dart' as xml;

/// Model for parsed spreadsheet sheet
class SheetData {
  final String name;
  final int rowCount;
  final int columnCount;
  final List<List<String>> rows;

  SheetData({
    required this.name,
    required this.rowCount,
    required this.columnCount,
    required this.rows,
  });
}

/// Model for parsed spreadsheet workbook
class WorkbookData {
  final String fileName;
  final List<SheetData> sheets;

  WorkbookData({
    required this.fileName,
    required this.sheets,
  });
}

/// Block elements within a Word DOCX document
enum DocxElementType {
  heading1,
  heading2,
  heading3,
  paragraph,
  bulletItem,
  table,
}

class DocxTextSpan {
  final String text;
  final bool isBold;
  final bool isItalic;
  final bool isUnderline;

  DocxTextSpan({
    required this.text,
    this.isBold = false,
    this.isItalic = false,
    this.isUnderline = false,
  });
}

class DocxBlock {
  final DocxElementType type;
  final List<DocxTextSpan> spans;
  final List<List<String>> tableData;

  DocxBlock({
    required this.type,
    this.spans = const [],
    this.tableData = const [],
  });

  String get fullText => spans.map((s) => s.text).join();
}

class DocxDocumentData {
  final String title;
  final List<DocxBlock> blocks;
  final Map<String, Uint8List> images;

  DocxDocumentData({
    required this.title,
    required this.blocks,
    required this.images,
  });
}

class DocumentService {
  DocumentService._internal();
  static final DocumentService instance = DocumentService._internal();

  /// Parses XLSX or XLS Excel files
  Future<WorkbookData> parseExcel(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('Excel file not found: $filePath');
    }

    final bytes = await file.readAsBytes();
    final excel = xl.Excel.decodeBytes(bytes);

    final List<SheetData> sheetList = [];

    for (final tableKey in excel.tables.keys) {
      final table = excel.tables[tableKey];
      if (table == null) continue;

      final List<List<String>> rows = [];
      int maxCols = 0;

      for (final row in table.rows) {
        final List<String> cellRow = [];
        for (final cell in row) {
          final val = cell?.value?.toString() ?? '';
          cellRow.add(val);
        }
        if (cellRow.length > maxCols) maxCols = cellRow.length;
        rows.add(cellRow);
      }

      sheetList.add(
        SheetData(
          name: tableKey,
          rowCount: rows.length,
          columnCount: maxCols,
          rows: rows,
        ),
      );
    }

    return WorkbookData(
      fileName: p.basename(filePath),
      sheets: sheetList,
    );
  }

  /// Parses CSV files into tabular spreadsheet format
  Future<WorkbookData> parseCsv(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('CSV file not found: $filePath');
    }

    final contents = await file.readAsString();
    final parsed = const CsvToListConverter(shouldParseNumbers: false).convert(contents);

    final List<List<String>> rows = [];
    int maxCols = 0;

    for (final row in parsed) {
      final List<String> stringRow = row.map((c) => c?.toString() ?? '').toList();
      if (stringRow.length > maxCols) maxCols = stringRow.length;
      rows.add(stringRow);
    }

    final sheet = SheetData(
      name: p.basenameWithoutExtension(filePath),
      rowCount: rows.length,
      columnCount: maxCols,
      rows: rows,
    );

    return WorkbookData(
      fileName: p.basename(filePath),
      sheets: [sheet],
    );
  }

  /// Parses DOCX files natively by reading word/document.xml and extracting images
  Future<DocxDocumentData> parseDocx(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('DOCX file not found: $filePath');
    }

    final bytes = await file.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes, verify: false);

    final Map<String, Uint8List> images = {};
    String? documentXmlString;

    for (final file in archive) {
      if (file.name == 'word/document.xml') {
        documentXmlString = utf8.decode(file.content as List<int>);
      } else if (file.name.startsWith('word/media/')) {
        images[p.basename(file.name)] = Uint8List.fromList(file.content as List<int>);
      }
    }

    if (documentXmlString == null) {
      throw Exception('Invalid DOCX format: word/document.xml missing.');
    }

    final documentXml = xml.XmlDocument.parse(documentXmlString);
    final List<DocxBlock> blocks = [];

    final body = documentXml.findAllElements('w:body').firstOrNull;
    if (body == null) {
      return DocxDocumentData(title: p.basename(filePath), blocks: [], images: images);
    }

    for (final child in body.children.whereType<xml.XmlElement>()) {
      final name = child.name.local;

      if (name == 'p') {
        // Paragraph or Heading or Bullet list item
        DocxElementType blockType = DocxElementType.paragraph;

        final pPr = child.findElements('w:pPr').firstOrNull;
        if (pPr != null) {
          final pStyle = pPr.findElements('w:pStyle').firstOrNull;
          final styleVal = pStyle?.getAttribute('w:val')?.toLowerCase() ?? '';

          if (styleVal.contains('heading1') || styleVal == '1') {
            blockType = DocxElementType.heading1;
          } else if (styleVal.contains('heading2') || styleVal == '2') {
            blockType = DocxElementType.heading2;
          } else if (styleVal.contains('heading3') || styleVal == '3') {
            blockType = DocxElementType.heading3;
          }

          final numPr = pPr.findElements('w:numPr').firstOrNull;
          if (numPr != null) {
            blockType = DocxElementType.bulletItem;
          }
        }

        final List<DocxTextSpan> spans = [];
        for (final run in child.findAllElements('w:r')) {
          final rPr = run.findElements('w:rPr').firstOrNull;
          bool isBold = false;
          bool isItalic = false;
          bool isUnderline = false;

          if (rPr != null) {
            isBold = rPr.findElements('w:b').isNotEmpty;
            isItalic = rPr.findElements('w:i').isNotEmpty;
            isUnderline = rPr.findElements('w:u').isNotEmpty;
          }

          final textElem = run.findElements('w:t').firstOrNull;
          if (textElem != null) {
            final t = textElem.innerText;
            if (t.isNotEmpty) {
              spans.add(DocxTextSpan(
                text: t,
                isBold: isBold,
                isItalic: isItalic,
                isUnderline: isUnderline,
              ));
            }
          }
        }

        if (spans.isNotEmpty) {
          blocks.add(DocxBlock(type: blockType, spans: spans));
        }
      } else if (name == 'tbl') {
        // Table
        final List<List<String>> tableData = [];
        for (final row in child.findAllElements('w:tr')) {
          final List<String> rowCells = [];
          for (final cell in row.findAllElements('w:tc')) {
            final text = cell.findAllElements('w:t').map((e) => e.innerText).join();
            rowCells.add(text.trim());
          }
          if (rowCells.isNotEmpty) {
            tableData.add(rowCells);
          }
        }
        if (tableData.isNotEmpty) {
          blocks.add(DocxBlock(type: DocxElementType.table, tableData: tableData));
        }
      }
    }

    return DocxDocumentData(
      title: p.basenameWithoutExtension(filePath),
      blocks: blocks,
      images: images,
    );
  }

  /// Converts parsed DOCX document data into a high-grade PDF file
  Future<File> convertDocxToPdf(DocxDocumentData docData, {String? customTitle}) async {
    final pdf = pw.Document(
      title: customTitle ?? docData.title,
      author: 'DocuBox Universal Suite',
      creator: 'DocuBox DOCX-to-PDF Engine',
    );

    final fontRegular = pw.Font.helvetica();
    final fontBold = pw.Font.helveticaBold();
    final fontItalic = pw.Font.helveticaOblique();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 36, vertical: 40),
        header: (pw.Context context) {
          return pw.Container(
            alignment: pw.Alignment.centerRight,
            margin: const pw.EdgeInsets.only(bottom: 12),
            child: pw.Text(
              docData.title,
              style: pw.TextStyle(font: fontItalic, fontSize: 9, color: PdfColors.grey700),
            ),
          );
        },
        footer: (pw.Context context) {
          return pw.Container(
            alignment: pw.Alignment.center,
            margin: const pw.EdgeInsets.only(top: 12),
            child: pw.Text(
              'Page ${context.pageNumber} of ${context.pagesCount}',
              style: pw.TextStyle(font: fontRegular, fontSize: 9, color: PdfColors.grey700),
            ),
          );
        },
        build: (pw.Context context) {
          final List<pw.Widget> widgets = [];

          for (final block in docData.blocks) {
            if (block.type == DocxElementType.heading1) {
              widgets.add(
                pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 14, bottom: 8),
                  child: pw.Text(
                    block.fullText,
                    style: pw.TextStyle(font: fontBold, fontSize: 18, color: PdfColors.blueGrey900),
                  ),
                ),
              );
            } else if (block.type == DocxElementType.heading2) {
              widgets.add(
                pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 10, bottom: 6),
                  child: pw.Text(
                    block.fullText,
                    style: pw.TextStyle(font: fontBold, fontSize: 15, color: PdfColors.blueGrey800),
                  ),
                ),
              );
            } else if (block.type == DocxElementType.heading3) {
              widgets.add(
                pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 8, bottom: 4),
                  child: pw.Text(
                    block.fullText,
                    style: pw.TextStyle(font: fontBold, fontSize: 13, color: PdfColors.blueGrey700),
                  ),
                ),
              );
            } else if (block.type == DocxElementType.bulletItem) {
              widgets.add(
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 2.5),
                  child: pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Container(
                        width: 5,
                        height: 5,
                        margin: const pw.EdgeInsets.only(top: 5, right: 8),
                        decoration: const pw.BoxDecoration(
                          color: PdfColors.blueGrey800,
                          shape: pw.BoxShape.circle,
                        ),
                      ),
                      pw.Expanded(
                        child: pw.Text(
                          block.fullText,
                          style: pw.TextStyle(font: fontRegular, fontSize: 10.5, lineSpacing: 1.3),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            } else if (block.type == DocxElementType.paragraph) {
              final spans = block.spans.map((s) {
                return pw.TextSpan(
                  text: s.text,
                  style: pw.TextStyle(
                    font: s.isBold ? fontBold : (s.isItalic ? fontItalic : fontRegular),
                    fontSize: 10.5,
                    decoration: s.isUnderline ? pw.TextDecoration.underline : pw.TextDecoration.none,
                  ),
                );
              }).toList();

              widgets.add(
                pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 6),
                  child: pw.RichText(
                    text: pw.TextSpan(children: spans),
                  ),
                ),
              );
            } else if (block.type == DocxElementType.table && block.tableData.isNotEmpty) {
              widgets.add(
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 8),
                  child: pw.TableHelper.fromTextArray(
                    border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
                    headerStyle: pw.TextStyle(font: fontBold, fontSize: 9.5),
                    cellStyle: pw.TextStyle(font: fontRegular, fontSize: 9),
                    headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
                    data: block.tableData,
                  ),
                ),
              );
            }
          }

          return widgets;
        },
      ),
    );

    final docsDir = await getApplicationDocumentsDirectory();
    final outDir = Directory(p.join(docsDir.path, 'DocuBox_Converted'));
    if (!await outDir.exists()) {
      await outDir.create(recursive: true);
    }

    final outPath = p.join(outDir.path, '${docData.title}_converted.pdf');
    final pdfBytes = await pdf.save();
    final outputFile = File(outPath);
    await outputFile.writeAsBytes(pdfBytes);

    return outputFile;
  }

  /// Converts Excel Workbook or CSV sheet to a paginated PDF table report
  Future<File> convertSheetToPdf({
    required SheetData sheet,
    required String workbookName,
  }) async {
    final pdf = pw.Document(
      title: '${workbookName}_${sheet.name}',
      author: 'DocuBox Universal Suite',
      creator: 'DocuBox Spreadsheet-to-PDF Engine',
    );

    final fontRegular = pw.Font.helvetica();
    final fontBold = pw.Font.helveticaBold();

    // Use landscape for spreadsheets with more than 4 columns
    final pageFormat = sheet.columnCount > 4 ? PdfPageFormat.a4.landscape : PdfPageFormat.a4;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: pageFormat,
        margin: const pw.EdgeInsets.all(24),
        header: (pw.Context context) {
          return pw.Container(
            padding: const pw.EdgeInsets.only(bottom: 10),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  '$workbookName — ${sheet.name}',
                  style: pw.TextStyle(font: fontBold, fontSize: 11, color: PdfColors.blueGrey900),
                ),
                pw.Text(
                  '${sheet.rowCount} rows, ${sheet.columnCount} columns',
                  style: pw.TextStyle(font: fontRegular, fontSize: 9, color: PdfColors.grey700),
                ),
              ],
            ),
          );
        },
        footer: (pw.Context context) {
          return pw.Container(
            alignment: pw.Alignment.centerRight,
            margin: const pw.EdgeInsets.only(top: 10),
            child: pw.Text(
              'Page ${context.pageNumber} of ${context.pagesCount}',
              style: pw.TextStyle(font: fontRegular, fontSize: 9, color: PdfColors.grey700),
            ),
          );
        },
        build: (pw.Context context) {
          if (sheet.rows.isEmpty) {
            return [pw.Center(child: pw.Text('Empty Sheet', style: pw.TextStyle(font: fontRegular)))];
          }

          // Truncate overly wide sheets gracefully to prevent layout breakage
          final cleanData = sheet.rows.map((row) {
            final padded = List<String>.from(row);
            while (padded.length < sheet.columnCount) {
              padded.add('');
            }
            return padded;
          }).toList();

          return [
            pw.TableHelper.fromTextArray(
              border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
              headerStyle: pw.TextStyle(font: fontBold, fontSize: 8.5),
              cellStyle: pw.TextStyle(font: fontRegular, fontSize: 8),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey100),
              cellAlignment: pw.Alignment.centerLeft,
              data: cleanData,
            ),
          ];
        },
      ),
    );

    final docsDir = await getApplicationDocumentsDirectory();
    final outDir = Directory(p.join(docsDir.path, 'DocuBox_Converted'));
    if (!await outDir.exists()) {
      await outDir.create(recursive: true);
    }

    final outPath = p.join(outDir.path, '${p.basenameWithoutExtension(workbookName)}_${sheet.name}.pdf');
    final pdfBytes = await pdf.save();
    final outputFile = File(outPath);
    await outputFile.writeAsBytes(pdfBytes);

    return outputFile;
  }
}
