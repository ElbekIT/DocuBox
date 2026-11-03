import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';

enum QrContentType {
  wifi,
  url,
  text,
  email,
  phone,
  sms,
}

class WifiQrData {
  final String ssid;
  final String password;
  final String encryptionType; // WPA, WEP, nopass
  final bool isHidden;

  WifiQrData({
    required this.ssid,
    required this.password,
    required this.encryptionType,
    this.isHidden = false,
  });

  String toQrString() {
    return 'WIFI:S:$ssid;T:$encryptionType;P:$password;${isHidden ? "H:true;" : ""};';
  }
}

class QrScanResult {
  final String rawValue;
  final QrContentType type;
  final BarcodeFormat format;
  final WifiQrData? wifiData;

  QrScanResult({
    required this.rawValue,
    required this.type,
    required this.format,
    this.wifiData,
  });
}

class QrBarcodeService {
  QrBarcodeService._internal();
  static final QrBarcodeService instance = QrBarcodeService._internal();

  /// Scans an image for QR codes and barcodes completely offline
  Future<List<QrScanResult>> scanImage(String imagePath) async {
    final file = File(imagePath);
    if (!await file.exists()) {
      throw Exception('Image not found: $imagePath');
    }

    final inputImage = InputImage.fromFilePath(imagePath);
    final barcodeScanner = BarcodeScanner();

    try {
      final List<Barcode> barcodes = await barcodeScanner.processImage(inputImage);
      final List<QrScanResult> results = [];

      for (final barcode in barcodes) {
        final raw = barcode.rawValue ?? barcode.displayValue ?? '';
        if (raw.isEmpty) continue;

        final wifi = _parseWifiString(raw);
        QrContentType contentType = QrContentType.text;

        if (wifi != null) {
          contentType = QrContentType.wifi;
        } else if (raw.startsWith('http://') || raw.startsWith('https://')) {
          contentType = QrContentType.url;
        } else if (raw.startsWith('mailto:')) {
          contentType = QrContentType.email;
        } else if (raw.startsWith('tel:')) {
          contentType = QrContentType.phone;
        } else if (raw.startsWith('smsto:')) {
          contentType = QrContentType.sms;
        }

        results.add(QrScanResult(
          rawValue: raw,
          type: contentType,
          format: barcode.format,
          wifiData: wifi,
        ));
      }

      return results;
    } finally {
      barcodeScanner.close();
    }
  }

  /// Parses standard Wi-Fi QR code strings:
  /// e.g. WIFI:S:HomeNet;T:WPA;P:SuperSecret123;H:false;;
  static WifiQrData? _parseWifiString(String raw) {
    if (!raw.toUpperCase().startsWith('WIFI:')) {
      return null;
    }

    String ssid = '';
    String password = '';
    String type = 'WPA';
    bool hidden = false;

    // Remove leading 'WIFI:'
    final content = raw.substring(5);
    final tokens = content.split(';');

    for (final token in tokens) {
      if (token.startsWith('S:') || token.startsWith('s:')) {
        ssid = token.substring(2);
      } else if (token.startsWith('P:') || token.startsWith('p:')) {
        password = token.substring(2);
      } else if (token.startsWith('T:') || token.startsWith('t:')) {
        type = token.substring(2).toUpperCase();
      } else if (token.startsWith('H:') || token.startsWith('h:')) {
        hidden = token.substring(2).toLowerCase() == 'true';
      }
    }

    if (ssid.isNotEmpty) {
      return WifiQrData(
        ssid: ssid,
        password: password,
        encryptionType: type.isEmpty ? 'WPA' : type,
        isHidden: hidden,
      );
    }

    return null;
  }
}
