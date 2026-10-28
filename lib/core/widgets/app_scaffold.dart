import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import 'app_offline_bar.dart';

class AppScaffold extends StatelessWidget {
  const AppScaffold({
    super.key,
    required this.body,
    this.bottomBar,
    this.bottomBarColor = AppColors.background,
    this.padding = const EdgeInsets.symmetric(horizontal: AppSpacing.page),
    this.backgroundColor = AppColors.background,
    this.hasDarkBackground = false,
    this.showOfflineBar = false,
    this.isScrollable = true,
  });

  final Widget body;
  final Widget? bottomBar;
  final Color bottomBarColor;
  final EdgeInsetsGeometry padding;
  final Color backgroundColor;
  final bool hasDarkBackground;
  final bool showOfflineBar;

  /// False for a body that holds its own scrollable (a page view): it then
  /// gets the viewport height, because an intrinsic height can't be measured.
  final bool isScrollable;

  @override
  Widget build(BuildContext context) {
    final iconBrightness = hasDarkBackground
        ? Brightness.light
        : Brightness.dark;
    final overlay = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: iconBrightness,
      statusBarBrightness: hasDarkBackground
          ? Brightness.dark
          : Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarIconBrightness: iconBrightness,
      systemNavigationBarContrastEnforced: false,
    );
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay,
      child: Scaffold(
        backgroundColor: backgroundColor,
        resizeToAvoidBottomInset: true,
        body: Column(
          children: [
            Expanded(
              child: SafeArea(
                bottom: bottomBar == null,
                child: Column(
                  children: [
                    if (showOfflineBar) const AppOfflineBar(),
                    Expanded(
                      child: isScrollable
                          ? _PackedScroll(padding: padding, body: body)
                          : Padding(padding: padding, child: body),
                    ),
                  ],
                ),
              ),
            ),
            if (bottomBar != null)
              ColoredBox(
                color: bottomBarColor,
                child: Padding(
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.paddingOf(context).bottom,
                  ),
                  child: bottomBar,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PackedScroll extends StatelessWidget {
  const _PackedScroll({required this.padding, required this.body});

  final EdgeInsetsGeometry padding;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final vertical = padding.resolve(Directionality.of(context)).vertical;
        return SingleChildScrollView(
          padding: padding,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: constraints.maxHeight - vertical,
            ),
            child: IntrinsicHeight(child: body),
          ),
        );
      },
    );
  }
}
