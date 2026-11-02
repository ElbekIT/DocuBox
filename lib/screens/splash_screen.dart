import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import '../core/calibration/screen_calibrator.dart';
import '../core/theme/app_theme.dart';
import 'home_dashboard.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _progressController;
  late Animation<double> _progressAnimation;
  String _currentStatus = 'Probing display matrix & pixel density...';

  @override
  void initState() {
    super.initState();

    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );

    _progressAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _progressController, curve: Curves.easeInOutCubic),
    )..addListener(() {
        final progress = (_progressAnimation.value * 100).toInt();
        setState(() {
          if (progress <= 25) {
            _currentStatus = 'Probing display matrix & pixel density...';
          } else if (progress <= 55) {
            _currentStatus = 'Computing aspect ratio & safe-area margins...';
          } else if (progress <= 85) {
            _currentStatus = 'Synthesizing responsive typography matrix...';
          } else {
            _currentStatus = 'Calibration Complete: 100% Device Synergy.';
          }
        });
      });

    _progressController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) {
            Navigator.of(context).pushReplacement(
              PageRouteBuilder(
                pageBuilder: (context, anim1, anim2) => const HomeDashboardScreen(),
                transitionsBuilder: (context, anim1, anim2, child) {
                  return FadeTransition(opacity: anim1, child: child);
                },
                transitionDuration: const Duration(milliseconds: 500),
              ),
            );
          }
        });
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      ScreenCalibrator.instance.calibrate(context);
      _progressController.forward();
    });
  }

  @override
  void dispose() {
    _progressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Proactive calibration in build
    ScreenCalibrator.instance.calibrate(context);

    final progressPercent = (_progressAnimation.value * 100).toInt().clamp(0, 100);

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 28.w),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Top Hardware Telemetry Badge
              Padding(
                padding: EdgeInsets.only(top: 24.h),
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 6.h),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(20.r),
                    border: Border.all(color: AppTheme.borderSubtle),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 7.r,
                        height: 7.r,
                        decoration: const BoxDecoration(
                          color: AppTheme.cyanAccent,
                          shape: BoxShape.circle,
                        ),
                      ),
                      SizedBox(width: 8.w),
                      Text(
                        'HARDWARE SYNERGY ENGINE',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 10.5.sp,
                          letterSpacing: 1.2,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Center Logo & Insignia
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 110.r,
                    height: 110.r,
                    decoration: BoxDecoration(
                      color: AppTheme.cardSurface,
                      borderRadius: BorderRadius.circular(28.r),
                      border: Border.all(color: AppTheme.cyanAccent.withOpacity(0.3), width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.cyanAccent.withOpacity(0.12),
                          blurRadius: 30,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Image.asset(
                      'assets/icons/app_icon.png',
                      fit: BoxFit.cover,
                      errorBuilder: (ctx, err, stack) {
                        return Center(
                          child: Icon(
                            Icons.folder_zip_rounded,
                            color: AppTheme.cyanAccent,
                            size: 54.r,
                          ),
                        );
                      },
                    ),
                  ),
                  SizedBox(height: 24.h),
                  Text(
                    'DocuBox',
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 32.sp,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                  SizedBox(height: 8.h),
                  Text(
                    'Universal Suite • Zero-Telemetry • 100% Local',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12.5.sp,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),

              // Bottom Progress Bar & Calibration Status Ticker
              Padding(
                padding: EdgeInsets.only(bottom: 32.h),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Percent and Ticker
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            _currentStatus,
                            style: TextStyle(
                              color: AppTheme.cyanAccent,
                              fontSize: 11.5.sp,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        SizedBox(width: 8.w),
                        Text(
                          '$progressPercent%',
                          style: TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 13.sp,
                            fontWeight: FontWeight.w700,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 10.h),

                    // Progress Bar
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8.r),
                      child: Container(
                        height: 6.h,
                        width: double.infinity,
                        color: AppTheme.surface,
                        child: FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: _progressAnimation.value.clamp(0.0, 1.0),
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [
                                  AppTheme.blueAccent,
                                  AppTheme.cyanAccent,
                                  AppTheme.emeraldAccent,
                                ],
                              ),
                              borderRadius: BorderRadius.circular(8.r),
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.cyanAccent.withOpacity(0.5),
                                  blurRadius: 8,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: 14.h),

                    // Military-Grade Local Shield Notice
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.shield_outlined, color: AppTheme.emeraldAccent, size: 14.r),
                        SizedBox(width: 6.w),
                        Text(
                          'AES-256 Armed • Zero Cloud Telemetry',
                          style: TextStyle(
                            color: AppTheme.textMuted,
                            fontSize: 11.sp,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
