/// 0.13: the text of a wiki page's HTML as numbered paragraphs
/// ([WikiBlock]s) for the Ask agent.
///
/// Generic rules only (no per-page layouts): headings start sections;
/// paragraphs, list items and the like are one paragraph each; a table row
/// is one paragraph with its cells joined by ` | `. Left out: scripts,
/// styles, forms and buttons, images, MediaWiki's edit links, reference
/// marks, navigation boxes and tables of contents, hidden elements — and
/// rows that are mostly numbers (stat tables: gameplay, not story).
library;

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

import 'wiki_page.dart';

/// Elements whose content is never page text.
const Set<String> _skippedTags = {
  'script', 'style', 'noscript', 'template', 'svg', 'canvas', 'iframe',
  'button', 'input', 'select', 'textarea', 'form', 'img', 'picture',
  'video', 'audio', 'source', 'nav', 'link', 'meta',
};

/// MediaWiki (and common) classes of page furniture: edit links,
/// reference marks, navigation boxes, tables of contents, print-only
/// helpers.
const Set<String> _skippedClasses = {
  'mw-editsection', 'reference', 'references', 'mw-references-wrap',
  'navbox', 'navbox-inner', 'toc', 'noprint', 'mw-empty-elt', 'catlinks',
  'printfooter', 'mw-jump-link', 'sr-only', 'visually-hidden',
};

const Set<String> _blockTags = {
  'p', 'div', 'section', 'article', 'main', 'aside', 'header', 'footer',
  'ul', 'ol', 'li', 'dl', 'dt', 'dd', 'table', 'thead', 'tbody', 'tfoot',
  'tr', 'caption', 'blockquote', 'pre', 'figure', 'figcaption', 'details',
  'summary', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'hr', 'center', 'body',
};

const Set<String> _headingTags = {'h1', 'h2', 'h3', 'h4', 'h5', 'h6'};

/// Most paragraphs a page gives (long list pages are cut).
const int maxWikiBlocks = 2000;

/// The paragraphs of [html] (a whole document or a fragment). [root]: a CSS
/// selector for the content element; the first match is read, the whole
/// body when nothing matches.
List<WikiBlock> wikiBlocksFromHtml(String html, {String? root}) {
  final document = html_parser.parse(html);
  Element? start;
  if (root != null) {
    for (final selector in root.split(',')) {
      start = document.querySelector(selector.trim());
      if (start != null) break;
    }
  }
  start ??= document.body ?? document.documentElement;
  if (start == null) return const [];
  final reader = _BlockReader();
  reader.walk(start);
  reader.flush();
  return reader.blocks;
}

/// The `<title>` of [html], without the site's suffix after " - ".
String wikiHtmlTitle(String html) {
  final title = html_parser.parse(html).querySelector('title')?.text ?? '';
  final cut = title.lastIndexOf(' - ');
  return (cut > 0 ? title.substring(0, cut) : title).trim();
}

/// [html] (a search snippet) as plain text.
String wikiPlainText(String html) =>
    _clean(html_parser.parseFragment(html).text ?? '');

class _BlockReader {
  _BlockReader({this.dropNumbers = true});

  /// Whether rows of numbers are dropped (not inside a table cell: the row
  /// is judged as a whole).
  final bool dropNumbers;
  final List<WikiBlock> blocks = [];
  final StringBuffer _inline = StringBuffer();
  String _section = '';

  void walk(Node node) {
    if (blocks.length >= maxWikiBlocks) return;
    if (node is Text) {
      _inline.write(node.text);
      return;
    }
    if (node is! Element) return;
    final tag = node.localName ?? '';
    if (_skip(node, tag)) return;
    if (tag == 'br') {
      _inline.write('\n');
      return;
    }
    if (_headingTags.contains(tag)) {
      flush();
      final heading = _clean(_visibleText(node));
      if (heading.isNotEmpty) _section = heading;
      return;
    }
    if (tag == 'tr') {
      flush();
      final cells = [
        for (final cell in node.children)
          if (cell.localName == 'td' || cell.localName == 'th')
            if (!_skip(cell, cell.localName!)) _clean(_textOf(cell)),
      ]..removeWhere((c) => c.isEmpty);
      if (cells.isNotEmpty) _emit(cells.join(' | '));
      return;
    }
    if (_blockTags.contains(tag)) {
      flush();
      for (final child in node.nodes) {
        walk(child);
      }
      flush();
      return;
    }
    for (final child in node.nodes) {
      walk(child);
    }
  }

  void flush() {
    if (_inline.isEmpty) return;
    final text = _clean(_inline.toString());
    _inline.clear();
    if (text.isNotEmpty) _emit(text);
  }

  void _emit(String text) {
    if (dropNumbers && _mostlyNumbers(text)) return;
    if (blocks.isNotEmpty &&
        blocks.last.text == text &&
        blocks.last.section == _section) {
      return;
    }
    blocks.add(WikiBlock(_section, text));
  }

  /// The text of a table cell, its own line breaks kept.
  String _textOf(Element cell) {
    final reader = _BlockReader(dropNumbers: false).._section = _section;
    for (final child in cell.nodes) {
      reader.walk(child);
    }
    reader.flush();
    return [for (final b in reader.blocks) b.text].join(' / ');
  }

  /// The text of [e] without the parts [_skip] leaves out.
  static String _visibleText(Element e) {
    final out = StringBuffer();
    void visit(Node n) {
      if (n is Text) {
        out.write(n.text);
      } else if (n is Element && !_skip(n, n.localName ?? '')) {
        n.nodes.forEach(visit);
      }
    }

    e.nodes.forEach(visit);
    return out.toString();
  }

  static bool _skip(Element e, String tag) {
    if (_skippedTags.contains(tag)) return true;
    if (e.attributes['hidden'] != null) return true;
    if (e.attributes['aria-hidden'] == 'true') return true;
    final style = (e.attributes['style'] ?? '').replaceAll(' ', '');
    if (style.contains('display:none')) return true;
    for (final c in e.classes) {
      if (_skippedClasses.contains(c)) return true;
    }
    return false;
  }
}

final RegExp _spaces = RegExp(r'[ \t 　\r\f\v]+');
final RegExp _blankLines = RegExp(r'\s*\n\s*');

/// Spaces collapsed; line breaks kept (one per break), trimmed.
String _clean(String text) => text
    .replaceAll(_spaces, ' ')
    .replaceAll(_blankLines, '\n')
    .trim();

final RegExp _numberToken =
    RegExp(r'^[-+]?[\d.,]+[%‰]?$|^[\d.]+[sSkKmMwW秒级阶★x×]?$|^[-–—/]$');

/// A row of stats: at least three tokens, most of them numbers; or a lone
/// number.
bool _mostlyNumbers(String text) {
  final tokens = [
    for (final t in text.split(RegExp(r'[\s|/]+')))
      if (t.isNotEmpty) t,
  ];
  if (tokens.isEmpty) return true;
  final numbers = tokens.where(_numberToken.hasMatch).length;
  if (tokens.length == 1) return numbers == 1;
  return tokens.length >= 3 && numbers / tokens.length >= 0.6;
}
