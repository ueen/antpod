import 'package:flutter/widgets.dart';

/// The app's binding: [WidgetsFlutterBinding], but a pointer can be kept
/// down through a navigation. A push cancels every pointer that's down
/// (Navigator._cancelActivePointers), so without this the drag that opens
/// the player sheet would let go of it the moment it's pushed.
class AppBinding extends WidgetsFlutterBinding {
  int? _kept;

  /// Runs [navigate] with [pointer] kept down through it. Without this
  /// binding (tests), the pointer is cancelled as usual.
  static T keepPointer<T>(int? pointer, T Function() navigate) {
    final binding = WidgetsBinding.instance;
    if (pointer == null || binding is! AppBinding) return navigate();
    binding._kept = pointer;
    try {
      return navigate();
    } finally {
      binding._kept = null;
    }
  }

  @override
  void cancelPointer(int pointer) {
    if (pointer == _kept) return;
    super.cancelPointer(pointer);
  }
}
