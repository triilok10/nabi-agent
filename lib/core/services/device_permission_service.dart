import 'dart:io';

import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

enum DevicePermissionResult {
  granted,
  denied,
  permanentlyDenied,
  restricted,
  notRequired,
}

class DevicePermissionService {
  DevicePermissionService({MethodChannel? channel, bool? isAndroid})
    : _channel =
          channel ?? const MethodChannel('com.nabi.agent/system_actions'),
      _isAndroid = isAndroid ?? Platform.isAndroid;

  final MethodChannel _channel;
  final bool _isAndroid;

  Future<DevicePermissionResult> requestMicrophonePermission() async {
    if (!_isAndroid) return DevicePermissionResult.notRequired;
    return _request(Permission.microphone);
  }

  Future<DevicePermissionResult> requestCameraPermission() async {
    return _request(Permission.camera);
  }

  Future<DevicePermissionResult> requestStoragePermission() async {
    if (!_isAndroid) return DevicePermissionResult.notRequired;

    final sdkInt = await _channel.invokeMethod<int>('getAndroidSdkInt');
    if (sdkInt == null) {
      throw PlatformException(
        code: 'android_sdk_unavailable',
        message: 'Could not determine Android version for storage permission.',
      );
    }
    if (sdkInt >= 33) return DevicePermissionResult.notRequired;

    return _request(Permission.storage);
  }

  Future<DevicePermissionResult> _request(Permission permission) async {
    final status = await permission.request();
    if (status.isGranted || status.isLimited) {
      return DevicePermissionResult.granted;
    }
    if (status.isPermanentlyDenied) {
      return DevicePermissionResult.permanentlyDenied;
    }
    if (status.isRestricted) return DevicePermissionResult.restricted;
    return DevicePermissionResult.denied;
  }
}
