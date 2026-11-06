import 'package:flutter/foundation.dart';

import '../presage/presage_channel.dart';
import '../presage/presage_models.dart';

/// Settings toggles (SPEC.md §2, screen 8). Kept in memory only: nothing is
/// written to disk (SPEC.md §8), so every launch starts from these defaults,
/// with SDK telemetry off.
class AppSettings extends ChangeNotifier {
  bool _hostVoice = true;
  bool _soundEffects = true;
  bool _haptics = true;
  bool _telemetry = false;
  bool _proofPanel = false;

  bool get hostVoice => _hostVoice;
  bool get soundEffects => _soundEffects;
  bool get haptics => _haptics;
  bool get telemetry => _telemetry;
  bool get proofPanel => _proofPanel;

  set hostVoice(bool v) => _set(() => _hostVoice = v);
  set soundEffects(bool v) => _set(() => _soundEffects = v);
  set haptics(bool v) => _set(() => _haptics = v);
  set telemetry(bool v) => _set(() => _telemetry = v);
  set proofPanel(bool v) => _set(() => _proofPanel = v);

  void _set(VoidCallback change) {
    change();
    notifyListeners();
  }
}

enum ApiKeyState {
  /// Asking the Keychain whether a key exists.
  checking,

  /// No key saved: "No key yet" (tomato).
  none,

  /// A key is saved but not tested this session.
  saved,

  /// Test connection in progress.
  testing,

  /// Test connection succeeded: "Connected" (teal).
  connected,

  /// Presage rejected the key or the test failed: "Key rejected" (tomato).
  rejected,
}

/// Drives the Presage API key card. The key itself never comes back from
/// Swift; only [hint] (last 4 characters) is shown.
class ApiKeyController extends ChangeNotifier {
  ApiKeyController(this._api);

  final PresageApi _api;

  ApiKeyState _state = ApiKeyState.checking;
  String? _hint;
  ConnectionTestResult? _lastTest;
  String? _error;

  ApiKeyState get state => _state;
  String? get hint => _hint;
  ConnectionTestResult? get lastTest => _lastTest;

  /// A Keychain or bridge error from the last save/remove, if any.
  String? get error => _error;

  bool get hasKey =>
      _state != ApiKeyState.none && _state != ApiKeyState.checking;

  Future<void> refresh() async {
    try {
      final has = await _api.hasApiKey();
      _hint = has ? await _api.apiKeyHint() : null;
      if (!has) {
        _state = ApiKeyState.none;
      } else if (_state == ApiKeyState.checking || _state == ApiKeyState.none) {
        _state = ApiKeyState.saved;
      }
    } on PresageException catch (e) {
      _state = ApiKeyState.none;
      _error = e.message;
    }
    notifyListeners();
  }

  /// Saves [key] to the Keychain. Returns true on success.
  Future<bool> save(String key) async {
    final trimmed = key.trim();
    if (trimmed.isEmpty) return false;
    try {
      await _api.setApiKey(trimmed);
      _error = null;
      _lastTest = null;
      _state = ApiKeyState.saved;
      _hint = await _api.apiKeyHint();
      notifyListeners();
      return true;
    } on PresageException catch (e) {
      _error = e.message;
      notifyListeners();
      return false;
    }
  }

  Future<void> remove() async {
    try {
      await _api.clearApiKey();
      _error = null;
    } on PresageException catch (e) {
      _error = e.message;
    }
    _hint = null;
    _lastTest = null;
    _state = ApiKeyState.none;
    notifyListeners();
  }

  Future<ConnectionTestResult> test({required bool telemetry}) async {
    _state = ApiKeyState.testing;
    notifyListeners();
    ConnectionTestResult result;
    try {
      result = await _api.testConnection(telemetry: telemetry);
    } on PresageException catch (e) {
      result = ConnectionTestResult(
        ok: false,
        code: e.code,
        message: e.message,
      );
    }
    _lastTest = result;
    if (result.ok) {
      _state = ApiKeyState.connected;
    } else if (result.code == 'NO_KEY') {
      _state = ApiKeyState.none;
    } else if (keyErrorCodes.contains(result.code)) {
      _state = ApiKeyState.rejected;
    } else {
      // Camera, network or timeout problems say nothing about the key itself.
      _state = ApiKeyState.saved;
    }
    notifyListeners();
    return result;
  }

  /// SDK error codes that mean Presage refused this key.
  static const keyErrorCodes = {
    'authenticationFailed',
    'creditExhausted',
    'configurationFailed',
  };
}

/// Plain-language explanation for a bridge/SDK error code.
String describePresageCode(String code, String fallback) => switch (code) {
  'authenticationFailed' => "Presage didn't accept this key.",
  'creditExhausted' => 'This key has run out of credits.',
  'configurationFailed' => 'The SDK configuration was rejected.',
  'networkError' => "Couldn't reach Presage. Check the internet connection.",
  'serverError' => 'Presage had a server problem. Try again in a moment.',
  'inputUnavailable' =>
    'The camera is unavailable. Allow camera access in iOS Settings.',
  'NO_KEY' => 'No Presage API key yet.',
  'BUSY' => 'A measurement is already running.',
  'UNAVAILABLE' => 'The Presage bridge only works on an iPhone.',
  _ => fallback.isEmpty ? code : fallback,
};
