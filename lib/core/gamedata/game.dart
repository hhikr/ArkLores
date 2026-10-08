/// The games ArkLores has a knowledge base for, and how their ids are told
/// apart.
///
/// Each game has its own database file (its own download, its own update
/// rhythm) with the same schema. Every id an Endfield database writes —
/// story ids, entry raw ids, collection ids, record ids — starts with
/// [endfieldIdPrefix], so any id seen anywhere (a citation, a reading-history
/// ref, a library route) names its game without a lookup.
library;

enum Game {
  arknights,
  endfield;

  /// The installed database's file name.
  String get dbFileName => switch (this) {
        Game.arknights => 'arklores_gamedata_zh.db',
        Game.endfield => 'arklores_endfield_zh.db',
      };

  /// The value the agent's tools take for this game.
  String get key => name;

  /// The game's name in the interface and in tool output.
  String get label => switch (this) {
        Game.arknights => '明日方舟',
        Game.endfield => '终末地',
      };

  String get labelEn => switch (this) {
        Game.arknights => 'Arknights',
        Game.endfield => 'Endfield',
      };

  /// [raw] read as a game (`arknights` / `endfield`, or a label); null when
  /// it names neither.
  static Game? parse(Object? raw) {
    final text = '${raw ?? ''}'.trim().toLowerCase();
    if (text.isEmpty) return null;
    if (text.startsWith('ark') || text.contains('明日方舟') || text == 'ak') {
      return Game.arknights;
    }
    if (text.startsWith('end') || text.contains('终末地') || text == 'ef') {
      return Game.endfield;
    }
    return null;
  }
}

/// Prefix of every id in an Endfield database.
const String endfieldIdPrefix = 'ef/';

/// The game [id] belongs to: a story id, a record id, a collection id, an
/// entry id (`<type>:<raw id>`) or a user-data ref (`story:<id>`, …).
Game gameOfId(String id) {
  final text = id.trim();
  if (text.startsWith(endfieldIdPrefix)) return Game.endfield;
  final colon = text.indexOf(':');
  if (colon >= 0 && text.startsWith(endfieldIdPrefix, colon + 1)) {
    return Game.endfield;
  }
  return Game.arknights;
}

/// [raw] in the Endfield id namespace (unchanged when it already is).
String endfieldId(String raw) =>
    raw.startsWith(endfieldIdPrefix) ? raw : '$endfieldIdPrefix$raw';
