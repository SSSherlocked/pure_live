import 'package:pure_live/core/index.dart';
import 'package:pure_live/core/network/douyu_utils.dart';
import 'package:pure_live/core/config/cookie_settings_controller.dart';
import 'package:pure_live/domains/account/data/bilibili_account_service.dart';

/// Where an account stands.
enum AccountState {
  /// No credential stored.
  signedOut,

  /// A working login.
  signedIn,

  /// Expired, but renews itself on the next request (Douyu with LTP0).
  renewing,

  /// A credential that no longer works and has to be replaced.
  needsAttention;

  bool get isSignedIn => this == signedIn || this == renewing;
}

/// The platforms with an account, in the order the account page lists them.
enum AccountPlatform {
  bilibili('bilibili', 'assets/images/bilibili_2.png'),
  huya('huya', 'assets/images/huya.png'),
  yy('yy', 'assets/images/yy.png'),
  bigo('bigo', 'assets/images/bigo.png'),
  douyin('douyin', 'assets/images/douyin.png'),
  kuaishou('kuaishou', 'assets/images/kuaishou.png'),
  twitch('twitch', 'assets/images/twitch.png'),
  soop('soop', 'assets/images/soop.png'),
  douyu('douyu', 'assets/images/douyu.png');

  const AccountPlatform(this.siteId, this.logo);

  final String siteId;
  final String logo;

  String get title => i18n('site_$siteId');
}

/// One platform's account status and what to say about it.
///
/// Every "is this platform signed in" decision is made here, once: the account
/// page shows it, and anything else that needs to know asks the same place
/// instead of testing a cookie's length (a stored Douyu cookie can be an
/// expired one). Reads observable settings, so an `Obx` around it follows
/// sign-ins and sign-outs.
@immutable
class AccountStatus {
  const AccountStatus(this.platform, this.state, this.detail);

  final AccountPlatform platform;
  final AccountState state;

  /// The tile's subtitle.
  final String detail;

  bool get isSignedIn => state.isSignedIn;

  static AccountStatus of(AccountPlatform platform, {String douyinNickName = ''}) {
    final cookies = CookieSettingsController.to;
    AccountStatus cookieStatus(RxString cookie, {String signedInDetail = ''}) {
      final signedIn = cookie.v.isNotEmpty;
      return AccountStatus(
        platform,
        signedIn ? AccountState.signedIn : AccountState.signedOut,
        signedIn ? (signedInDetail.isNotEmpty ? signedInDetail : i18n('logined')) : i18n('set_cookie'),
      );
    }

    return switch (platform) {
      AccountPlatform.bilibili => _bilibili(),
      AccountPlatform.huya => cookieStatus(cookies.huyaCookie),
      AccountPlatform.yy => cookieStatus(cookies.yyCookie),
      AccountPlatform.bigo => cookieStatus(cookies.bigoCookie),
      AccountPlatform.douyin => cookieStatus(cookies.douyinCookie, signedInDetail: douyinNickName),
      AccountPlatform.kuaishou => cookieStatus(cookies.kuaishouCookie),
      AccountPlatform.twitch => cookieStatus(cookies.twitchCookie),
      AccountPlatform.soop => cookieStatus(cookies.soopCookie),
      AccountPlatform.douyu => _douyu(cookies),
    };
  }

  static AccountStatus _bilibili() {
    final service = BiliBiliAccountService.instance;
    if (!service.logined.v) {
      return AccountStatus(AccountPlatform.bilibili, AccountState.signedOut, i18n('not_logged_in'));
    }
    final name = service.name.v.trim();
    return AccountStatus(
      AccountPlatform.bilibili,
      AccountState.signedIn,
      name.isEmpty ? i18n('account_verifying') : name,
    );
  }

  /// A stored Douyu cookie is not the same as a working login: an expired one
  /// is a guest request whatever its length. One with its renewal key renews on
  /// its own and still counts as signed in.
  static AccountStatus _douyu(CookieSettingsController cookies) {
    return switch (DouyuUtils.sessionState(cookies.douyuCookie.v)) {
      DouyuSessionState.none => AccountStatus(AccountPlatform.douyu, AccountState.signedOut, i18n('set_cookie')),
      DouyuSessionState.valid => AccountStatus(
        AccountPlatform.douyu,
        AccountState.signedIn,
        i18n('cookie_saved_local'),
      ),
      DouyuSessionState.expiredRefreshable => AccountStatus(
        AccountPlatform.douyu,
        AccountState.renewing,
        i18n('douyu_session_renewable'),
      ),
      DouyuSessionState.guest || DouyuSessionState.expired => AccountStatus(
        AccountPlatform.douyu,
        AccountState.needsAttention,
        i18n('douyu_session_needs_cookie'),
      ),
    };
  }
}
