import 'dart:async';

import 'package:pure_live/core/index.dart';
import 'package:pure_live/core/network/douyu_utils.dart';
import 'package:pure_live/core/network/cookie_sanitizer.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:pure_live/core/config/cookie_settings_controller.dart';

/// Douyu's own sign-in entry (the site's 登录 link). It forwards to the passport
/// page with the parameters Douyu expects; a hand-built passport URL made the
/// post-login redirect fail with 参数错误.
const String douyuWebLoginUrl = 'https://www.douyu.com/member/login';

/// How often the open login page re-reads the cookies. Douyu finishes a sign-in
/// with in-page requests and script redirects, so page loads alone miss it.
const Duration douyuWebLoginPollInterval = Duration(seconds: 2);

/// Where the page session (`dy_auth` / `acf_*`) lives.
final WebUri douyuSiteCookieUri = WebUri('https://www.douyu.com/');

/// Where the H5 (phone) sign-in may leave its session instead.
final WebUri douyuMobileSiteCookieUri = WebUri('https://m.douyu.com/');

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

  /// A non-error status, e.g. signed in but still waiting for LTP0.
  final infoMessageKey = ''.obs;

  Future<void>? _activeCheck;
  Timer? _pollTimer;
  int _revision = 0;
  bool _completed = false;
  bool _closed = false;

  /// Set after a failed renewal: automatic checks stop retrying it (it is a
  /// request to Douyu, not a local read) until the viewer asks again.
  bool _autoChecksSuspended = false;

  void onWebViewCreated(InAppWebViewController controller) {
    if (_closed) return;
    webViewController = controller;
    _pollTimer ??= Timer.periodic(douyuWebLoginPollInterval, (_) => unawaited(checkLogin()));
  }

  /// A finished Douyu page is a chance that the sign-in just completed.
  void onLoadStop(InAppWebViewController _, WebUri? uri) => _onDouyuPage(uri);

  /// So is any URL change, including script redirects that never "finish".
  void onUpdateVisitedHistory(InAppWebViewController _, WebUri? uri, bool? isReload) => _onDouyuPage(uri);

  void _onDouyuPage(WebUri? uri) {
    final host = uri?.host.toLowerCase() ?? '';
    if (host == 'douyu.com' || host.endsWith('.douyu.com')) unawaited(checkLogin());
  }

  /// The viewer says they are signed in: check, and explain what is missing.
  Future<void> checkNow() {
    _autoChecksSuspended = false;
    return checkLogin(reportMissingSession: true);
  }

  /// Checks whether the sign-in is complete. Automatic checks (page loads,
  /// the poll) stay quiet about what is not there yet; [reportMissingSession]
  /// is the viewer asking, and gets an explanation.
  Future<void> checkLogin({bool reportMissingSession = false}) {
    if (_closed || _completed) return Future.value();
    if (!reportMissingSession && _autoChecksSuspended) return Future.value();
    final active = _activeCheck;
    if (active != null) {
      // A quiet check in flight must not swallow the viewer's request for an
      // answer: run the reporting check once it is done.
      return reportMissingSession ? active.then((_) => checkLogin(reportMissingSession: true)) : active;
    }

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
      // Phones sign in through Douyu's H5 page, which may keep the session on
      // m.douyu.com; the www values win where both have one.
      site = {...await _cookieLoader(douyuMobileSiteCookieUri), ...await _cookieLoader(douyuSiteCookieUri)};
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

    // LTP0 and dy_did can arrive a moment after the session: an automatic check
    // waits for them, an explicit one says what is missing.
    final ltp0 = _field(passport, DouyuUtils.longTermTokenName) ?? _field(site, DouyuUtils.longTermTokenName);
    if (ltp0 == null) {
      reportMissingSession ? _showError('douyu_web_login_no_ltp0') : _showInfo('douyu_web_login_waiting_ltp0');
      return;
    }
    // The renewal has to present the device the login was issued to, which is
    // the passport's; the site cookie normally carries the same one.
    final did = _field(passport, DouyuUtils.deviceIdName) ?? _field(site, DouyuUtils.deviceIdName);
    if (did == null) {
      reportMissingSession ? _showError('douyu_web_login_no_did') : _showInfo('douyu_web_login_waiting_ltp0');
      return;
    }

    isVerifying.value = true;
    errorMessageKey.value = '';
    infoMessageKey.value = '';
    String? renewed;
    try {
      renewed = await _renewer(cookie: session, ltp0: ltp0, did: did);
    } catch (_) {
      renewed = null;
    }
    if (!_isCurrent(revision)) return;
    if (renewed == null) {
      _autoChecksSuspended = true;
      _showError('douyu_web_login_refresh_failed');
      return;
    }

    _saveCredentials(ltp0: ltp0, did: did);
    _completed = true;
    _pollTimer?.cancel();
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
    infoMessageKey.value = '';
    errorMessageKey.value = messageKey;
  }

  void _showInfo(String messageKey) {
    errorMessageKey.value = '';
    infoMessageKey.value = messageKey;
  }

  bool _isCurrent(int revision) => !_closed && revision == _revision;

  @override
  void onClose() {
    _closed = true;
    _revision++;
    _pollTimer?.cancel();
    _pollTimer = null;
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
