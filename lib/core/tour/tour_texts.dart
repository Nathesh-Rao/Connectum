/// Every word of the tours.
class TourTexts {
  TourTexts._();

  static const next = 'Next';
  static const done = 'Got it';
  static const skip = 'Skip';
  static const nextLabel = 'Next tip';
  static const doneLabel = 'Finish the tour';
  static const skipLabel = 'Skip the tour';

  static String announce(String title, String body, int index, int total) =>
      'Tip ${index + 1} of $total. $title. $body';

  static String progress(int index, int total) => 'Tip ${index + 1} of $total';

  static const tourStarted = 'A short tour of this screen has started.';

  // The intro before the very first tour.
  static const introTitle = 'A quick tour, with sample data';
  static const introBody =
      "While we show you around, some of what you see will be sample data, made up just for the tour. It's marked 'Sample', nothing is saved or sent, and it all disappears when the tour ends.";
  static const introStart = 'Show me around';
  static const introStartLabel = 'Show me around: start the tour';
  static const introSkip = 'Skip tours';
  static const introSkipLabel = 'Skip tours: do not show the tours';

  // App tour section of the Profile.
  static const sectionTitle = 'APP TOUR';
  static const replayTitle = 'Replay all tours';
  static const replaySubtitle = 'Show the first-run tips again';
  static const replayDone =
      'The tours will play again as you visit each screen.';

  // Chat list.
  static const chatSwitcherTitle = 'Your enterprise';
  static const chatSwitcherBody =
      'This is the enterprise you are working in. Tap it to switch to another one.';
  static const chatActionsTitle = 'Notifications and profile';
  static const chatActionsBody =
      'The bell shows your unread notifications. Tap your picture to open your profile.';
  static const chatWorkspaceTitle = 'My Work Space';
  static const chatWorkspaceBody =
      'Your own private space, pinned above your chats. Notes to yourself, the forms you sent and the records sent to you are kept here.';
  static const chatSearchTitle = 'Search your chats';
  static const chatSearchBody =
      'Find a chat by its name, or a message saved on this phone. It works offline too.';
  static const chatNewTitle = 'Start a conversation';
  static const chatNewBody =
      'Tap here to start a chat or a group and connect with colleagues.';
  static const chatTabsTitle = 'Move around';

  static String chatTabsBody(List<String> names) {
    if (names.length < 2) return 'Use the bar at the bottom to move around.';
    final head = names.sublist(0, names.length - 1).join(', ');
    return 'Switch between $head and ${names.last} down here.';
  }

  static const chatRowTitle = 'Your chats';
  static const chatRowBody = 'Long-press a chat for more options.';

  // First chat. Every sentence is true for the chat it is shown in: the
  // pieces depend on what that chat allows.
  static const chatInfoTitle = 'Chat info';
  static const chatInfoBody = 'Tap the name to open this chat\'s info.';
  static const chatInfoLockedBody =
      'Tap the name to open this chat\'s info. The lock means messages here are end-to-end encrypted.';

  static const chatComposerTitle = 'Write here';
  static String chatComposerBody({required bool canAttach}) => canAttach
      ? 'Type your message here. The buttons beside it attach a photo or document, and open your forms.'
      : 'Type your message here. The button beside it opens your forms.';

  static const chatHashTitle = 'Shortcuts';
  static const chatHashBody =
      'Type # to see shortcuts, like opening your Inbox.';

  static const chatHoldTitle = 'Press and hold';
  static String chatHoldBody({required bool canReact}) => canReact
      ? 'Press and hold a message to select it. Quick reactions show above it.'
      : 'Press and hold a message to select it.';

  static const chatOptionsTitle = 'Message options';

  /// [bar] are the icons on the bar, [more] the ones under More, both named
  /// from what the selected message really allows.
  static String optionsBody(
    List<String> bar,
    List<String> more, {
    String? note,
  }) {
    final parts = <String>[
      if (bar.isNotEmpty) 'The bar shows ${_list(bar)}.',
      if (more.isNotEmpty) 'More has ${_list(more)}.',
      ?note,
    ];
    return parts.isEmpty ? 'Tap the arrow to leave.' : parts.join(' ');
  }

  static const editWindowNote = 'You can edit your own message for 15 minutes.';

  static String _list(List<String> names) => names.length < 2
      ? names.join()
      : '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}';

  static const chatSwipeTitle = 'Swipe to reply';
  static const chatSwipeBody = 'Swipe a message to the right to reply to it.';

  // Sample messages of the tours, shown with a "Sample" tag.
  static const sampleTag = 'Sample';
  static const sampleSender = 'Maya';
  static const sampleWelcome =
      'Welcome to Connectum! Messages you send and receive show up like this.';
  static const sampleReply = 'Thanks, glad to be here.';
  static const sampleNote = 'Call the supplier about Friday\'s delivery.';

  // My Work Space.
  static const wsHeaderTitle = 'Your Work Space';
  static const wsHeaderBody =
      'Notes to yourself, forms you submitted and records sent to you. Saved notes, tasks and approvals are up here.';
  static const wsComposerTitle = 'Write a note';
  static const wsComposerBody =
      'Notes are kept on your account and show on your other devices. You can write one offline; it is sent when you are back online.';
  static const wsHoldTitle = 'Press and hold a note';
  static const wsHoldBody =
      'Press and hold a note to select it. The bar on top shows what you can do with it.';
  static const wsOptionsTitle = 'Note options';
  static const wsEditNote = 'A note can be edited at any time.';
  static const wsSwipeTitle = 'Swipe to reply';
  static const wsSwipeBody = 'Swipe a note to the right to reply to it.';

  // The # shortcuts panel.
  static const cmdPanelTitle = 'Your shortcuts';
  static const cmdPanelBody =
      'These # commands open screens and do jobs without leaving the chat.';
  static const cmdInboxTitle = 'Try #inbox';
  static const cmdInboxBody = '#inbox opens your Inbox.';
  static const cmdViewTitle = 'Try #view';
  static const cmdViewBody =
      '#view opens Smart view. Type a form\'s name after it to go straight to that one.';
  static const cmdRunTitle = 'Run one';
  static const cmdRunBody =
      'Tap a shortcut to put it in the message box, then press send. Nothing runs until you send.';

  // Smart view.
  static const svViewsTitle = 'Your smart views';
  static String svViewsBody({required bool isSample}) => isSample
      ? 'The menu lists the views you can open, and Find looks one up. You have no views yet, so this one is a sample.'
      : 'The menu lists the views you can open, and Find looks one up. Pick one to see its records.';
  static const svCardsTitle = 'Records as cards';
  static String svCardsBody({required bool isSample, required bool hasFiles}) {
    final base = isSample
        ? 'Each record of a view is a card. These are sample records.'
        : 'Each record of the view is a card.';
    return hasFiles
        ? '$base A file on a card is a chip: tap it to preview it.'
        : base;
  }

  static const svModeTitle = 'Cards or Table';
  static const svModeBody =
      'Switch between cards and a table of the same records. Your choice is kept.';
  static const svSearchTitle = 'Search';
  static const svSearchBody =
      'Search looks inside the records of this view. You can limit it to one field.';
  static const svFilterTitle = 'Filter and Sort';
  static const svFilterBody =
      'Filter narrows the records by field and opens as a sheet; nothing changes until you apply it. Sort changes their order.';
  static const svActionsTitle = 'The Actions button';
  static const svActionsBody =
      'The round grid button opens Actions: Add record where the view allows it, KPI and Charts.';
  static const svExpandTitle = 'Open a card';
  static const svExpandBody =
      'Show all lists every field of the record and all of its files. Tap the card itself to open the record.';
  static const svSampleViewCaption = 'Sample requests';

  // Inbox.
  static const inboxCardsTitle = 'Your records';
  static String inboxCardsBody({required bool isSample}) => isSample
      ? 'Forms you send and records sent to you show up as cards, with a coloured status. These are sample cards.'
      : 'Forms you send and records sent to you show up as cards, with a coloured status.';
  static const inboxExpandTitle = 'Open a card';
  static const inboxExpandBody =
      'Show more lists every answer and the files on the record. Tap the card itself to open the record and its history.';
  static const inboxViewsTitle = 'Saved views';
  static const inboxViewsBody =
      'This is the view you have open. Tap it to switch views, or to save your filters as a view you can come back to.';
  static const inboxSearchTitle = 'Search and filter';
  static const inboxSearchBody =
      'Search looks through your records. The filter button narrows and sorts them, and opens as a popup; nothing changes until you apply it.';
  static const inboxTabsTitle = 'Records and Approvals';
  static String inboxTabsBody({required int pending}) {
    const base =
        'Records are the forms you sent and the ones sent to you. Approvals are requests waiting for your answer. Swipe sideways or tap to switch.';
    return pending > 0
        ? '$base $pending waiting for you now.'
        : '$base Requests that need your answer show up in Approvals.';
  }

  static const inboxFilterBarTitle = 'Filter the approvals';
  static const inboxFilterBarBody =
      'The filter button at the top chooses which requests show. The chips under the tabs say what is on; tap the cross on one to take it off.';
  static const inboxApprovalsTitle = 'Answer a request';
  static String inboxApprovalsBody({required bool isSample}) => isSample
      ? 'A request waiting for you has Approve and Decline. A form can also be Returned. These are sample requests.'
      : 'A request waiting for you has Approve and Decline. A form can also be Returned.';
  static const inboxSampleName = 'Maya Rao';

  // Notifications.
  static const ntPillsTitle = 'Filter by priority';
  static const ntPillsBody =
      'Updates from your account show up here. Tap High, Medium, Low or Resolved to see just those; All shows everything.';
  static const ntTapTitle = 'Tap to open';
  static const ntTapBody =
      'Tap a notification to open what it is about. It is marked read when you do.';
  static const ntTapEmptyBody =
      'New notifications show up here. Tap one to open what it is about.';
  static const ntSwipeTitle = 'Swipe to dismiss';
  static const ntSwipeBody = 'Swipe a notification to the left to dismiss it.';
  static const ntMoreTitle = 'More options';
  static const ntMoreBody =
      'Show unread only, mark everything read or resolved, or clear the ones already resolved.';

  // Profile.
  static const prIdentityTitle = 'Your profile';
  static const prIdentityBody =
      'Your name, username and enterprise are here. Tap your picture to take a photo or choose one from your gallery.';
  static const prSecurityTitle = 'Security';
  static const prSecurityBody =
      'See the devices that can read your encrypted messages, and remove one you no longer use.';
  static const prSwitchTitle = 'Switch enterprise';
  static const prSwitchBody =
      'If you belong to more than one enterprise, switch between them from here.';
  static const prReplayTitle = 'See the tours again';
  static const prReplayBody =
      'Tap Replay all tours any time to see these tips again as you visit each screen.';
}
