/// One choice of an event as the table lists it: its title, its own text, the
/// key of the scene it leads to (empty when it names none) and the key of the
/// scene that is its own result (the one numbered like it, shown when it is
/// chosen; empty when there is none).
typedef EventChoice = ({String title, String text, String next, String own});

class _Node {
  _Node(this.title, this.text, this.after, this.gate);

  final String title;
  final String text;

  /// What is said after choosing: the choice's own result, then the scene it
  /// leads to.
  final String after;

  /// A choice that names no scene: what is offered after it follows it in the
  /// table (its own options, then the next round).
  final bool gate;
  final List<_Node> children = [];
}

/// The options of an event as a list whose bullets say how deep they are (-,
/// --, ---), each option followed by the text that appears after choosing
/// it (no indentation: a text stored in pieces loses the spaces at the start of
/// a piece):
///
///     - **option**：its own text
///     what is said after choosing it
///     -- **a later option** …
///
/// The tables give a choice → scene link but no "this scene offers these
/// choices" link, so the layers are read from the order the choices are
/// listed in: a choice that names no scene opens a new layer, and the choices
/// after it (up to the next such choice) are offered in it. Choices that say
/// the same words are one (variants of one outcome); a layer that repeats an
/// earlier one word for word is not listed again.
String eventOutline(
  List<EventChoice> choices,
  String Function(String sceneKey) sceneText,
) {
  String say(String key) => key.isEmpty ? '' : sceneText(key);
  String after(EventChoice c) {
    final own = say(c.own), next = say(c.next);
    return [
      if (own.isNotEmpty) own,
      if (next.isNotEmpty && next != own) next,
    ].join('\n');
  }

  final root = <_Node>[];
  var into = root;
  for (final c in choices) {
    if (c.title.isEmpty) continue;
    final said = after(c);
    final gate = c.next.isEmpty;
    final twin = into.any(
      (n) =>
          n.title == c.title &&
          n.text == c.text &&
          n.after == said &&
          n.gate == gate,
    );
    if (twin) continue;
    final node = _Node(c.title, c.text, said, gate);
    into.add(node);
    if (gate) into = node.children;
  }

  // A layer that says what an earlier one said adds nothing.
  final seen = <String>{};
  String signature(List<_Node> layer) => [
        for (final n in layer) '${n.title}|${n.text}|${n.after}',
      ].join('\n');
  void prune(List<_Node> layer) {
    if (layer.isEmpty) return;
    if (!seen.add(signature(layer))) {
      layer.clear();
      return;
    }
    for (final n in layer) {
      prune(n.children);
    }
  }

  prune(root);

  final out = StringBuffer();
  void write(List<_Node> layer, int depth) {
    final mark = '-' * (depth + 1);
    final said = <String>{};
    for (final n in layer) {
      out.writeln('$mark **${n.title}**${n.text.isEmpty ? '' : '：${n.text}'}');
      if (n.after.isNotEmpty) {
        final line = said.add(n.after) ? n.after : '（结果同上）';
        for (final l in line.split('\n')) {
          if (l.trim().isNotEmpty) out.writeln(l.trim());
        }
      }
      write(n.children, depth + 1);
    }
  }

  write(root, 0);
  return out.toString().trimRight();
}
