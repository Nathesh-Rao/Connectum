/// The words of the Profile screens.
class ProfileTexts {
  ProfileTexts._();

  static const addStatus = 'Add a status';
  static const statusHint = "What's on your mind?";
  static const noStatus = 'No status message';
  static const discardTitle = 'Discard your changes?';
  static const discardBody =
      'What you changed in your profile has not been saved.';
  static const discard = 'Discard';
  static const keepEditing = 'Keep editing';

  static const offline =
      "You're offline. Connect and save again; your changes are kept.";
  static const statusSaved = 'Status updated';
  static const timeout =
      "The server didn't answer. Try again; your changes are kept.";
  static const saveFailed =
      "Couldn't save your status. Try again; your changes are kept.";

  /// What a refused status or presence command says.
  static String commandError(String code) => switch (code) {
    'invalid_status' =>
      "That status is too long or has characters that aren't allowed (up to 140).",
    'invalid_presence' =>
      "That presence isn't valid. Pick one of the five options.",
    'rate_limited' =>
      "You're sending too fast. Wait a few seconds and try again.",
    'offline' => offline,
    'timeout' => timeout,
    _ => saveFailed,
  };

  static const detailsTitle = 'Personal details';
  static const detailsPrivate =
      'Personal details are private to you and organization administrators.';
  static const detailsSaved = 'Personal details saved';
  static const detailsLoadFailed = "Couldn't load your details.";
  static const detailsSaveFailed =
      "Couldn't save your details. Try again; your changes are kept.";
  static const detailsNothing = 'Nothing has changed.';
}
