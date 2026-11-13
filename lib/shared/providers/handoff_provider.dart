import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A main tab another page wants shown (0 wiki, 1 AI, 2 library, 3
/// settings); the shell switches to it and clears this.
final mainTabRequestProvider = StateProvider<int?>((ref) => null);

/// 0.13: a page another page wants opened in the Wiki tab (an answer's
/// wiki citation): [siteId] is the wiki source to use (`prts`, `endfield`,
/// or a source added in Settings); a site not among the tabs falls back to
/// the tab of the URL's host, then the first. The Wiki page loads it and
/// clears this.
class WikiOpenRequest {
  const WikiOpenRequest(this.siteId, this.url);
  final String siteId;
  final Uri url;
}

final wikiOpenRequestProvider = StateProvider<WikiOpenRequest?>((ref) => null);
