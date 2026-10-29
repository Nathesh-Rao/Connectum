import 'ids.dart';

/// One entry of `options.list`: something the person may run from the forms
/// button. Only `data_input` options are forms; the others are listed but
/// unavailable on mobile.
class FormOption {
  const FormOption({
    required this.id,
    required this.caption,
    required this.type,
    required this.target,
    required this.targetScope,
    required this.category,
    required this.order,
  });

  static const formType = 'data_input';

  final String id;
  final String caption;
  final String type;
  final String target;

  /// `user` for a form a person made, `admin` for an admin-managed one.
  final String targetScope;
  final String category;
  final int order;

  bool get isForm => type == formType && target.isNotEmpty;

  factory FormOption.fromMap(Map data) {
    final target = idText(data['target']);
    final caption = idText(data['caption']);
    return FormOption(
      id: idText(data['id']),
      caption: caption.isEmpty ? target : caption,
      type: idText(data['type']),
      target: target,
      targetScope: idText(data['targetScope']),
      category: idText(data['category']),
      order: intOf(data['order']),
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'caption': caption,
    'type': type,
    'target': target,
    'targetScope': targetScope,
    'category': category,
    'order': order,
  };
}

/// The icon and wiring of a category, from `options.categories`.
class FormCategory {
  const FormCategory({
    required this.id,
    required this.label,
    required this.icon,
    required this.isExecutable,
  });

  final String id;
  final String label;
  final String icon;
  final bool isExecutable;

  factory FormCategory.fromMap(Map data) => FormCategory(
    id: idText(data['id']),
    label: idText(data['label']),
    icon: idText(data['icon']),
    isExecutable: data['executable'] != false,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'label': label,
    'icon': icon,
    'executable': isExecutable,
  };
}

/// A form used lately, kept per organisation and user.
class FormRecent {
  const FormRecent({
    required this.name,
    required this.scope,
    required this.caption,
  });

  final String name;
  final String scope;
  final String caption;
}

/// One choice of a list field: the stored value and the text shown.
class FormChoice {
  const FormChoice(this.value, this.label);

  final String value;
  final String label;
}
