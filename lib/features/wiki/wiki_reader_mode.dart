import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'wiki_appearance_palette.dart';
import 'wiki_reader_css.dart';
import 'wiki_reader_scripts.dart';
import 'wiki_site_adapter.dart';

class WikiReaderMode {
  WikiReaderMode._();

  static const _regularFontAsset =
      'assets/fonts/lxgw-wenkai/LXGWWenKai-Regular.woff2';

  static Future<String>? _fontFacesFuture;

  static Future<String> _fontFaces() {
    return _fontFacesFuture ??= _buildFontFaces();
  }

  static Future<String> _buildFontFaces() async {
    final data = await rootBundle.load(_regularFontAsset);
    final bytes =
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    final uri = 'data:font/woff2;base64,${base64Encode(bytes)}';
    return '''
@font-face {
  font-family: "$readerFontFamily";
  src: url("$uri") format("woff2");
  font-weight: 400 700;
  font-style: normal;
  font-display: swap;
}
''';
  }

  static Future<void> setEnabled(
    InAppWebViewController controller, {
    required bool enabled,
    required bool dark,
    required double fontScale,
  }) async {
    if (!enabled) {
      await remove(controller);
      return;
    }
    await inject(controller, dark: dark, fontScale: fontScale);
  }

  static Future<void> inject(
    InAppWebViewController controller, {
    required bool dark,
    required double fontScale,
    WikiSiteKind siteKind = WikiSiteKind.generic,
  }) async {
    final fontFaces = await _fontFaces();
    final palette =
        dark ? WikiAppearancePalette.dark : WikiAppearancePalette.light;
    final baseFontSize = (18 * fontScale).clamp(11, 25).toStringAsFixed(1);
    final lineHeight =
        (1.72 - ((fontScale - 1) * 0.08)).clamp(1.56, 1.78).toStringAsFixed(2);

    final css = buildReaderCss(
      fontFaces: fontFaces,
      palette: palette,
      dark: dark,
      fontScale: fontScale,
      baseFontSize: baseFontSize,
      lineHeight: lineHeight,
    );
    final js = buildReaderScript(
      siteKind: siteKind,
      dark: dark,
      css: css,
    );
    try {
      await controller.evaluateJavascript(source: js);
    } catch (_) {
      // Reader mode is best-effort for third-party pages.
    }
  }

  static Future<void> remove(InAppWebViewController controller) async {
    final js = buildRemoveReaderScript();
    try {
      await controller.evaluateJavascript(source: js);
    } catch (_) {
      // Best-effort cleanup only.
    }
  }
}
