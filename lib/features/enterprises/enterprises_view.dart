import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/theme/app_text.dart';
import '../../core/widgets/app_scaffold.dart';
import 'enterprises_controller.dart';

class EnterprisesView extends GetView<EnterprisesController> {
  const EnterprisesView({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      body: Center(child: Text('Enterprises', style: AppText.title)),
    );
  }
}
