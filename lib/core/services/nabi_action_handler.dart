import 'dart:io';

import 'package:flutter/services.dart';

import '../database/db_helper.dart';
import '../models/nabi_intent.dart';
import 'device_permission_service.dart';
import 'local_model_bridge.dart';

class NabiActionResult {
  const NabiActionResult({
    required this.response,
    required this.executionStatus,
    this.executedAction,
  });

  final String response;
  final String executionStatus;
  final String? executedAction;

  bool get succeeded => executionStatus == 'success';
}

class NabiActionHandler {
  NabiActionHandler({
    LocalModelIntegrationBridge? model,
    String? modelUnavailableReason,
    DBHelper? database,
    MethodChannel? channel,
    bool? isAndroid,
  }) : _model = model,
       _modelUnavailableReason = modelUnavailableReason,
       _database = database ?? DBHelper.instance,
       _channel =
           channel ?? const MethodChannel('com.nabi.agent/system_actions'),
       _isAndroid = isAndroid ?? Platform.isAndroid;

  final LocalModelIntegrationBridge? _model;
  final String? _modelUnavailableReason;
  final DBHelper _database;
  final MethodChannel _channel;
  final bool _isAndroid;
  final DevicePermissionService _permissions = DevicePermissionService();

  Future<NabiActionResult> handleCommand(String command) async {
    final input = command.trim();
    if (input.isEmpty) {
      throw ArgumentError.value(command, 'command', 'Command cannot be empty');
    }

    try {
      final model = _model;
      if (model == null) {
        throw StateError(
          _modelUnavailableReason ?? 'The local model is not configured.',
        );
      }
      final intent = await model.parseInput(input);
      final result = await _execute(intent);
      await _database.insertMemoryLog(
        interactionType: 'command',
        userInput: input,
        systemResponse: result.response,
        executedAction: result.executedAction,
        executionStatus: result.executionStatus,
      );
      return result;
    } catch (error) {
      await _database.insertMemoryLog(
        interactionType: 'command',
        userInput: input,
        systemResponse: 'Local intent processing failed: $error',
        executionStatus: 'failed',
      );
      rethrow;
    }
  }

  Future<NabiActionResult> _execute(NabiIntent intent) async {
    final action = switch (intent.action) {
      NabiIntentAction.osIntent =>
        intent.target == 'camera' ? 'open_camera' : 'launch_app',
      NabiIntentAction.toggleTorch => 'toggle_torch',
      NabiIntentAction.openCamera => 'open_camera',
      NabiIntentAction.openSettings => 'open_settings',
      NabiIntentAction.respond => null,
    };
    if (action == null) {
      return NabiActionResult(
        response: intent.params['text']! as String,
        executionStatus: 'success',
      );
    }
    if (!_isAndroid) {
      return NabiActionResult(
        response: 'This system action is not available on this platform.',
        executedAction: action,
        executionStatus: 'unsupported_platform',
      );
    }

    if (intent.action == NabiIntentAction.toggleTorch) {
      final permission = await _permissions.requestCameraPermission();
      if (permission != DevicePermissionResult.granted) {
        return const NabiActionResult(
          response:
              'Camera permission was not granted; enable it in system settings to use the flashlight.',
          executedAction: 'toggle_torch',
          executionStatus: 'permission_denied',
        );
      }
    }

    try {
      final response = await _channel.invokeMapMethod<String, Object?>(
        'executeAction',
        {'action': action, 'target': intent.target, 'params': intent.params},
      );
      if (response == null || response['status'] != 'success') {
        throw PlatformException(
          code: 'invalid_action_response',
          message: 'Android returned an invalid action response.',
        );
      }
      return NabiActionResult(
        response: response['message'] as String? ?? 'Action completed.',
        executedAction: action,
        executionStatus: 'success',
      );
    } on PlatformException catch (error) {
      final message = switch (error.code) {
        'app_not_found' =>
          'Could not find that installed app. Check the app name and try again.',
        'ambiguous_app' =>
          'More than one installed app matches. Specify its full app name.',
        'camera_permission_required' =>
          'Camera permission is required for flashlight control.',
        'permission_denied' =>
          'Camera permission was not granted; enable it in system settings to use the flashlight.',
        'action_not_available' =>
          'This action is not available on the current device.',
        'unsupported_action' => 'The requested system action is not supported.',
        _ => 'The system action failed (${error.code}).',
      };
      return NabiActionResult(
        response: message,
        executedAction: action,
        executionStatus: 'failed',
      );
    } on MissingPluginException {
      return NabiActionResult(
        response: 'System actions are unavailable in this platform build.',
        executedAction: action,
        executionStatus: 'failed',
      );
    }
  }
}
