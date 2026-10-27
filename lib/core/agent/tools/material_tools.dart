import '../../materials/material_snapshot.dart';
import '../context_ledger.dart';
import '../lore_tools.dart';
import 'agent_tool.dart';

class ReadMaterialTool extends AgentTool {
  ReadMaterialTool(this.materials, this.seen);
  final MaterialSnapshot materials;
  final SeenLines seen;
  @override
  String get name => 'read_material';
  @override
  String get description =>
      '分页读取已启用补充资料的原文、作者与来源说明；id 使用 search 给出的完整 material:文档ID@版本。每个 P 段展示后才能引用；长文用 start 继续。';
  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'id': {'type': 'string'},
          'start': {'type': 'integer', 'description': '从0起的段号'},
          'count': {'type': 'integer', 'description': '默认12，最多30段'},
        },
        'required': ['id'],
      };
  @override
  Future<String> execute(Map<String, dynamic> a) async => materials.read(
        '${a['id'] ?? ''}',
        (a['start'] as num?)?.toInt() ?? 0,
        ((a['count'] as num?)?.toInt() ?? 12).clamp(1, 30),
        seen.add,
      );
}

/// The existing tools retain their names and cover both game and supplemental text.
class MaterialJoinedTool extends AgentTool {
  MaterialJoinedTool(this.inner, this.materials, this.seen, {this.ledger});
  final AgentTool inner;
  final MaterialSnapshot materials;
  final SeenLines seen;
  final ContextLedger? ledger;
  @override
  String get name => inner.name;
  @override
  String get description =>
      '${inner.description}\n同时覆盖已启用的补充资料；可与游戏原文联查。${name == 'sql' ? 'source=materials 时只读查询 material_documents(id,version,source,title,kind,policy) 和 material_blocks(id,version,paragraph,heading,kind,author,content)。查询不返回其他用户数据。' : ''}';
  @override
  Map<String, dynamic> get parameters => {
        ...inner.parameters,
        'properties': {
          ...inner.parameters['properties'] as Map<String, dynamic>,
          if (name == 'sql')
            'source': {
              'type': 'string',
              'enum': ['games', 'materials'],
              'description': '默认 games；materials 为本轮已启用资料的只读快照',
            },
        },
      };
  @override
  Future<String> execute(Map<String, dynamic> a) async {
    if (name == 'sql' && a['source'] == 'materials') {
      final result = await materials.sql('${a['query'] ?? ''}');
      if (result.error != null) return result.error!;
      final out = StringBuffer(result.columns.join(' | '));
      for (final row in result.rows) {
        final line = row.map((x) => '$x').join(' | ');
        if (out.length + line.length > 7000) {
          out.writeln('\n其余未展示；加条件缩小范围，正文用 read_material。');
          break;
        }
        out.writeln('\n$line');
        final fields = Map.fromIterables(result.columns, row);
        if (fields['id'] is String &&
            fields['version'] is String &&
            fields['paragraph'] is num &&
            fields['content'] is String) {
          final id = 'material:${fields['id']}@${fields['version']}';
          final doc = materials.document(id);
          final p = (fields['paragraph'] as num).toInt();
          if (doc != null &&
              p >= 0 &&
              p < doc.blocks.length &&
              doc.blocks[p].text == fields['content']) {
            seen.add(id, p);
          }
        }
      }
      if (result.truncated) out.writeln('\n仅列前200行；缩小查询范围。');
      return out.toString();
    }
    final args = Map<String, dynamic>.from(a)..remove('source');
    final original = await inner.execute(args);
    if (name == 'guide') {
      return '$original\n\n${materials.guide}\nSQL 资料表见 sql 工具说明。';
    }
    if (name == 'grep' && (a['collection'] != null || a['story_ids'] != null)) {
      return '$original';
    }
    final query = name == 'gather'
        ? (a['names'] as List? ?? []).join(' ')
        : '${a['pattern'] ?? ''}';
    final hits = materials.search(
      query,
      game: a['game'] as String?,
      limit: 6,
      bodyOnly: true,
    );
    return '$original\n\n${materials.render(hits, seen.add, maxChars: name == 'gather' ? 6000 : 4000)}';
  }
}
