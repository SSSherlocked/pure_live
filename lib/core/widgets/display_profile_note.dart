import 'package:pure_live/core/index.dart';

/// One line under a settings group whose values are kept per
/// [DisplayProfile]: which profile the page edits right now. Settings only
/// ever edit the current one; the other two change when the app runs in
/// their layout.
class DisplayProfileNote extends StatelessWidget {
  const DisplayProfileNote({super.key, required this.profile, this.padding = EdgeInsets.zero, this.color});

  /// The profile the edited settings hold.
  final Rx<DisplayProfile> profile;
  final EdgeInsetsGeometry padding;

  /// Text colour; the theme's outline colour when null.
  final Color? color;

  static String label(DisplayProfile profile) => switch (profile) {
    DisplayProfile.phone => i18n('display_profile_editing_phone'),
    DisplayProfile.tablet => i18n('display_profile_editing_tablet'),
    DisplayProfile.desktop => i18n('display_profile_editing_desktop'),
  };

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => Padding(
        padding: padding,
        child: Text(
          label(profile.value),
          key: ValueKey('display-profile-note-${profile.value.name}'),
          style: AppText.of(context).secondary.copyWith(color: color ?? Theme.of(context).colorScheme.outline),
        ),
      ),
    );
  }
}
