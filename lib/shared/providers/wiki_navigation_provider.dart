import 'package:flutter_riverpod/flutter_riverpod.dart';

typedef WikiBackHandler = Future<bool> Function();

final wikiBackHandlerProvider = StateProvider<WikiBackHandler?>((ref) => null);

final wikiReaderFullscreenProvider = StateProvider<bool>((ref) => false);
