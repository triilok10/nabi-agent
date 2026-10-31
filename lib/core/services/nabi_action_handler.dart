import 'dart:io';

import 'package:flutter/services.dart';

import '../database/db_helper.dart';

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
    DBHelper? database,
    MethodChannel? channel,
    bool? isAndroid,
  })  : _database = database ?? DBHelper.instance,
        _channel =
            channel ?? const MethodChannel('com.trilok.nabi/app_intents'),
        _isAndroid = isAndroid ?? Platform.isAndroid;

  static const Map<String, String> _appPackages = {
    'instagram': 'com.instagram.android',
  };

  final DBHelper _database;
  final MethodChannel _channel;
  final bool _isAndroid;

  static String? packageForCommand(String command) {
    final normalized = command.trim().toLowerCase();
    final opensInstagram =
        RegExp(r'\b(?:open|launch|start)\s+(?:the\s+)?instagram\b')
                .hasMatch(normalized) ||
            RegExp(r'\binstagram\s+(?:open|launch|start|kholo)\b')
                .hasMatch(normalized) ||
            RegExp(r'\binstagram\s+open\s+karo\b').hasMatch(normalized);
    return opensInstagram ? _appPackages['instagram'] : null;
  }

  Future<NabiActionResult> handleCommand(String command) async {
    final input = command.trim();
    if (input.isEmpty) {
      throw ArgumentError.value(command, 'command', 'Command cannot be empty');
    }

    final packageName = packageForCommand(input);
    late final NabiActionResult result;
    if (packageName == null) {
      result = const NabiActionResult(
        response: 'I can currently open Instagram. No action was taken.',
        executionStatus: 'unsupported',
      );
    } else if (!_isAndroid) {
      result = const NabiActionResult(
        response: 'Opening apps is currently supported on Android only.',
        executedAction: 'open_instagram',
        executionStatus: 'unsupported_platform',
      );
    } else {
      try {
        await _channel.invokeMethod<void>(
          'launchApp',
          {'packageName': packageName},
        );
        result = const NabiActionResult(
          response: 'Instagram opened.',
          executedAction: 'open_instagram',
          executionStatus: 'success',
        );
      } on PlatformException catch (error) {
        final response = switch (error.code) {
          'app_not_installed' => 'Instagram is not installed on this device.',
          'app_not_launchable' => 'Instagram could not be opened.',
          _ => 'Could not open Instagram (${error.code}).',
        };
        result = NabiActionResult(
          response: response,
          executedAction: 'open_instagram',
          executionStatus: 'failed',
        );
      } on MissingPluginException {
        result = const NabiActionResult(
          response: 'App launching is unavailable on this Android build.',
          executedAction: 'open_instagram',
          executionStatus: 'failed',
        );
      }
    }

    await _database.insertMemoryLog(
      interactionType: 'command',
      userInput: input,
      systemResponse: result.response,
      executedAction: result.executedAction,
      executionStatus: result.executionStatus,
    );
    return result;
  }
}
