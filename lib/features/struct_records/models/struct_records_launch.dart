/// What `#tstruct <name>` hands to the records screen: the structure the
/// server opened, and where the command was typed, so New record opens the
/// add form exactly as `#tstruct-add <name>` does there.
class StructRecordsLaunch {
  const StructRecordsLaunch({
    required this.name,
    required this.scope,
    required this.caption,
    this.convId,
  });

  final String name;
  final String scope;
  final String caption;
  final String? convId;
}
