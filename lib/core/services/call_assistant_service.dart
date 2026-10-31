import 'package:flutter/foundation.dart';

/// Stores a revocable in-app preference only.
///
/// This release deliberately does not answer calls, capture call audio, or
/// invoke an Android call/accessibility service. Consent by the app owner alone
/// cannot establish consent from the other call participant.
class CallAssistantService extends ChangeNotifier {
  bool _isEnabled = false;

  bool get isEnabled => _isEnabled;

  void setEnabled(bool value) {
    if (_isEnabled == value) return;
    _isEnabled = value;
    notifyListeners();
  }
}
