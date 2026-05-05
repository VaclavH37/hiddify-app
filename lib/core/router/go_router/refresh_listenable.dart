import 'package:flutter/material.dart';
import 'package:hiddify/core/router/deep_linking/my_app_links.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

// For temporary storage of the link received from AppLinks.
String newUrlFromAppLink = '';

class RefreshListenable extends ChangeNotifier {
  RefreshListenable(this.ref) {
    ref.listen(myAppLinksProvider, (_, next) {
      if (next.value != null) {
        newUrlFromAppLink = next.value!;
        notifyListeners();
      }
    });
    // Auth-gate transitions: when the profile-count crosses zero ↔ one the
    // redirect needs to bounce between /auth and /home.
    ref.listen(hasAnyProfileProvider, (_, _) => notifyListeners());
  }
  final Ref ref;
}
