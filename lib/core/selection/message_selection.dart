import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

/// Which messages of one thread are selected (long press, then taps). One
/// instance per conversation and one for My Work Space; ids are message ids,
/// so the selection survives new messages and rebuilds.
class MessageSelection {
  /// The selected ids, in the order they were picked.
  final ids = <String>[].obs;

  /// The reaction bar is hidden by a scroll; the selection stays.
  final isBarHidden = false.obs;

  final _anchors = <String, GlobalKey>{};

  bool get isActive => ids.isNotEmpty;
  bool get isSingle => ids.length == 1;
  String? get only => isSingle ? ids.first : null;
  bool isSelected(String id) => ids.contains(id);

  /// The key of a row, so the reaction bar can find where it is.
  GlobalKey anchorOf(String id) => _anchors.putIfAbsent(id, GlobalKey.new);

  /// A long press selects (and adds while selecting).
  void onLongPress(String id) {
    HapticFeedback.mediumImpact();
    if (!isSelected(id)) ids.add(id);
    isBarHidden.value = false;
  }

  /// A tap while selecting adds the message, or removes it when it was
  /// selected. Removing the last one leaves selection.
  void onTap(String id) {
    if (!ids.remove(id)) ids.add(id);
    isBarHidden.value = false;
  }

  void clear() {
    if (ids.isEmpty) return;
    ids.clear();
    isBarHidden.value = false;
  }

  /// Drops ids that are no longer in the thread (deleted, or a temp id that
  /// the server replaced).
  void prune(Set<String> present) {
    if (ids.isEmpty) return;
    ids.removeWhere((id) => !present.contains(id));
  }

  void hideBar() {
    if (isActive) isBarHidden.value = true;
  }
}
