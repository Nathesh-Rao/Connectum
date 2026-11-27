/// Everything a message can do from the selection bar. The order of
/// [SelectionRules.iconOrder] is the order of the icons.
enum SelectionAction {
  retry,
  reply,
  star,
  delete,
  forward,
  copy,
  pin,
  edit,
  formMenu,
}

/// What one selected message allows, decided by its controller with the same
/// conditions the old long-press sheet had.
class SelectionTarget {
  const SelectionTarget({
    required this.id,
    this.canReply = false,
    this.canStar = false,
    this.canDelete = false,
    this.canForward = false,
    this.canCopy = false,
    this.canPin = false,
    this.canEdit = false,
    this.canRetry = false,
    this.canReact = false,
    this.hasFormMenu = false,
  });

  final String id;
  final bool canReply;
  final bool canStar;
  final bool canDelete;
  final bool canForward;
  final bool canCopy;
  final bool canPin;
  final bool canEdit;
  final bool canRetry;
  final bool canReact;
  final bool hasFormMenu;
}

/// Which actions apply to a selection, and how many fit as icons. Pure, so it
/// is tested without a screen.
class SelectionRules {
  SelectionRules._();

  /// Icons first, in this order; the rest always sit in the overflow menu.
  static const iconOrder = [
    SelectionAction.retry,
    SelectionAction.reply,
    SelectionAction.star,
    SelectionAction.delete,
    SelectionAction.forward,
  ];

  /// Chats put Edit among the icons, right after Reply (`isEditIcon` of
  /// [available] and [split]); notes keep it in the menu.
  static const iconOrderWithEdit = [
    SelectionAction.retry,
    SelectionAction.reply,
    SelectionAction.edit,
    SelectionAction.star,
    SelectionAction.delete,
    SelectionAction.forward,
  ];

  static const overflowOrder = [
    SelectionAction.copy,
    SelectionAction.pin,
    SelectionAction.edit,
    SelectionAction.formMenu,
  ];

  /// Reply, edit, pin, retry and the form menu are for exactly one message;
  /// the others need every selected message to allow them.
  static List<SelectionAction> available(
    List<SelectionTarget> targets, {
    bool isEditIcon = false,
  }) {
    if (targets.isEmpty) return const [];
    final isOne = targets.length == 1;
    final first = targets.first;
    bool all(bool Function(SelectionTarget t) test) => targets.every(test);
    final allowed = <SelectionAction, bool>{
      SelectionAction.retry: isOne && first.canRetry,
      SelectionAction.reply: isOne && first.canReply,
      SelectionAction.star: all((t) => t.canStar),
      SelectionAction.delete: all((t) => t.canDelete),
      SelectionAction.forward: all((t) => t.canForward),
      SelectionAction.copy: all((t) => t.canCopy),
      SelectionAction.pin: isOne && first.canPin,
      SelectionAction.edit: isOne && first.canEdit,
      SelectionAction.formMenu: isOne && first.hasFormMenu,
    };
    final order = isEditIcon
        ? [
            ...iconOrderWithEdit,
            ...overflowOrder.where((a) => a != SelectionAction.edit),
          ]
        : [...iconOrder, ...overflowOrder];
    return [
      for (final a in order)
        if (allowed[a] ?? false) a,
    ];
  }

  /// The quick reactions are for one message that takes them.
  static bool showsReactions(
    List<SelectionTarget> targets, {
    required bool isSupported,
  }) => isSupported && targets.length == 1 && targets.first.canReact;

  /// At most four icons on a narrow screen (320 px), five otherwise.
  static int maxIcons(double width) => width < 360 ? 4 : 5;

  /// The icons that fit, and what goes into the overflow menu (the icons that
  /// did not fit first, then the overflow-only actions).
  static ({List<SelectionAction> icons, List<SelectionAction> overflow}) split(
    List<SelectionAction> actions,
    double width, {
    bool isEditIcon = false,
  }) {
    final icons = <SelectionAction>[];
    final overflow = <SelectionAction>[];
    final limit = maxIcons(width);
    final iconKinds = isEditIcon ? iconOrderWithEdit : iconOrder;
    for (final a in actions) {
      if (iconKinds.contains(a) && icons.length < limit) {
        icons.add(a);
      } else {
        overflow.add(a);
      }
    }
    return (icons: icons, overflow: overflow);
  }
}
