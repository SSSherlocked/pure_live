import 'dart:async';

import 'package:pure_live/core/index.dart';
import 'package:pure_live/core/network/douyu_utils.dart';
import 'package:pure_live/core/network/cookie_sanitizer.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:pure_live/core/config/cookie_settings_controller.dart';

/// Douyu's passport sign-in page, returning to the site afterwards.
const String douyuWebLoginUrl =
    'https://passport.douyu.com/index/login?passport_reuri=https%3A%2F%2Fwww.douyu.com%2F'
    '&passport_jumpUrl=https%3A%2F%2Fwww.douyu.com%2F&type=login&client_id=1';

/// Where the page session (`dy_auth` / `acf_*`) lives.
final WebUri douyuSiteCookieUri = WebUri('https://www.douyu.com/');

/// Where the renewal key `LTP0` and the login's `dy_did` live.
final WebUri douyuPassportCookieUri = WebUri('https://passport.douyu.com/');

/// Reads the WebView's cookies for one address, as name → value.
typedef DouyuWebCookieLoader = Future<Map<String, String>> Function(WebUri uri);

/// Renews [cookie] with [ltp0] and [did]; the renewed cookie, or null.
typedef DouyuSessionRenewer = Future<String?> Function({
  required String cookie,
  required String ltp0,
  required String did,
});

/// Stores the renewal pair once the renewal has proved it works.
typedef DouyuCredentialSaver = void Function({required String ltp0, required String did});

typedef DouyuWebLoginCompletion = void Function();

/// Signs in to Douyu inside a WebView and takes the cookies from it.
///
/// A sign-in only counts when everything the app needs to stay signed in was
/// obtained *and works*: the page session, the long-term key `LTP0` and the
/// device id `dy_did`, and one renewal with them that the passport endpoint
/// actually answers. Anything less stores nothing, so a half login can never
/// replace a working one.
///
/// The cookies are read from the WebView's native store, which also holds the
/// HttpOnly ones a page script cannot see — that is what makes `LTP0`, kept by
/// `passport.douyu.com`, reachable at all.
class DouyuWebLoginController extends GetxController {
  DouyuWebLoginController({
    DouyuWebCookieLoader? cookieLoader,
    DouyuSessionRenewer? renewer,
    DouyuCredentialSaver? saveCredentials,
    DouyuWebLoginCompletion? completeLogin,
    this.transitionDelay = const Duration(milliseconds: 300),
  }) : _cookieLoader = cookieLoader ?? _loadBrowserCookies,
       _renewer = renewer ?? _renewSession,
       _saveCredentials = saveCredentials ?? _storeCredentials,
       _completeLogin = completeLogin ?? _finishLogin;

  final DouyuWebCookieLoader _cookieLoader;
  final DouyuSessionRenewer _renewer;
  final DouyuCredentialSaver _saveCredentials;
  final DouyuWebLoginCompletion _completeLogin;
  final Duration transitionDelay;

  InAppWebViewController? webViewController;
  final showWebView = true.obs;
  final isVerifying = false.obs;
  final errorMessageKey = ''.obs;

  Future<void>? _activeCheck;
  int _revision = 0;
  bool _completed = false;
  bool _closed = false;

  void onWebViewCreated(InAppWebViewController controller) {
    if (_closed) return;
    webViewController = controller;
  }

  /// Every finished Douyu page is a chance that the sign-in just completed.
  ///
  /// Quiet: a page loaded before signing in is not an error.
  void onLoadStop(InAppWebViewController _, WebUri? uri) {
    final host = uri?.host.toLowerCase() ?? '';
    if (host == 'douyu.com' || host.endsWith('.douyu.com')) unawaited(checkLogin());
  }

  /// The viewer says they are signed in: check, and explain what is missing.
  Future<void> checkNow() => checkLogin(reportMissingSession: true);

  Future<void> checkLogin({bool reportMissingSession = false}) {
    if (_closed || _completed) return Future.value();
    final active = _activeCheck;
    if (active != null) return active;

    final revision = ++_revision;
    late final Future<void> task;
    task = _check(revision, reportMissingSession: reportMissingSession).whenComplete(() {
      if (identical(_activeCheck, task)) _activeCheck = null;
    });
    _activeCheck = task;
    return task;
  }

  Future<void> _check(int revision, {required bool reportMissingSession}) async {
    Map<String, String> site;
    Map<String, String> passport;
    try {
      site = await _cookieLoader(douyuSiteCookieUri);
      passport = await _cookieLoader(douyuPassportCookieUri);
    } catch (_) {
      if (_isCurrent(revision)) _showError('douyu_web_login_cookie_failed');
      return;
    }
    if (!_isCurrent(revision)) return;

    final session = sessionCookieFrom(site);
    if (DouyuUtils.sessionToken(session) == null) {
      // Not signed in yet; only a request from the viewer deserves an answer.
      if (reportMissingSession) _showError('douyu_web_login_no_session');
      return;
    }

    final ltp0 = _field(passport, DouyuUtils.longTermTokenName) ?? _field(site, DouyuUtils.longTermTokenName);
    if (ltp0 == null) {
      _showError('douyu_web_login_no_ltp0');
      return;
    }
    // The renewal has to present the device the login was issued to, which is
    // the passport's; the site cookie normally carries the same one.
    final did = _field(passport, DouyuUtils.deviceIdName) ?? _field(site, DouyuUtils.deviceIdName);
    if (did == null) {
      _showError('douyu_web_login_no_did');
      return;
    }

    isVerifying.value = true;
    errorMessageKey.value = '';
    String? renewed;
    try {
      renewed = await _renewer(cookie: session, ltp0: ltp0, did: did);
    } catch (_) {
      renewed = null;
    }
    if (!_isCurrent(revision)) return;
    if (renewed == null) {
      _showError('douyu_web_login_refresh_failed');
      return;
    }

    _saveCredentials(ltp0: ltp0, did: did);
    _completed = true;
    showWebView.value = false;
    await Future<void>.delayed(transitionDelay);
    if (_closed) return;
    isVerifying.value = false;
    _completeLogin();
  }

  /// The page session as a Cookie header: everything the site holds except
  /// `LTP0`, which belongs to the passport and is stored on its own.
  static String sessionCookieFrom(Map<String, String> site) {
    final pieces = <String>[
      for (final entry in site.entries)
        if (entry.key.toLowerCase() != DouyuUtils.longTermTokenName.toLowerCase() && entry.value.trim().isNotEmpty)
          '${entry.key}=${entry.value.trim()}',
    ];
    return normalizeAccountCookie(pieces.join('; '));
  }

  static String? _field(Map<String, String> cookies, String name) {
    final wanted = name.toLowerCase();
    for (final entry in cookies.entries) {
      if (entry.key.toLowerCase() == wanted) {
        final value = entry.value.trim();
        return value.isEmpty ? null : value;
      }
    }
    return null;
  }

  void _showError(String messageKey) {
    isVerifying.value = false;
    showWebView.value = true;
    errorMessageKey.value = messageKey;
  }

  bool _isCurrent(int revision) => !_closed && revision == _revision;

  @override
  void onClose() {
    _closed = true;
    _revision++;
    webViewController = null;
    super.onClose();
  }

  static Future<Map<String, String>> _loadBrowserCookies(WebUri uri) async {
    final cookies = await CookieManager.instance().getCookies(url: uri);
    return <String, String>{
      for (final cookie in cookies)
        if (cookie.name.isNotEmpty && cookie.value != null) cookie.name: '${cookie.value}',
    };
  }

  /// One forced renewal. On success [DouyuUtils.refreshSession] has already
  /// stored the renewed cookie and its save time.
  static Future<String?> _renewSession({required String cookie, required String ltp0, required String did}) {
    return DouyuUtils.refreshSession(accountCookie: cookie, longTerm: ltp0, did: did, force: true);
  }

  static void _storeCredentials({required String ltp0, required String did}) {
    final cookies = CookieSettingsController.to;
    cookies.douyuLtp0.v = ltp0;
    cookies.douyuDid.v = did;
  }

  static void _finishLogin() {
    ToastUtil.show(i18n('douyu_web_login_success'));
    Navigator.of(Get.context!).pop(true);
  }
}
