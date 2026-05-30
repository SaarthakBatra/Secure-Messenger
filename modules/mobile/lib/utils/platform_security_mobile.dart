import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_windowmanager/flutter_windowmanager.dart';
import 'package:screen_protector/screen_protector.dart';

class PlatformSecurityService {
  static Future<void> updateNativeSecurity(bool isVaultActive) async {
    if (Platform.isAndroid) {
      try {
        const channel = MethodChannel('com.example.mobile/security');
        await channel.invokeMethod('setVaultActive', isVaultActive);
      } catch (e) {
        debugPrint('[SECURITY] Failed to invoke setVaultActive on channel: $e');
      }
      
      if (isVaultActive) {
        await FlutterWindowManager.addFlags(FlutterWindowManager.FLAG_SECURE);
      } else {
        await FlutterWindowManager.clearFlags(FlutterWindowManager.FLAG_SECURE);
      }
    }
    if (Platform.isIOS) {
      if (isVaultActive) {
        await ScreenProtector.protectDataLeakageWithColor(const Color(0xFF0F2027));
        await ScreenProtector.preventScreenshotOn();
      } else {
        await ScreenProtector.preventScreenshotOff();
      }
    }
  }
}
