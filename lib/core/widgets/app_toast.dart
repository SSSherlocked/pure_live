import 'package:flutter/material.dart';
import 'package:pure_live/core/theme/app_text.dart';
import 'package:pure_live/core/config/settings_service.dart';
import 'package:pure_live/core/storage/hive_rx.dart';

/// The toast every ToastUtil message shows in.
///
/// SmartDialog draws toasts in its own overlay, outside AppShell, so its stock
/// toast kept a fixed size: neither 字体设置's sizes nor the text scale reached
/// it. This one is the stock look (a dark pill, white text) in the app's body
/// role at the app's text scale.
class AppToast extends StatelessWidget {
  const AppToast(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(SettingsService.to.font.textScaleFactor.v),
      ),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 30, vertical: 50),
        padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 10),
        decoration: BoxDecoration(
          color: dark ? const Color(0xFF606060) : Colors.black,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(message, style: AppText.of(context).body.copyWith(color: Colors.white)),
      ),
    );
  }
}
