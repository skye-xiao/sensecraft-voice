// Google Sign-In / SenseCraft `oauth/mobile` — Web application client IDs
// (`GoogleSignIn.initialize(serverClientId: …)` → `id_token.aud` matches SenseCraft).
// Android app OAuth client …-26oie… must exist in Google Cloud for `cc.seeed.voice` + SHA-1.
// Web OAuth client IDs — see Google Cloud console for this app.

import '../server_providers.dart' show kDefaultAppEnv;

/// Production / Global Web client (`GOOGLE_WEB_CLIENT_ID_PROD`).
const String kGoogleWebClientIdProd =
    '721415563732-gvsfu25trpg6buls5l6kvpf7fqhfrarg.apps.googleusercontent.com';

/// Test / intranet auth — matches `GOOGLE_WEB_CLIENT_ID_DEV`.
const String kGoogleWebClientIdDev =
    '721415563732-onmkav3p8u5ahq35265am22ulbm6kf9p.apps.googleusercontent.com';

/// Pick Web client id from persisted / compile-time app env (same buckets as
/// [serverConfigProvider] / login env switch).
///
/// Override anytime with `--dart-define=GOOGLE_SERVER_CLIENT_ID=...`.
String googleWebClientIdForAppEnv(String? env) {
  final e = (env ?? kDefaultAppEnv).trim().toLowerCase();
  switch (e) {
    case 'prod':
    case 'production':
    case 'release':
      return kGoogleWebClientIdProd;
    case 'test':
    case 'testing':
    case 'qa':
    case 'uat':
    case 'dev':
    case 'debug':
    case 'local':
    default:
      return kGoogleWebClientIdDev;
  }
}
