import 'package:flutter_test/flutter_test.dart';
import 'package:nabi_agent/core/models/nabi_intent.dart';

void main() {
  group('NabiIntent.parse', () {
    test('parses an app-launch intent from raw model JSON', () {
      final intent = NabiIntent.parse(
        '{"action":"OS_INTENT","target":"app",'
        '"params":{"name":"Instagram"}}',
      );

      expect(intent.action, NabiIntentAction.osIntent);
      expect(intent.target, 'app');
      expect(intent.params['name'], 'Instagram');
    });

    test('extracts one JSON object from model formatting', () {
      final intent = NabiIntent.parse(
        '```json\n{"action":"TOGGLE_TORCH","target":"torch",'
        '"params":{"state":"on"}}\n```',
      );

      expect(intent.action, NabiIntentAction.toggleTorch);
      expect(intent.params['state'], 'on');
    });

    test('accepts a semantic camera intent with selfie mode', () {
      final intent = NabiIntent.parse(
        '{"action":"OS_INTENT","target":"camera",'
        '"params":{"mode":"selfie"}}',
      );

      expect(intent.action, NabiIntentAction.osIntent);
      expect(intent.target, 'camera');
      expect(intent.params['mode'], 'selfie');
    });

    test('normalizes intent targets before dispatch', () {
      final intent = NabiIntent.parse(
        '{"action":"OS_INTENT","target":"CAMERA",'
        '"params":{"mode":"photo"}}',
      );

      expect(intent.target, 'camera');
    });

    test('rejects unknown actions and malformed action parameters', () {
      expect(
        () => NabiIntent.parse(
          '{"action":"RUN_SHELL","target":"system","params":{}}',
        ),
        throwsFormatException,
      );
      expect(
        () => NabiIntent.parse(
          '{"action":"TOGGLE_TORCH","target":"torch",'
          '"params":{"state":"maybe"}}',
        ),
        throwsFormatException,
      );
    });
  });
}
