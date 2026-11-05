import '../../../data/models/ticket.dart';

/// Keeps the Tickets lists right when a page, an event or an answer arrives.
/// Pure.
class TicketReducer {
  TicketReducer._();

  /// The server's order is kept; a read page replaces what is shown. Rows
  /// already shown that the page no longer lists are returned in [gone] so
  /// the screen can slide them out.
  static ({List<Ticket> next, List<Ticket> gone}) refreshed(
    List<Ticket> fresh,
    List<Ticket> shown,
  ) {
    final ids = {for (final t in fresh) t.id};
    return (
      next: fresh,
      gone: [
        for (final t in shown)
          if (!ids.contains(t.id)) t,
      ],
    );
  }

  /// The next page after the rows already shown.
  static List<Ticket> appended(List<Ticket> shown, List<Ticket> page) {
    final ids = {for (final t in shown) t.id};
    return [
      ...shown,
      for (final t in page)
        if (!ids.contains(t.id)) t,
    ];
  }

  static List<Ticket> remove(List<Ticket> list, int id) => [
    for (final t in list)
      if (t.id != id) t,
  ];

  /// A ticket I changed: replaced in place where it is shown.
  static List<Ticket> replace(List<Ticket> list, Ticket ticket) => [
    for (final t in list) t.id == ticket.id ? ticket : t,
  ];

  /// After an update, does the ticket still belong in [as]: `with` = with
  /// [user] now and not final; `raised` = raised by [user] and not final.
  static bool belongsIn(Ticket t, String as, String user) {
    if (t.isFinal) return false;
    return as == 'with'
        ? t.isWith(user) && !t.isAwaitingApproval
        : t.isRaisedBy(user);
  }

  /// The tabs' lists after my own update answered: the ticket is replaced
  /// where it stays and leaves where it no longer belongs ([gone]).
  static ({List<Ticket> next, bool isGone}) afterUpdate(
    List<Ticket> list,
    Ticket ticket, {
    required String as,
    required String user,
  }) {
    if (!list.any((t) => t.id == ticket.id)) {
      return (next: list, isGone: false);
    }
    if (!belongsIn(ticket, as, user)) {
      return (next: list, isGone: true);
    }
    return (next: replace(list, ticket), isGone: false);
  }
}

/// What a live event asks to be read again. `ticket_assigned` can move any
/// ticket (it also says nothing of what changed in the row), so the lists are
/// read again, and the open ticket too when it is the one named.
class TicketRefreshPlan {
  const TicketRefreshPlan({required this.lists, required this.openTicket});

  final bool lists;
  final bool openTicket;

  static TicketRefreshPlan of(TicketAssigned? event, {int? openId}) =>
      TicketRefreshPlan(
        lists: true,
        openTicket: event == null || (openId != null && event.id == openId),
      );
}
