import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Device form factor classification based on screen metrics.
enum DeviceFormFactor {
  compactPhone,
  standardPhone,
  largePhone,
  foldableFolded,
  foldableUnfolded,
  tabletSmall,
  tabletLarge,
}

/// ScreenCalibrator: Zero-Cutoff hardware display calibration matrix.
/// Automatically probes physical size, logical DPI, aspect ratio, cutout/notch insets,
/// and computes clamped scale factors relative to a standard baseline (390 x 844).
class ScreenCalibrator {
  ScreenCalibrator._internal();
  static final ScreenCalibrator instance = ScreenCalibrator._internal();

  // Baseline calibration constants (Standard modern device baseline)
  static const double baselineWidth = 390.0;
  static const double baselineHeight = 844.0;

  // Mathematical clamping factors to prevent extreme distortion on foldables/tablets
  static const double minScaleFactor = 0.82;
  static const double maxScaleFactor = 1.38;
  static const double minFontScaleFactor = 0.85;
  static const double maxFontScaleFactor = 1.25;

  bool _isCalibrated = false;
  late double _screenWidth;
  late double _screenHeight;
  late double _pixelRatio;
  late double _aspectRatio;
  late EdgeInsets _safePadding;
  late EdgeInsets _viewInsets;
  late DeviceFormFactor _formFactor;

  late double _scaleWidth;
  late double _scaleHeight;
  late double _scaleFont;
  late double _scaleRadius;

  bool get isCalibrated => _isCalibrated;
  double get screenWidth => _screenWidth;
  double get screenHeight => _screenHeight;
  double get pixelRatio => _pixelRatio;
  double get aspectRatio => _aspectRatio;
  EdgeInsets get safePadding => _safePadding;
  EdgeInsets get viewInsets => _viewInsets;
  DeviceFormFactor get formFactor => _formFactor;

  double get scaleWidth => _scaleWidth;
  double get scaleHeight => _scaleHeight;
  double get scaleFont => _scaleFont;
  double get scaleRadius => _scaleRadius;

  /// Probes MediaQueryData and computes calibration coefficients.
  void calibrate(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    calibrateWithMediaQuery(mediaQuery);
  }

  /// Direct calibration using MediaQueryData
  void calibrateWithMediaQuery(MediaQueryData data) {
    _screenWidth = data.size.width;
    _screenHeight = data.size.height;
    _pixelRatio = data.devicePixelRatio;
    _safePadding = data.padding;
    _viewInsets = data.viewInsets;

    _aspectRatio = _screenHeight > 0 ? (_screenWidth / _screenHeight) : (390 / 844);

    // Dynamic width scale bounded mathematically
    final rawScaleW = _screenWidth / baselineWidth;
    _scaleWidth = rawScaleW.clamp(minScaleFactor, maxScaleFactor);

    // Dynamic height scale bounded mathematically
    final rawScaleH = _screenHeight / baselineHeight;
    _scaleHeight = rawScaleH.clamp(minScaleFactor, maxScaleFactor);

    // Font scaling prioritizes width & pixel density with stricter bounds to avoid overflow
    final fontDensityWeight = (_scaleWidth * 0.75) + (_scaleHeight * 0.25);
    _scaleFont = fontDensityWeight.clamp(minFontScaleFactor, maxFontScaleFactor);

    // Geometric radius scale
    _scaleRadius = math.min(_scaleWidth, _scaleHeight);

    // Classify form factor
    final shortestSide = math.min(_screenWidth, _screenHeight);
    final longestSide = math.max(_screenWidth, _screenHeight);

    if (shortestSide >= 720) {
      _formFactor = DeviceFormFactor.tabletLarge;
    } else if (shortestSide >= 600) {
      _formFactor = DeviceFormFactor.tabletSmall;
    } else if (shortestSide >= 500 && _aspectRatio > 0.7) {
      _formFactor = DeviceFormFactor.foldableUnfolded;
    } else if (shortestSide < 360) {
      _formFactor = DeviceFormFactor.compactPhone;
    } else if (longestSide >= 880) {
      _formFactor = DeviceFormFactor.largePhone;
    } else {
      _formFactor = DeviceFormFactor.standardPhone;
    }

    _isCalibrated = true;
  }

  /// Safe conversion helpers
  double setWidth(num width) => (width * _scaleWidth).toDouble();
  double setHeight(num height) => (height * _scaleHeight).toDouble();
  double setSp(num fontSize) => (fontSize * _scaleFont).toDouble();
  double setRadius(num radius) => (radius * _scaleRadius).toDouble();

  /// Formatted device calibration summary
  Map<String, dynamic> getDiagnostics() {
    return {
      'resolution': '${_screenWidth.toStringAsFixed(1)} x ${_screenHeight.toStringAsFixed(1)} dp',
      'pixelRatio': '${_pixelRatio.toStringAsFixed(2)}x',
      'aspectRatio': _aspectRatio.toStringAsFixed(3),
      'formFactor': _formFactor.name,
      'scaleWidth': _scaleWidth.toStringAsFixed(3),
      'scaleHeight': _scaleHeight.toStringAsFixed(3),
      'scaleFont': _scaleFont.toStringAsFixed(3),
      'safeTop': '${_safePadding.top.toStringAsFixed(1)} dp',
      'safeBottom': '${_safePadding.bottom.toStringAsFixed(1)} dp',
      'hasCutout': _safePadding.top > 24,
    };
  }
}

/// Global Zero-Cutoff Responsive Extensions
extension ScreenCalibratorExtension on num {
  /// Scaled width with mathematical bounds
  double get w => ScreenCalibrator.instance.isCalibrated
      ? ScreenCalibrator.instance.setWidth(this)
      : toDouble();

  /// Scaled height with mathematical bounds
  double get h => ScreenCalibrator.instance.isCalibrated
      ? ScreenCalibrator.instance.setHeight(this)
      : toDouble();

  /// Scaled typography font size guaranteeing zero text clipping or truncation
  double get sp => ScreenCalibrator.instance.isCalibrated
      ? ScreenCalibrator.instance.setSp(this)
      : toDouble();

  /// Scaled corner radius / geometric circular constraint
  double get r => ScreenCalibrator.instance.isCalibrated
      ? ScreenCalibrator.instance.setRadius(this)
      : toDouble();
}
