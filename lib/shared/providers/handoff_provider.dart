import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A main tab another page wants shown (0 wiki, 1 AI, 2 library, 3
/// settings); the shell switches to it and clears this.
final mainTabRequestProvider = StateProvider<int?>((ref) => null);

/// 0.13: a page another page wants opened in the Wiki tab (an answer's
/// wiki citation): [siteId] is the wiki tab to use (`prts` / `endfield`).
/// The Wiki page loads it and clears this.
class WikiOpenRequest {
  const WikiOpenRequest(this.siteId, this.url);
  final String siteId;
  final Uri url;
}

final wikiOpenRequestProvider = StateProvider<WikiOpenRequest?>((ref) => null);
