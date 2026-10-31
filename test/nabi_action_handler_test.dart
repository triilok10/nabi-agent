import 'package:flutter_test/flutter_test.dart';
import 'package:nabi_agent/core/services/nabi_action_handler.dart';

void main() {
  group('NabiActionHandler.packageForCommand', () {
    test('maps English and Hindi Instagram open commands', () {
      expect(
        NabiActionHandler.packageForCommand('open instagram'),
        'com.instagram.android',
      );
      expect(
        NabiActionHandler.packageForCommand('Instagram open karo'),
        'com.instagram.android',
      );
    });

    test('does not launch apps for unrelated text', () {
      expect(
        NabiActionHandler.packageForCommand('tell me about Instagram'),
        isNull,
      );
      expect(NabiActionHandler.packageForCommand(''), isNull);
    });
  });
}
