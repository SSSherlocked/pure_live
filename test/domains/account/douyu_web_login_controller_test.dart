import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/domains/account/presentation/account/douyu/douyu_web_login_controller.dart';

/// A sign-in counts only when the session, LTP0 and dy_did were all obtained
/// *and* one renewal with them succeeded; anything less must store nothing.
void main() {
  const site = <String, String>{'dy_auth': 'session-token', 'dy_did': 'site-did', 'acf_uid': '42'};
  const passport = <String, String>{'LTP0': 'long-term', 'dy_did': 'passport-did'};

  late List<({String cookie, String ltp0, String did})> renewals;
  late List<({String ltp0, String did})> saved;
  late int completions;

  DouyuWebLoginController build({
    Map<String, String> siteCookies = site,
    Map<String, String> passportCookies = passport,
    String? renewedCookie = 'dy_auth=renewed',
  }) {
    return DouyuWebLoginController(
      cookieLoader: (WebUri uri) async =>
          uri.host == douyuPassportCookieUri.host ? passportCookies : siteCookies,
      renewer: ({required String cookie, required String ltp0, required String did}) async {
        renewals.add((cookie: cookie, ltp0: ltp0, did: did));
        return renewedCookie;
      },
      saveCredentials: ({required String ltp0, required String did}) => saved.add((ltp0: ltp0, did: did)),
      completeLogin: () => completions++,
      transitionDelay: Duration.zero,
    );
  }

  setUp(() {
    renewals = [];
    saved = [];
    completions = 0;
  });

  test('renews once with the passport pair, then saves and completes', () async {
    final controller = build();
    await controller.checkLogin();

    expect(renewals, hasLength(1));
    expect(renewals.single.ltp0, 'long-term');
    // The login's device is the passport's.
    expect(renewals.single.did, 'passport-did');
    expect(renewals.single.cookie, contains('dy_auth=session-token'));
    expect(saved.single, (ltp0: 'long-term', did: 'passport-did'));
    expect(completions, 1);
    expect(controller.showWebView.value, isFalse);
  });

  test('a failed renewal stores nothing, keeps the page open and stops automatic retries', () async {
    final controller = build(renewedCookie: null);
    await controller.checkLogin();

    expect(renewals, hasLength(1));
    expect(saved, isEmpty);
    expect(completions, 0);
    expect(controller.errorMessageKey.value, 'douyu_web_login_refresh_failed');
    expect(controller.showWebView.value, isTrue);

    // The poll does not keep asking Douyu; the viewer's own check does.
    await controller.checkLogin();
    expect(renewals, hasLength(1));
    await controller.checkNow();
    expect(renewals, hasLength(2));
  });

  test('a session without LTP0 is not a sign-in: the poll waits, an explicit check explains', () async {
    final controller = build(passportCookies: const {'dy_did': 'passport-did'});
    await controller.checkLogin();

    expect(renewals, isEmpty);
    expect(saved, isEmpty);
    expect(controller.errorMessageKey.value, isEmpty);
    expect(controller.infoMessageKey.value, 'douyu_web_login_waiting_ltp0');

    await controller.checkNow();
    expect(controller.errorMessageKey.value, 'douyu_web_login_no_ltp0');
    expect(controller.infoMessageKey.value, isEmpty);
  });

  test('LTP0 on the site cookie is used, but never sent as part of the session', () async {
    final controller = build(
      siteCookies: const {'dy_auth': 'session-token', 'dy_did': 'site-did', 'LTP0': 'from-site'},
      passportCookies: const {},
    );
    await controller.checkLogin();

    expect(renewals.single.ltp0, 'from-site');
    expect(renewals.single.did, 'site-did');
    expect(renewals.single.cookie, isNot(contains('LTP0')));
    expect(completions, 1);
  });

  test('before signing in, page loads stay quiet and an explicit check explains', () async {
    final controller = build(siteCookies: const {'dy_did': 'site-did'});
    await controller.checkLogin();
    expect(controller.errorMessageKey.value, isEmpty);
    expect(renewals, isEmpty);

    await controller.checkNow();
    expect(controller.errorMessageKey.value, 'douyu_web_login_no_session');
    expect(renewals, isEmpty);
  });
}
