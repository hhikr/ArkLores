/// 0.11 library page: a stable reference to one readable item.
///
/// The user database never points into the official knowledge base with
/// foreign keys or row ids: a knowledge base update replaces the whole file
/// and rebuilds row ids. It stores these strings instead, built from the
/// stable identifiers the importer keeps (`story_id`, `normalized_records.id`,
/// `entity_id` + `document_type`). When an update drops or renames the
/// target, the reference still parses; the page shows it as "no longer in
/// the current knowledge base" instead of failing (see `docs/V0.11_PLAN.md`).
library;

/// What kind of item a [LibraryRef] points at.
enum LibraryRefKind {
  /// One story file (`story_lines.story_id`), read line by line.
  story('story'),

  /// One normalized record (`normalized_records.id`), e.g. an enemy profile.
  record('record'),

  /// One entity document (`entity_documents`: entity id + document type).
  document('document'),

  /// One user material (user database row id).
  user('user');

  const LibraryRefKind(this.prefix);

  /// Prefix in the serialized form `<prefix>:<id>`.
  final String prefix;
}

/// A parsed `<kind>:<id>` reference, e.g. `story:<story_id>`.
class LibraryRef {
  const LibraryRef(this.kind, this.id);

  /// The reference for one story file.
  const LibraryRef.story(String storyId) : this(LibraryRefKind.story, storyId);

  /// The reference for one normalized record.
  const LibraryRef.record(String recordId)
      : this(LibraryRefKind.record, recordId);

  /// The reference for an entity document; [documentType] keeps two
  /// documents of the same entity apart.
  LibraryRef.document(String entityId, String documentType)
      : this(LibraryRefKind.document, '$entityId/$documentType');

  /// The reference for one user material.
  const LibraryRef.user(String materialId)
      : this(LibraryRefKind.user, materialId);

  final LibraryRefKind kind;
  final String id;

  /// Parses `<kind>:<id>`; returns null for an unknown kind or an empty id,
  /// so a reference written by a newer app version is skipped, not fatal.
  static LibraryRef? tryParse(String value) {
    final cut = value.indexOf(':');
    if (cut <= 0 || cut == value.length - 1) return null;
    final prefix = value.substring(0, cut);
    for (final kind in LibraryRefKind.values) {
      if (kind.prefix == prefix) return LibraryRef(kind, value.substring(cut + 1));
    }
    return null;
  }

  /// Whether the item lives in the read-only official knowledge base.
  bool get isOfficial => kind != LibraryRefKind.user;

  @override
  String toString() => '${kind.prefix}:$id';

  @override
  bool operator ==(Object other) =>
      other is LibraryRef && other.kind == kind && other.id == id;

  @override
  int get hashCode => Object.hash(kind, id);
}
