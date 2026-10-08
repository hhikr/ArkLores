/// 0.13: a wiki page as the Ask agent reads it — numbered paragraphs under
/// their section headings — and the ids its citations use.
///
/// A page id names the site, the page and the version the paragraphs were
/// numbered in: `wiki:prts:65528@430715` (PRTS page id 65528, revision
/// 430715), `wiki:warfarin:operators/perlica@3f2a9c01` (Warfarin has no
/// revision numbers: a hash of the page text). A citation adds paragraph
/// numbers like a story citation adds line numbers:
/// `wiki:prts:65528@430715:3-5`. The version keeps the numbers valid after
/// the page is edited: the cited version is kept as a snapshot.
library;

import '../gamedata/game.dart';

/// The wikis the agent can read: one per game.
enum WikiSite {
  /// PRTS (prts.wiki), the Arknights wiki (MediaWiki).
  prts,

  /// Warfarin Wiki (warfarin.wiki), the Endfield wiki.
  warfarin;

  /// The value in page ids.
  String get key => name;

  Game get game => switch (this) {
        WikiSite.prts => Game.arknights,
        WikiSite.warfarin => Game.endfield,
      };

  /// The site's name in tool output and in the interface.
  String get label => switch (this) {
        WikiSite.prts => 'PRTS',
        WikiSite.warfarin => 'Warfarin Wiki',
      };

  /// The page in a browser.
  Uri pageUrl(String pageKey) => switch (this) {
        // A page id resolves to its current title.
        WikiSite.prts => int.tryParse(pageKey) != null
            ? Uri.parse('https://prts.wiki/index.php?curid=$pageKey')
            : Uri.parse(
                'https://prts.wiki/w/${Uri.encodeComponent(pageKey.replaceAll(' ', '_'))}',
              ),
        WikiSite.warfarin => Uri.parse('https://warfarin.wiki/cn/$pageKey'),
      };

  static WikiSite? parse(String? key) {
    for (final s in WikiSite.values) {
      if (s.key == key) return s;
    }
    return null;
  }

  /// The wiki of [game].
  static WikiSite of(Game game) => switch (game) {
        Game.arknights => WikiSite.prts,
        Game.endfield => WikiSite.warfarin,
      };
}

/// Prefix of every wiki page id and citation.
const String wikiIdPrefix = 'wiki:';

/// A page id: `wiki:<site>:<page key>@<version>` (see the library comment).
/// Page keys are PRTS page ids or Warfarin `<type>/<slug>` paths.
final RegExp wikiPageIdPattern =
    RegExp(r'wiki:([a-z]+):([A-Za-z0-9_\-/]+)@([A-Za-z0-9]+)');

/// A wiki citation in answer text: a page id, then paragraph numbers
/// (`:3` or `:3-5`; a `P` before a number is accepted).
final RegExp wikiCitationPattern = RegExp(
  '${wikiPageIdPattern.pattern}'
  r'\s*[:：]\s*[Pp¶]?(\d+)(?:\s*[-–~]\s*[Pp¶]?(\d+))?',
);

/// The parts of a page id.
class WikiPageId {
  const WikiPageId(this.site, this.key, this.version);

  final WikiSite site;
  final String key;
  final String version;

  @override
  String toString() => '$wikiIdPrefix${site.key}:$key@$version';

  /// [id] read as a page id (exactly, nothing around it), or null.
  static WikiPageId? parse(String id) {
    final m = wikiPageIdPattern.matchAsPrefix(id.trim());
    if (m == null || m.end != id.trim().length) return null;
    final site = WikiSite.parse(m.group(1));
    if (site == null) return null;
    return WikiPageId(site, m.group(2)!, m.group(3)!);
  }

  Uri get url => site.pageUrl(key);
}

/// One paragraph of a page: a paragraph, a list item, a table row (cells
/// joined by ` | `), under the heading of its section.
class WikiBlock {
  const WikiBlock(this.section, this.text);

  /// The heading the paragraph stands under ('' before the first one).
  final String section;
  final String text;

  Map<String, dynamic> toJson() => {'s': section, 't': text};

  static WikiBlock fromJson(Map<String, dynamic> json) =>
      WikiBlock('${json['s'] ?? ''}', '${json['t'] ?? ''}');
}

/// A page as fetched: its paragraphs in one version.
class WikiPage {
  const WikiPage({
    required this.site,
    required this.key,
    required this.version,
    required this.title,
    required this.url,
    required this.fetchedAt,
    required this.blocks,
  });

  final WikiSite site;

  /// PRTS page id / Warfarin `<type>/<slug>`.
  final String key;

  /// PRTS revision id / hash of the text.
  final String version;
  final String title;
  final Uri url;
  final DateTime fetchedAt;
  final List<WikiBlock> blocks;

  /// The id the agent cites the page by.
  String get id => '$wikiIdPrefix${site.key}:$key@$version';

  /// The paragraphs [first]..[last] (clamped), with their numbers.
  List<(int, WikiBlock)> range(int first, int last) => [
        for (var i = first < 0 ? 0 : first;
            i <= last && i < blocks.length;
            i++)
          (i, blocks[i]),
      ];

  Map<String, dynamic> toJson() => {
        'site': site.key,
        'key': key,
        'version': version,
        'title': title,
        'url': '$url',
        'fetchedAt': fetchedAt.toIso8601String(),
        'blocks': [for (final b in blocks) b.toJson()],
      };

  static WikiPage? fromJson(Map<String, dynamic> json) {
    final site = WikiSite.parse('${json['site']}');
    final blocks = json['blocks'];
    if (site == null || blocks is! List) return null;
    return WikiPage(
      site: site,
      key: '${json['key']}',
      version: '${json['version']}',
      title: '${json['title'] ?? ''}',
      url: Uri.tryParse('${json['url']}') ?? site.pageUrl('${json['key']}'),
      fetchedAt:
          DateTime.tryParse('${json['fetchedAt']}') ?? DateTime.now(),
      blocks: [
        for (final b in blocks)
          if (b is Map<String, dynamic>) WikiBlock.fromJson(b),
      ],
    );
  }
}

/// One search result.
class WikiSearchHit {
  const WikiSearchHit({
    required this.site,
    required this.key,
    required this.title,
    this.snippet = '',
    this.category = '',
  });

  final WikiSite site;
  final String key;
  final String title;
  final String snippet;

  /// What kind of page it is, when the site says (Warfarin's type and
  /// category).
  final String category;

  /// The page as `wiki_read` takes it (no version: the current one).
  String get ref => '$wikiIdPrefix${site.key}:$key';
}

/// A wiki could not be reached or answered with an error.
class WikiUnavailable implements Exception {
  const WikiUnavailable(this.site, this.reason);
  final WikiSite site;
  final String reason;

  @override
  String toString() => '${site.label} 暂时无法访问（$reason）';
}
