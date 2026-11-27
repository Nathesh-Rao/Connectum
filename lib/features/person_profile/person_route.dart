import 'package:get/get.dart';

import '../../core/routes/app_routes.dart';
import 'models/person_card.dart';

/// Opens someone's read-only profile. Nothing without a username.
class PersonRoute {
  PersonRoute._();

  static void open(PersonCard card) {
    if (card.username.isEmpty) return;
    Get.toNamed(AppRoutes.personOf(card.username), arguments: card);
  }
}
