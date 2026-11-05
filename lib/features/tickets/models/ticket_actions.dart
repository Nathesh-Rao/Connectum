import '../../../data/models/ticket.dart';

/// What [user] may do with a ticket, worked out from the data. The server
/// stays the judge: it can still refuse, and its text is shown.
class TicketActions {
  TicketActions._();

  /// The actions to offer. [isAdmin] and [inPool] are known only once
  /// `status.get` has answered; until then admin-only actions stay hidden.
  static List<TicketAction> of(
    Ticket ticket,
    String user, {
    bool isAdmin = false,
    bool? inPool,
  }) {
    final table = ticket.table;
    if (table == null || ticket.isAwaitingApproval || ticket.isFinal) {
      return const [];
    }
    return [
      for (final a in table.actions)
        if (_isWho(a, ticket, user, isAdmin, inPool) && _isFrom(a, ticket)) a,
    ];
  }

  static bool _isFrom(TicketAction a, Ticket ticket) =>
      a.from.isEmpty ? !ticket.isFinal : a.from.contains(ticket.status);

  static bool _isWho(
    TicketAction a,
    Ticket ticket,
    String user,
    bool isAdmin,
    bool? inPool,
  ) {
    for (final who in a.who) {
      final isMatch = switch (who) {
        'assignee' => ticket.isWith(user),
        'raiser' => ticket.isRaisedBy(user),
        'admin' => isAdmin,
        'pool' => mayTakeFromPool(ticket, inPool),
        _ => false,
      };
      if (isMatch) return true;
    }
    return false;
  }

  /// ASSUMPTION: the list never says who is in the group a ticket waits for,
  /// so an action for the pool is offered when the ticket's pool field has a
  /// value. When `status.get` says (`inPool`), that answer wins. If the
  /// server refuses (forbidden), its text is shown and the ticket is read
  /// again.
  static bool mayTakeFromPool(Ticket ticket, bool? inPool) =>
      inPool ?? ticket.hasPool;

  /// Edit on the raiser's own ticket, only while its status is in
  /// `editableIn`.
  static bool canEdit(Ticket ticket, String user) {
    final table = ticket.table;
    return table != null &&
        !ticket.isAwaitingApproval &&
        ticket.isRaisedBy(user) &&
        table.editableIn.contains(ticket.status);
  }
}
