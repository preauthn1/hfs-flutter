import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:modal_bottom_sheet/modal_bottom_sheet.dart' as mbs;
import 'package:responsive_framework/responsive_framework.dart';

import 'answer_sheet_painter.dart';
import 'hfs_client.dart';
import 'hfs_models.dart';

part 'widgets/auth_and_mini_scores_panel.dart';
part 'widgets/bind_student_advanced_dialog.dart';
part 'widgets/wrong_notebook_panel.dart';
part 'widgets/classmates_roster_dialog.dart';
part 'widgets/app_settings_dialog.dart';
part 'widgets/score_trend_analytics_card.dart';

/// Taste-Skill 2.5 Design System Tokens (Warm Neutral Surface + Single Teal Accent)
class Taste {
  static const String fontFamily = 'NotoSansSC';

  /// Unified responsive mobile detection via `ResponsiveBreakpoints` (with `MediaQuery` fallback).
  static bool isMobile(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    try {
      final bp = ResponsiveBreakpoints.of(context);
      if (bp.screenWidth > 0) {
        return bp.smallerThan(DESKTOP);
      }
    } catch (_) {}
    return width < 860;
  }

  /// Standardized dropdown popup width that expands to readable mobile width
  /// instead of being squeezed to a narrow trigger button's width.
  static double resolveDropdownMenuWidth(
    BuildContext context, {
    double? preferredWidth,
    double minMobileWidth = 272,
    double maxDesktopWidth = 420,
  }) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final maxAllowed = math.max(180.0, screenWidth - 28.0);
    if (preferredWidth != null) {
      return math.min(maxAllowed, preferredWidth);
    }
    if (screenWidth < 860) {
      return math.min(maxAllowed, math.max(minMobileWidth, screenWidth - 36.0));
    }
    return math.min(maxAllowed, maxDesktopWidth);
  }

  /// Standard `DropdownStyleData` for `dropdown_button2`:
  /// - Explicit `width` (`dropdownWidth`) so mobile secondary menus are never narrower than their labels
  /// - Explicit `maxHeight` + visible scrollbar + rounded white card surface
  /// - Safe area + vertical offset so popup never collides with screen edges
  static DropdownStyleData dropdownStyle(
    BuildContext context, {
    double maxHeight = 320,
    double? dropdownWidth,
    DropdownDirection direction = DropdownDirection.textDirection,
  }) {
    final screenH = MediaQuery.sizeOf(context).height;
    final viewPadding = MediaQuery.paddingOf(context);
    final mobile = isMobile(context);
    final bottomReserve =
        math.max(mobile ? 88.0 : 24.0, viewPadding.bottom + (mobile ? 78.0 : 20.0));
    final safeMaxH = math.max(
      160.0,
      math.min(maxHeight, screenH - viewPadding.top - bottomReserve - 64.0),
    );
    return DropdownStyleData(
      maxHeight: safeMaxH,
      width: dropdownWidth,
      direction: direction,
      useSafeArea: true,
      elevation: 6,
      offset: const Offset(0, -2),
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(radiusCard),
        border: Border.all(color: border),
      ),
      scrollbarTheme: ScrollbarThemeData(
        radius: const Radius.circular(4),
        thickness: WidgetStateProperty.all(4),
        thumbVisibility: WidgetStateProperty.all(true),
      ),
    );
  }

  /// Standard `MenuItemStyleData` for `dropdown_button2`:
  /// - Explicit `itemHeight: 52` on mobile (≥ 48dp Material touch target + 2-line CJK room)
  /// - Highlighted active row background for immediate visual feedback
  static MenuItemStyleData menuItemStyle(
    BuildContext context, {
    double? itemHeight,
    EdgeInsetsGeometry padding = const EdgeInsets.symmetric(horizontal: 12),
  }) {
    final effectiveHeight = itemHeight ?? (isMobile(context) ? 52.0 : 44.0);
    return MenuItemStyleData(
      height: effectiveHeight,
      padding: padding,
      selectedMenuItemBuilder: (ctx, child) => Container(
        decoration: const BoxDecoration(
          color: raised,
        ),
        child: child,
      ),
    );
  }

  /// Standard `IconStyleData` for `dropdown_button2`.
  static const IconStyleData dropdownIconStyle = IconStyleData(
    icon: Icon(Icons.keyboard_arrow_down_rounded, color: muted),
    openMenuIcon: Icon(Icons.keyboard_arrow_up_rounded, color: accent),
    iconSize: 18,
  );

  /// Present a complex multi-input / rebind / roster / settings modal:
  /// - On mobile (`< 860px`), uses `modal_bottom_sheet` (`showCustomModalBottomSheet`)
  ///   with a top drag handle and bottom `NavigationBar` clearance (`bottomReserve`)
  ///   so secondary dropdowns and long student/school fields have full width and vertical room.
  /// - On desktop (`>= 860px`), presents the standard centered `Dialog`.
  static Future<T?> showResponsiveModal<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    bool enableDrag = false,
  }) {
    if (!isMobile(context)) {
      return showDialog<T>(
        context: context,
        builder: builder,
      );
    }
    return mbs.showCustomModalBottomSheet<T>(
      context: context,
      expand: true,
      enableDrag: enableDrag,
      isDismissible: true,
      useRootNavigator: false,
      barrierColor: Colors.black54,
      duration: Duration.zero,
      containerWidget: (ctx, animation, child) {
        return SafeArea(
          bottom: false,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 38,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 4),
                  decoration: BoxDecoration(
                    color: Colors.white70,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                Flexible(child: child),
              ],
            ),
          ),
        );
      },
      builder: builder,
    );
  }

  // Neutral Surfaces & Borders (95% neutral interface)
  static const Color ground = Color(0xFFF5F7F9);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color raised = Color(0xFFF4F6F8);
  static const Color active = Color(0xFFEBEDEE);
  static const Color border = Color(0xFFE8EAEC);
  static const Color rule = Color(0xFFF0F1F2);
  static const Color control = Color(0xFFCDCED1);

  // Ink & Typography
  static const Color text = Color(0xFF131416);
  static const Color muted = Color(0xFF5D5F60);
  static const Color faint = Color(0xFF6B6E70);

  // Single Brand Accent & Semantic Colors (Never violet/purple)
  static const Color accent = Color(0xFF1B6C80);
  static const Color primary = Color(0xFF131416);
  static const Color primaryInk = Color(0xFFFFFFFF);
  static const Color positive = Color(0xFF1E7B4F);
  static const Color negative = Color(0xFFC4242A);
  static const Color warning = Color(0xFF92400E);
  static const Color chart1 = Color(0xFF1B6C80);
  static const Color chart2 = Color(0xFF2F70BB);
  static const Color chart3 = Color(0xFFA86F0C);

  // Semantic Pale Pills
  static const Color pillPosBg = Color(0xFFDCFAE5);
  static const Color pillPosInk = Color(0xFF04250E);
  static const Color pillNegBg = Color(0xFFFFEDEA);
  static const Color pillNegInk = Color(0xFF831C1E);
  static const Color pillWarnBg = Color(0xFFFFFBEB);
  static const Color pillWarnInk = Color(0xFF92400E);
  static const Color pillNeutralBg = Color(0xFFEBEDEE);
  static const Color pillNeutralInk = Color(0xFF353736);
  static const Color pillBlueBg = Color(0xFFE0F2FE);
  static const Color pillBlueInk = Color(0xFF0C4A6E);

  // Radii & Spacing
  static const double radiusCard = 8.0;
  static const double radiusControl = 6.0;
  static const double radiusSheet = 16.0;

  static const List<FontFeature> tabularNums = <FontFeature>[
    FontFeature.tabularFigures(),
  ];

  static TextStyle numStyle({
    double size = 14,
    FontWeight weight = FontWeight.w500,
    Color color = text,
  }) {
    return TextStyle(
      fontFamily: fontFamily,
      fontSize: size,
      fontWeight: weight,
      color: color,
      fontFeatures: tabularNums,
    );
  }

  /// Safe dialog inset padding that always clears the mobile bottom function bar
  /// (`NavigationBar`, 62px) when the soft keyboard is closed.
  static EdgeInsets dialogInsetPadding(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final isMobile = size.width < 860;
    if (!isMobile) {
      return const EdgeInsets.symmetric(horizontal: 24, vertical: 24);
    }
    final bottomReserve = viewInsets.bottom > 0 ? 14.0 : 78.0;
    return EdgeInsets.fromLTRB(14, 18, 14, bottomReserve);
  }

  /// Maximum dialog height bounded to the actual visible viewport above the
  /// bottom function bar and soft keyboard.
  static double dialogMaxHeight(
    BuildContext context, {
    double desktopMax = 700,
  }) {
    final size = MediaQuery.sizeOf(context);
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final viewPadding = MediaQuery.viewPaddingOf(context);
    final insets = dialogInsetPadding(context);
    final avail = size.height -
        viewInsets.bottom -
        viewPadding.vertical -
        insets.vertical;
    return math.max(200.0, math.min(desktopMax, avail));
  }

  /// Opaque, top-bordered dialog action footer that prevents options or
  /// semi-transparent modal barriers from overlapping action buttons.
  static Widget buildDialogFooter({
    required List<Widget> children,
    EdgeInsetsGeometry padding = const EdgeInsets.fromLTRB(16, 10, 16, 12),
  }) {
    Widget content;
    if (children.length == 1) {
      content = Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: children,
      );
    } else if (children.length == 2) {
      content = Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          children[0],
          const SizedBox(width: 10),
          Flexible(child: children[1]),
        ],
      );
    } else {
      content = Wrap(
        alignment: WrapAlignment.end,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 10,
        runSpacing: 8,
        children: children,
      );
    }
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: const BoxDecoration(
        color: surface,
        border: Border(top: BorderSide(color: border)),
      ),
      child: content,
    );
  }

  /// Opaque cancel button with guaranteed minimum 80x38 hit area.
  static Widget dialogCancelButton({
    required VoidCallback? onPressed,
    String label = '取消',
  }) {
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        backgroundColor: surface,
        foregroundColor: text,
        side: const BorderSide(color: control),
        minimumSize: const Size(80, 38),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        tapTargetSize: MaterialTapTargetSize.padded,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusControl),
        ),
      ),
      onPressed: onPressed,
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontFamily: fontFamily,
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: text,
        ),
      ),
    );
  }
}

enum TastePillTone { neutral, positive, negative, warning, blue }

class TastePill extends StatelessWidget {
  final String label;
  final TastePillTone tone;
  final int maxLines;

  const TastePill({
    super.key,
    required this.label,
    this.tone = TastePillTone.neutral,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    late Color bg;
    late Color fg;
    switch (tone) {
      case TastePillTone.positive:
        bg = Taste.pillPosBg;
        fg = Taste.pillPosInk;
        break;
      case TastePillTone.negative:
        bg = Taste.pillNegBg;
        fg = Taste.pillNegInk;
        break;
      case TastePillTone.warning:
        bg = Taste.pillWarnBg;
        fg = Taste.pillWarnInk;
        break;
      case TastePillTone.blue:
        bg = Taste.pillBlueBg;
        fg = Taste.pillBlueInk;
        break;
      case TastePillTone.neutral:
        bg = Taste.pillNeutralBg;
        fg = Taste.pillNeutralInk;
        break;
    }
    return Container(
      constraints: const BoxConstraints(minHeight: 22),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontFamily: Taste.fontFamily,
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: fg,
          fontFeatures: Taste.tabularNums,
        ),
      ),
    );
  }
}

/// Read-only score view through the official WeChat mini-program proxy.
