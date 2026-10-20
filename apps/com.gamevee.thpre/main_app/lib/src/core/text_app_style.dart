import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Typography for all [AppLanguage] values: Vietnamese, English, Japanese, Chinese.
///
/// **Full coverage**
/// - [ui] uses **Noto Sans** (Latin Extended, Vietnamese) with
///   [cjkFontFamilyFallback] so ja/zh glyphs resolve correctly.
///
/// **Display fonts**
/// - [rajdhani] and [pressStart2p] keep the game look for Latin; any CJK in
///   localized strings falls through to **Noto Sans JP** / **Noto Sans SC**.
///
/// Call [precacheMultilingualFonts] once at startup (see [main]) so fallbacks
/// load early and first paint avoids missing glyphs.
class TextAppStyle {
  TextAppStyle._();

  /// Registered families used after the primary font for Japanese and Chinese.
  static const List<String> cjkFontFamilyFallback = [
    // Latin Extended (Vietnamese) first to avoid tofu when primary is a display font
    // (e.g. Rajdhani / Press Start 2P) that lacks Vietnamese glyphs.
    'Noto Sans',
    // System default on Android; helps if Noto isn't ready yet.
    'Roboto',
    'Noto Sans JP',
    'Noto Sans SC',
  ];

  /// Call once at startup (see [main]) before any [GoogleFonts] [TextStyle].
  ///
  /// `google_fonts` loads via an **unawaited** future and **rethrows** on
  /// failure (offline, DNS, or missing assets). That becomes an unhandled
  /// isolate exception. We keep runtime fetch on (so fonts work when online)
  /// and mark those failures as handled; [cjkFontFamilyFallback] still applies.
  static void precacheMultilingualFonts() {
    GoogleFonts.config.allowRuntimeFetching = true;
    final bool Function(Object, StackTrace)? previous =
        PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      if (_isGoogleFontsLoadFailure(error)) {
        if (kDebugMode) {
          debugPrint('google_fonts load failed (non-fatal): $error');
        }
        return true;
      }
      return previous?.call(error, stack) ?? false;
    };
  }

  static bool _isGoogleFontsLoadFailure(Object error) {
    final String message = error.toString();
    return message.contains('GoogleFonts.config.allowRuntimeFetching') ||
        message.contains('Failed to load font with url') ||
        message.contains('fonts.gstatic.com') ||
        message.contains('was not found in the application assets');
  }

  /// Default for any localized body copy (safest for vi / en / ja / zh).
  static TextStyle ui({
    required double fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? letterSpacing,
    double? height,
    TextDecoration? decoration,
  }) {
    return GoogleFonts.notoSans(
      fontSize: fontSize,
      fontWeight: fontWeight ?? FontWeight.w400,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
      decoration: decoration,
    ).copyWith(
      fontFamilyFallback: cjkFontFamilyFallback,
    );
  }

  /// Condensed game UI (headings, buttons). Same CJK fallbacks as [ui].
  static TextStyle rajdhani({
    required double fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? letterSpacing,
    double? height,
    List<Shadow>? shadows,
  }) {
    return GoogleFonts.rajdhani(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
      shadows: shadows,
    ).copyWith(
      fontFamilyFallback: cjkFontFamilyFallback,
    );
  }

  /// Pixel / retro titles. CJK in strings uses fallbacks (e.g. [l10n.appTitle] in ja).
  static TextStyle pressStart2p({
    required double fontSize,
    Color? color,
    List<Shadow>? shadows,
    FontWeight? fontWeight,
  }) {
    return GoogleFonts.pressStart2p(
      fontSize: fontSize,
      color: color,
      shadows: shadows,
      fontWeight: fontWeight,
    ).copyWith(
      fontFamilyFallback: cjkFontFamilyFallback,
    );
  }

  /// **SF Pro** on iOS/macOS with [cjkFontFamilyFallback]; elsewhere [ui] (e.g. Roboto + Noto).
  static TextStyle sfProWithCjkFallback({
    required double fontSize,
    FontWeight fontWeight = FontWeight.w400,
    Color? color,
    double? letterSpacing,
    double? height,
  }) {
    final bool useSfPro = defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;
    if (!useSfPro) {
      return ui(
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
        letterSpacing: letterSpacing,
        height: height,
      );
    }
    final String family =
        fontSize >= 20 ? '.SF Pro Display' : '.SF Pro Text';
    return TextStyle(
      fontFamily: family,
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
      fontFamilyFallback: cjkFontFamilyFallback,
    );
  }

  /// Regional-indicator flags (e.g. 🇻🇳) and emoji. Do not use [ui] — Noto Sans
  /// replaces them with tofu or blank glyphs.
  static TextStyle emojiOnly({
    required double fontSize,
    Color? color,
  }) {
    final TextStyle base = TextStyle(
      fontSize: fontSize,
      height: 1.05,
      color: color,
      inherit: false,
    );
    if (kIsWeb) {
      return base;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        return base.copyWith(fontFamily: 'Apple Color Emoji');
      case TargetPlatform.android:
        return base.copyWith(fontFamily: 'Noto Color Emoji');
      case TargetPlatform.windows:
        return base.copyWith(fontFamily: 'Segoe UI Emoji');
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        return base;
    }
  }
}
