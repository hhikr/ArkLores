final _sprite = RegExp(r'^(char|avg)_[a-z0-9_+]+(#\d+)?(\$\d+)?$');

/// The canonical sprite name, or null when [raw] is not a sprite name.
String? canonicalSprite(String raw) {
  final value = raw.replaceAll(RegExp(r'\s', unicode: true), '').toLowerCase();
  if (!_sprite.hasMatch(value)) return null;
  final parts = value.split(RegExp(r'[#\$]'));
  final face = RegExp(r'#(\d+)').firstMatch(value)?.group(1) ?? '1';
  final body = RegExp(r'\$(\d+)').firstMatch(value)?.group(1) ?? '1';
  return SpriteName(parts.first, int.parse(face), int.parse(body)).canonical;
}

class SpriteName {
  const SpriteName(this.group, this.face, this.body);
  final String group;
  final int face;
  final int body;
  String get canonical => '$group#$face\$$body';

  static SpriteName? parse(String canonical) {
    final match = RegExp(r'^((?:char|avg)_[a-z0-9_+]+)#(\d+)\$(\d+)$')
        .firstMatch(canonical);
    if (match == null) return null;
    final face = int.tryParse(match[2]!);
    final body = int.tryParse(match[3]!);
    if (face == null || body == null) return null;
    final name = SpriteName(match[1]!, face, body);
    return name.canonical == canonical ? name : null;
  }
}
