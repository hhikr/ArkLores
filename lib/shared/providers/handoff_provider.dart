import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Text another page wants in the Ask question box (the library's "ask about
/// it"). The Ask page puts it in the box, lets the user finish the question
/// and clears this; it is never sent on its own.
final askDraftProvider = StateProvider<String?>((ref) => null);

/// A main tab another page wants shown (0 wiki, 1 AI, 2 library, 3
/// settings); the shell switches to it and clears this.
final mainTabRequestProvider = StateProvider<int?>((ref) => null);
