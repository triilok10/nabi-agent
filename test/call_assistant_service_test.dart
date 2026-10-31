import 'package:flutter_test/flutter_test.dart';
import 'package:nabi_agent/core/services/call_assistant_service.dart';

void main() {
  group('CallAssistantService', () {
    test('starts disabled and emits changes when preference is updated', () {
      final service = CallAssistantService();
      var notifications = 0;
      service.addListener(() => notifications++);

      expect(service.isEnabled, isFalse);
      service.setEnabled(true);
      expect(service.isEnabled, isTrue);
      expect(notifications, 1);

      service.setEnabled(false);
      expect(service.isEnabled, isFalse);
      expect(notifications, 2);

      service.dispose();
    });

    test('does not notify when preference is unchanged', () {
      final service = CallAssistantService();
      var notifications = 0;
      service.addListener(() => notifications++);

      service.setEnabled(false);
      expect(notifications, 0);

      service.dispose();
    });
  });
}
