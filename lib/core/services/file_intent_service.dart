import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import '../../screens/archive_screen.dart';
import '../../screens/document_viewer_screen.dart';
import '../../screens/ocr_screen.dart';

class FileIntentService {
  FileIntentService._internal();
  static final FileIntentService instance = FileIntentService._internal();

  static const MethodChannel _channel = MethodChannel('com.docubox.app/file_intent');

  bool _initialized = false;
  String? _pendingFilePath;
  BuildContext? _currentContext;

  void setContext(BuildContext context) {
    _currentContext = context;
    if (_pendingFilePath != null) {
      final path = _pendingFilePath!;
      _pendingFilePath = null;
      openFile(context, path);
    }
  }

  void init() {
    if (_initialized) return;
    _initialized = true;

    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onFileReceived') {
        final filePath = call.arguments as String?;
        if (filePath != null && filePath.isNotEmpty) {
          if (_currentContext != null && _currentContext!.mounted) {
            openFile(_currentContext!, filePath);
          } else {
            _pendingFilePath = filePath;
          }
        }
      }
    });

    _fetchInitialFile();
  }

  Future<void> _fetchInitialFile() async {
    try {
      final initialPath = await _channel.invokeMethod<String>('getInitialFile');
      if (initialPath != null && initialPath.isNotEmpty) {
        if (_currentContext != null && _currentContext!.mounted) {
          openFile(_currentContext!, initialPath);
        } else {
          _pendingFilePath = initialPath;
        }
      }
    } catch (e) {
      debugPrint('[FileIntentService] getInitialFile error: $e');
    }
  }

  void openFile(BuildContext context, String filePath) {
    final file = File(filePath);
    if (!file.existsSync()) {
      debugPrint('[FileIntentService] Received file does not exist: $filePath');
      return;
    }

    final ext = p.extension(filePath).toLowerCase();

    if (ext == '.zip' || ext == '.7z' || ext == '.rar' || ext == '.tar' || ext == '.gz' || ext == '.aes') {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ArchiveScreen(initialArchivePath: filePath)),
      );
    } else if (ext == '.pdf' ||
        ext == '.docx' ||
        ext == '.doc' ||
        ext == '.xlsx' ||
        ext == '.xls' ||
        ext == '.csv' ||
        ext == '.txt') {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => DocumentViewerScreen(initialFilePath: filePath)),
      );
    } else if (ext == '.jpg' || ext == '.jpeg' || ext == '.png' || ext == '.webp') {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => OcrScreen(initialImagePath: filePath)),
      );
    } else {
      // Default fallback for any other file type
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => DocumentViewerScreen(initialFilePath: filePath)),
      );
    }
  }
}
