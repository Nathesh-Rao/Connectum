/// What the in-app browser opens: the address and the name to show until the
/// page gives its own title.
class LinkBrowserArgs {
  const LinkBrowserArgs({required this.url, this.title = ''});

  final String url;
  final String title;
}
