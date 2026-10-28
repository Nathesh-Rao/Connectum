import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/theme/app_text.dart';
import '../../core/widgets/app_scaffold.dart';
import 'profile_controller.dart';

class ProfileView extends GetView<ProfileController> {
  const ProfileView({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      body: Center(child: Text('Profile', style: AppText.title)),
    );
  }
}
