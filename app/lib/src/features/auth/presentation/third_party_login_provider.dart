import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/third_party_login_store.dart';

final showThirdPartyLoginProvider =
    StateNotifierProvider<ShowThirdPartyLoginNotifier, bool>((ref) {
  return ShowThirdPartyLoginNotifier();
});

class ShowThirdPartyLoginNotifier extends StateNotifier<bool> {
  ShowThirdPartyLoginNotifier() : super(ThirdPartyLoginStore.showThirdPartyLogin);

  Future<void> setEnabled(bool show) async {
    await ThirdPartyLoginStore.setShowThirdPartyLogin(show);
    state = show;
  }
}
