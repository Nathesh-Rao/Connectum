import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:connectum/core/theme/theme.dart';
import 'package:connectum/core/widgets/widgets.dart';
import 'package:connectum/features/inbox/inbox.dart';
import 'package:connectum/features/profile/profile.dart';
import 'person_profile_controller.dart';

class PersonProfileView extends GetView<PersonProfileController> {
  const PersonProfileView({super.key});

  static const avatarSize = 96.0;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final card = c.card;
    return AppScaffold(
      isScrollable: false,
      showOfflineBar: true,
      padding: EdgeInsets.zero,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xs,
              AppSpacing.sm,
              AppSpacing.md,
              AppSpacing.xs,
            ),
            child: Row(
              children: [
                AppButton.icon(
                  icon: Icons.arrow_back,
                  semanticLabel: 'Back',
                  onPressed: Get.back,
                ),
                const Expanded(child: Text('Profile', style: AppText.heading)),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.xs,
                AppSpacing.md,
                AppSpacing.md,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ClipRRect(
                    borderRadius: AppRadius.cardAll,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppColors.surfaceSubtle,
                        borderRadius: AppRadius.cardAll,
                        border: Border.all(color: AppColors.line),
                      ),
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: Obx(
                              () => InboxAvatarWash(picture: c.picture),
                            ),
                          ),
                          const Positioned.fill(
                            child: CardTopRightDecoration(),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(AppSpacing.md),
                            child: Obx(() {
                              final mood = c.mood;
                              final status = c.status;
                              return Column(
                                children: [
                                  SizedBox.square(
                                    dimension: avatarSize,
                                    child: Stack(
                                      clipBehavior: Clip.none,
                                      children: [
                                        InboxAvatarRing(
                                          name: card.displayName,
                                          picture: c.picture,
                                          dimension: avatarSize,
                                        ),
                                        if (mood != null)
                                          Positioned(
                                            right: 2,
                                            bottom: 2,
                                            child: DecoratedBox(
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                border: Border.all(
                                                  color: AppColors.white,
                                                  width: 2.5,
                                                ),
                                              ),
                                              child: PresenceDotView(
                                                presence: mood,
                                                size: 18,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: AppSpacing.sm),
                                  Text(
                                    card.displayName,
                                    maxLines: 2,
                                    textAlign: TextAlign.center,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppText.title,
                                  ),
                                  Text(
                                    '@${card.username}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppText.readable.copyWith(
                                      color: AppColors.muted,
                                    ),
                                  ),
                                  if (card.designation.isNotEmpty) ...[
                                    const SizedBox(height: AppSpacing.xs),
                                    DecoratedBox(
                                      decoration: BoxDecoration(
                                        color: AppColors.primaryTint,
                                        borderRadius: AppRadius.pillAll,
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: AppSpacing.sm,
                                          vertical: AppSpacing.xxs,
                                        ),
                                        child: Text(
                                          card.designation,
                                          maxLines: 2,
                                          textAlign: TextAlign.center,
                                          overflow: TextOverflow.ellipsis,
                                          style: AppText.readableStrong
                                              .copyWith(
                                                color: AppColors.primaryStrong,
                                              ),
                                        ),
                                      ),
                                    ),
                                  ],
                                  if (mood != null) ...[
                                    const SizedBox(height: AppSpacing.xs),
                                    PresencePill(presence: mood),
                                  ],
                                  if (status != null) ...[
                                    const SizedBox(height: AppSpacing.xs),
                                    Text(
                                      status,
                                      key: const ValueKey('person-status'),
                                      textAlign: TextAlign.center,
                                      style: AppText.readable,
                                    ),
                                  ],
                                ],
                              );
                            }),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (card.workplace.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.lg),
                    ProfileGroup(
                      title: 'WORK',
                      children: [
                        ProfileInfoRow(
                          label: 'Department',
                          value: card.workplace,
                        ),
                      ],
                    ),
                  ],
                  if (card.hasContact) ...[
                    const SizedBox(height: AppSpacing.lg),
                    ProfileGroup(
                      title: 'CONTACT',
                      children: [
                        if (card.email.isNotEmpty)
                          ProfileInfoRow(label: 'Email', value: card.email),
                        if (card.mobile.isNotEmpty)
                          ProfileInfoRow(label: 'Mobile', value: card.mobile),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.xs,
              AppSpacing.md,
              AppSpacing.md,
            ),
            child: Row(
              children: [
                Expanded(
                  child: AppButton.secondary(
                    label: 'Close',
                    onPressed: Get.back,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: AppButton.primary(
                    label: 'Message',
                    isCentered: true,
                    onPressed: c.message,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
