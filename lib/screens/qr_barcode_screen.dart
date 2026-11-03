import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/calibration/screen_calibrator.dart';
import '../core/theme/app_theme.dart';
import '../services/qr_barcode_service.dart';
import '../services/scanner_service.dart';

class QrBarcodeScreen extends StatefulWidget {
  const QrBarcodeScreen({super.key});

  @override
  State<QrBarcodeScreen> createState() => _QrBarcodeScreenState();
}

class _QrBarcodeScreenState extends State<QrBarcodeScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isScanning = false;
  QrScanResult? _scanResult;
  bool _showPassword = true;

  // Generator form controllers
  final TextEditingController _wifiSsidController = TextEditingController();
  final TextEditingController _wifiPasswordController = TextEditingController();
  String _wifiSecurity = 'WPA';
  final TextEditingController _textQrController = TextEditingController();

  String _generatedQrData = 'https://docubox.app';
  int _generatorMode = 0; // 0 = Wi-Fi, 1 = Text/URL

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _wifiSsidController.dispose();
    _wifiPasswordController.dispose();
    _textQrController.dispose();
    super.dispose();
  }

  Future<void> _pickImageAndScan() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    if (result != null && result.files.single.path != null) {
      _scanImagePath(result.files.single.path!);
    }
  }

  Future<void> _cameraScan() async {
    final paths = await ScannerService.instance.startMLKitScan(pageLimit: 1);
    if (paths.isNotEmpty) {
      _scanImagePath(paths.first);
    }
  }

  Future<void> _scanImagePath(String path) async {
    setState(() => _isScanning = true);
    try {
      final results = await QrBarcodeService.instance.scanImage(path);
      if (results.isNotEmpty) {
        setState(() {
          _scanResult = results.first;
        });
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No QR code or Barcode detected in this image.')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Scan error: $e'), backgroundColor: AppTheme.roseAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isScanning = false);
    }
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppTheme.cardSurfaceLight,
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: AppTheme.emeraldAccent, size: 20),
            const SizedBox(width: 10),
            Text('Copied $label to clipboard!'),
          ],
        ),
      ),
    );
  }

  void _updateGeneratedQr() {
    setState(() {
      if (_generatorMode == 0) {
        // Wi-Fi QR Code format: WIFI:S:MySSID;T:WPA;P:MyPassword;;
        final ssid = _wifiSsidController.text.trim();
        final pwd = _wifiPasswordController.text;
        _generatedQrData = 'WIFI:S:$ssid;T:$_wifiSecurity;P:$pwd;;';
      } else {
        _generatedQrData = _textQrController.text.trim().isEmpty ? 'DocuBox' : _textQrController.text.trim();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    ScreenCalibrator.instance.calibrate(context);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('QR & Wi-Fi Key Hub'),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppTheme.cyanAccent,
          labelColor: AppTheme.cyanAccent,
          unselectedLabelColor: AppTheme.textSecondary,
          tabs: const [
            Tab(icon: Icon(Icons.qr_code_scanner), text: 'Scanner & Wi-Fi Extractor'),
            Tab(icon: Icon(Icons.qr_code_2), text: 'QR Generator'),
          ],
        ),
      ),
      body: Stack(
        children: [
          TabBarView(
            controller: _tabController,
            children: [
              _buildScannerTab(),
              _buildGeneratorTab(),
            ],
          ),
          if (_isScanning)
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

  Widget _buildScannerTab() {
    return SingleChildScrollView(
      padding: EdgeInsets.all(16.w),
      child: Column(
        children: [
          // Action Buttons
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _cameraScan,
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('Camera Scan'),
                ),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickImageAndScan,
                  icon: const Icon(Icons.photo_library),
                  label: const Text('Scan Image'),
                ),
              ),
            ],
          ),
          SizedBox(height: 24.h),

          if (_scanResult == null)
            Container(
              padding: EdgeInsets.symmetric(vertical: 40.h, horizontal: 20.w),
              decoration: BoxDecoration(
                color: AppTheme.cardSurface,
                borderRadius: BorderRadius.circular(16.r),
                border: Border.all(color: AppTheme.border),
              ),
              child: Column(
                children: [
                  Icon(Icons.wifi_find_outlined, size: 64.r, color: AppTheme.cyanAccent.withOpacity(0.6)),
                  SizedBox(height: 14.h),
                  Text(
                    'Instant Wi-Fi Password Extraction',
                    style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 16.sp),
                  ),
                  SizedBox(height: 6.h),
                  Text(
                    'Scan any Wi-Fi QR code from phones, routers, or stickers to instantly reveal its SSID and secret password.',
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 12.5.sp),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          else ...[
            // Specialized Wi-Fi Revealed Card
            if (_scanResult!.type == QrContentType.wifi && _scanResult!.wifiData != null)
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(18.w),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppTheme.cardSurface,
                      AppTheme.cyanAccent.withOpacity(0.12),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(16.r),
                  border: Border.all(color: AppTheme.cyanAccent, width: 1.5),
                  boxShadow: [
                    BoxShadow(color: AppTheme.cyanAccent.withOpacity(0.15), blurRadius: 20),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: EdgeInsets.all(10.r),
                          decoration: BoxDecoration(
                            color: AppTheme.cyanAccent.withOpacity(0.2),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.wifi, color: AppTheme.cyanAccent, size: 28.r),
                        ),
                        SizedBox(width: 14.w),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Wi-Fi Network Detected',
                                style: TextStyle(color: AppTheme.cyanAccent, fontSize: 11.5.sp, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                              ),
                              Text(
                                _scanResult!.wifiData!.ssid,
                                style: TextStyle(color: AppTheme.textPrimary, fontSize: 18.sp, fontWeight: FontWeight.w800),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Divider(color: AppTheme.border, height: 28),

                    // Password Section
                    Text(
                      'WI-FI PASSWORD:',
                      style: TextStyle(color: AppTheme.textMuted, fontSize: 10.5.sp, fontWeight: FontWeight.w800, letterSpacing: 1.0),
                    ),
                    SizedBox(height: 6.h),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
                      decoration: BoxDecoration(
                        color: AppTheme.background,
                        borderRadius: BorderRadius.circular(10.r),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _showPassword ? _scanResult!.wifiData!.password : '••••••••••••',
                              style: TextStyle(
                                color: AppTheme.emeraldAccent,
                                fontSize: 18.sp,
                                fontWeight: FontWeight.bold,
                                letterSpacing: _showPassword ? 1.0 : 3.0,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility, color: AppTheme.textSecondary),
                            onPressed: () => setState(() => _showPassword = !_showPassword),
                          ),
                          IconButton(
                            icon: const Icon(Icons.copy, color: AppTheme.cyanAccent),
                            tooltip: 'Copy Password',
                            onPressed: () => _copyToClipboard(_scanResult!.wifiData!.password, 'Wi-Fi Password'),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 12.h),

                    // Security & Details
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Security: ${_scanResult!.wifiData!.encryptionType}', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12.sp)),
                        TextButton.icon(
                          onPressed: () => _copyToClipboard(_scanResult!.rawValue, 'Raw Config'),
                          icon: const Icon(Icons.share, size: 16),
                          label: const Text('Share Config'),
                        ),
                      ],
                    ),
                  ],
                ),
              )
            else
              // Generic Text / URL Result Card
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(18.w),
                decoration: BoxDecoration(
                  color: AppTheme.cardSurface,
                  borderRadius: BorderRadius.circular(16.r),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _scanResult!.type == QrContentType.url ? Icons.link : Icons.text_snippet,
                          color: AppTheme.cyanAccent,
                        ),
                        SizedBox(width: 10.w),
                        Text(
                          _scanResult!.type.name.toUpperCase(),
                          style: TextStyle(color: AppTheme.cyanAccent, fontWeight: FontWeight.bold, fontSize: 12.sp),
                        ),
                      ],
                    ),
                    SizedBox(height: 12.h),
                    SelectableText(
                      _scanResult!.rawValue,
                      style: TextStyle(color: AppTheme.textPrimary, fontSize: 14.sp, height: 1.4),
                    ),
                    SizedBox(height: 16.h),
                    Row(
                      children: [
                        ElevatedButton.icon(
                          onPressed: () => _copyToClipboard(_scanResult!.rawValue, 'Text'),
                          icon: const Icon(Icons.copy, size: 16),
                          label: const Text('Copy Text'),
                        ),
                        if (_scanResult!.type == QrContentType.url) ...[
                          SizedBox(width: 10.w),
                          OutlinedButton.icon(
                            onPressed: () async {
                              final uri = Uri.parse(_scanResult!.rawValue);
                              if (await canLaunchUrl(uri)) {
                                await launchUrl(uri, mode: LaunchMode.externalApplication);
                              }
                            },
                            icon: const Icon(Icons.open_in_new, size: 16),
                            label: const Text('Open URL'),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildGeneratorTab() {
    return SingleChildScrollView(
      padding: EdgeInsets.all(16.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Mode Switcher
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('Wi-Fi QR'), icon: Icon(Icons.wifi)),
              ButtonSegment(value: 1, label: Text('Text / URL'), icon: Icon(Icons.link)),
            ],
            selected: {_generatorMode},
            onSelectionChanged: (val) {
              setState(() {
                _generatorMode = val.first;
                _updateGeneratedQr();
              });
            },
          ),
          SizedBox(height: 16.h),

          // Inputs based on mode
          if (_generatorMode == 0) ...[
            TextField(
              controller: _wifiSsidController,
              decoration: const InputDecoration(labelText: 'Wi-Fi Network Name (SSID)'),
              onChanged: (_) => _updateGeneratedQr(),
            ),
            SizedBox(height: 12.h),
            TextField(
              controller: _wifiPasswordController,
              decoration: const InputDecoration(labelText: 'Wi-Fi Password'),
              onChanged: (_) => _updateGeneratedQr(),
            ),
            SizedBox(height: 12.h),
            DropdownButtonFormField<String>(
              value: _wifiSecurity,
              decoration: const InputDecoration(labelText: 'Security Encryption'),
              dropdownColor: AppTheme.cardSurface,
              items: const [
                DropdownMenuItem(value: 'WPA', child: Text('WPA / WPA2 / WPA3')),
                DropdownMenuItem(value: 'WEP', child: Text('WEP')),
                DropdownMenuItem(value: 'nopass', child: Text('Open / No Password')),
              ],
              onChanged: (val) {
                if (val != null) {
                  setState(() {
                    _wifiSecurity = val;
                    _updateGeneratedQr();
                  });
                }
              },
            ),
          ] else ...[
            TextField(
              controller: _textQrController,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Text or Website URL (e.g. https://...)'),
              onChanged: (_) => _updateGeneratedQr(),
            ),
          ],
          SizedBox(height: 24.h),

          // Rendered QR Code
          Center(
            child: Container(
              padding: EdgeInsets.all(16.r),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16.r),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 15),
                ],
              ),
              child: QrImageView(
                data: _generatedQrData,
                version: QrVersions.auto,
                size: 200.r,
                backgroundColor: Colors.white,
              ),
            ),
          ),
          SizedBox(height: 18.h),

          Center(
            child: TextButton.icon(
              onPressed: () {
                Share.share(_generatedQrData, subject: 'QR Code Data');
              },
              icon: const Icon(Icons.share, color: AppTheme.cyanAccent),
              label: const Text('Share Raw Config', style: TextStyle(color: AppTheme.cyanAccent)),
            ),
          ),
        ],
      ),
    );
  }
}
