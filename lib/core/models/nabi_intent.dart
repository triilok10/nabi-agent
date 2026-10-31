import 'dart:convert';

enum NabiIntentAction {
  osIntent,
  toggleTorch,
  openCamera,
  openSettings,
  respond,
}

class NabiIntent {
  const NabiIntent({
    required this.action,
    required this.target,
    required this.params,
    this.response,
  });

  final NabiIntentAction action;
  final String target;
  final Map<String, Object?> params;
  final String? response;

  static NabiIntent parse(String modelOutput) {
    final decoded = jsonDecode(_extractJson(modelOutput));
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Intent must be a JSON object.');
    }

    final actionName = decoded['action'];
    final target = decoded['target'];
    final rawParams = decoded['params'];
    final response = decoded['response'];
    if (actionName is! String || target is! String) {
      throw const FormatException('Intent requires string action and target.');
    }
    if (rawParams != null && rawParams is! Map<String, dynamic>) {
      throw const FormatException('Intent params must be a JSON object.');
    }
    if (response != null && response is! String) {
      throw const FormatException('Intent response must be a string.');
    }
    final action = NabiIntentAction.values
        .where((candidate) => _actionName(candidate) == actionName)
        .firstOrNull;
    if (action == null) {
      throw FormatException('Unsupported intent action: $actionName');
    }
    final params = Map<String, Object?>.from(
      rawParams as Map<String, dynamic>? ?? const {},
    );
    if (!_isJsonValue(params)) {
      throw const FormatException('Intent params contain invalid JSON values.');
    }
    _validateIntent(action, target, params);
    return NabiIntent(
      action: action,
      target: target.trim().toLowerCase(),
      params: params,
      response: response as String?,
    );
  }

  static String _extractJson(String text) {
    final trimmed = text.trim();
    if (trimmed.startsWith('{') && trimmed.endsWith('}')) return trimmed;

    var depth = 0;
    var start = -1;
    var inString = false;
    var escaped = false;
    for (var index = 0; index < text.length; index++) {
      final character = text[index];
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (character == r'\') {
          escaped = true;
        } else if (character == '"') {
          inString = false;
        }
        continue;
      }
      if (character == '"') {
        inString = true;
      } else if (character == '{') {
        if (depth == 0) start = index;
        depth++;
      } else if (character == '}') {
        depth--;
        if (depth < 0) break;
        if (depth == 0 && start >= 0) return text.substring(start, index + 1);
      }
    }
    throw const FormatException('Model did not return a JSON intent.');
  }

  static String _actionName(NabiIntentAction action) => switch (action) {
    NabiIntentAction.osIntent => 'OS_INTENT',
    NabiIntentAction.toggleTorch => 'TOGGLE_TORCH',
    NabiIntentAction.openCamera => 'OPEN_CAMERA',
    NabiIntentAction.openSettings => 'OPEN_SETTINGS',
    NabiIntentAction.respond => 'RESPOND',
  };

  static bool _isJsonValue(Object? value) {
    if (value == null || value is String || value is num || value is bool) {
      return true;
    }
    if (value is List) return value.every(_isJsonValue);
    if (value is Map) {
      return value.keys.every((key) => key is String) &&
          value.values.every(_isJsonValue);
    }
    return false;
  }

  static void _validateIntent(
    NabiIntentAction action,
    String target,
    Map<String, Object?> params,
  ) {
    final normalizedTarget = target.trim().toLowerCase();
    switch (action) {
      case NabiIntentAction.osIntent:
        final validApp =
            normalizedTarget == 'app' &&
            params['name'] is String &&
            (params['name']! as String).trim().isNotEmpty;
        final validCamera =
            normalizedTarget == 'camera' &&
            (params.isEmpty ||
                const ['selfie', 'photo'].contains(params['mode']));
        if (!validApp && !validCamera) {
          throw const FormatException(
            'OS_INTENT requires an app name or a supported camera mode.',
          );
        }
        break;
      case NabiIntentAction.toggleTorch:
        if (normalizedTarget != 'torch' ||
            !const ['on', 'off'].contains(params['state'])) {
          throw const FormatException(
            'TOGGLE_TORCH requires target "torch" and state "on" or "off".',
          );
        }
        break;
      case NabiIntentAction.openCamera:
        if (normalizedTarget != 'camera') {
          throw const FormatException('OPEN_CAMERA requires target "camera".');
        }
        break;
      case NabiIntentAction.openSettings:
        if (normalizedTarget != 'settings' ||
            !const [
              'system',
              'notifications',
              'app',
            ].contains(params['section'])) {
          throw const FormatException(
            'OPEN_SETTINGS requires a supported settings section.',
          );
        }
        break;
      case NabiIntentAction.respond:
        if (normalizedTarget != 'user' || params['text'] is! String) {
          throw const FormatException(
            'RESPOND requires target "user" and a string params.text.',
          );
        }
        break;
    }
  }
}
