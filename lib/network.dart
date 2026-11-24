// lib/network.dart
//
// One reading of connectivity_plus results for the whole app, so the offline
// marks, pull-to-refresh and the download queue always agree.

import 'package:connectivity_plus/connectivity_plus.dart';

extension ConnectivityX on List<ConnectivityResult> {
  /// Nothing that reaches the internet (Bluetooth alone doesn't).
  bool get isOffline => every(
      (r) => r == ConnectivityResult.none || r == ConnectivityResult.bluetooth);

  /// Wi-Fi or ethernet: fine for downloads.
  bool get isUnmetered =>
      contains(ConnectivityResult.wifi) || contains(ConnectivityResult.ethernet);
}
