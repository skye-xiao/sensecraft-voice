import 'dart:io' show Platform;

import 'package:shared_preferences/shared_preferences.dart';

/// Compile-time switch for domestic China Android builds.
///
/// Enable with: `--dart-define=HIDE_THIRD_PARTY_LOGIN=true`
///
/// App API envs stay `release` (prod) / `test` only — do **not** use a separate
/// `china` APP_ENV for packaging; hide third-party login via this define.
const bool kHideThirdPartyLoginDefine =
    bool.fromEnvironment('HIDE_THIRD_PARTY_LOGIN', defaultValue: false);

bool defaultHideThirdPartyLogin() => kHideThirdPartyLoginDefine;

/// Persists whether third-party login (Google / GitHub / Apple) is shown.
///
/// On Android the value is user-toggleable in Settings. Non-Android always
/// shows third-party options (Apple remains platform-gated on the login page).
class ThirdPartyLoginStore {
  static const _kShow = 'show_third_party_login';

  /// `null` means "use [defaultHideThirdPartyLogin]".
  static bool? _cachedShow;

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey(_kShow)) {
      _cachedShow = prefs.getBool(_kShow);
    } else {
      _cachedShow = null;
    }
  }

  /// Whether the login landing page should show the third-party block.
  static bool get showThirdPartyLogin {
    if (!Platform.isAndroid) return true;
    if (_cachedShow != null) return _cachedShow!;
    return !defaultHideThirdPartyLogin();
  }

  static Future<void> setShowThirdPartyLogin(bool show) async {
    _cachedShow = show;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kShow, show);
  }
}
