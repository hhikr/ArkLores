import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:uuid/uuid.dart';

import '../../core/rag/chunker.dart';
import '../../core/rag/embedder.dart';
import '../../core/rag/vector_store.dart';

/// Result of importing a single book file.
class BookImportResult {
  final String bookId;
  final String fileName;
  final int chunkCount;

  const BookImportResult({
    required this.bookId,
    required this.fileName,
    required this.chunkCount,
  });
}

/// Progress reported during a book import operation.
class BookImportProgress {
  final String fileName;
  final String
      stage; // 'extracting', 'chunking', 'embedding', 'storing', 'done', 'error'
  final double fraction;
  final String? detail;
  final String? error;

  const BookImportProgress({
    required this.fileName,
    this.stage = 'extracting',
    this.fraction = 0.0,
    this.detail,
    this.error,
  });

  BookImportProgress copyWith({
    String? fileName,
    String? stage,
    double? fraction,
    String? detail,
    String? error,
  }) =>
      BookImportProgress(
        fileName: fileName ?? this.fileName,
        stage: stage ?? this.stage,
        fraction: fraction ?? this.fraction,
        detail: detail ?? this.detail,
        error: error ?? this.error,
      );
}

/// Service for importing book files (PDF/TXT) into the knowledge base.
///
/// Handles the full pipeline: file reading → text extraction → chunking →
/// embedding → storing.
class BookImportService {
  final VectorStore _vectorStore;
  final Embedder _embedder;
  final String _profileId;
  final Future<void> Function(int dimension)? _onEmbeddingDimensionDetected;
  final Chunker _chunker;
  final Uuid _uuid;

  BookImportService({
    required VectorStore vectorStore,
    required Embedder embedder,
    required String profileId,
    Future<void> Function(int dimension)? onEmbeddingDimensionDetected,
    Chunker? chunker,
    Uuid? uuid,
  })  : _vectorStore = vectorStore,
        _embedder = embedder,
        _profileId = profileId,
        _onEmbeddingDimensionDetected = onEmbeddingDimensionDetected,
        _chunker = chunker ?? const Chunker(),
        _uuid = uuid ?? const Uuid();

  /// Imports a single book file.
  ///
  /// Calls [onProgress] at each stage of the pipeline.
  Future<BookImportResult> importFile(
    PlatformFile file, {
    void Function(BookImportProgress)? onProgress,
  }) async {
    final fileName = file.name;
    final bookId = _uuid.v4();

    void emit(String stage, double fraction, {String? detail}) {
      onProgress?.call(BookImportProgress(
        fileName: fileName,
        stage: stage,
        fraction: fraction,
        detail: detail,
      ));
    }

    try {
      // ── Step 1: Extract text ──────────────────────────────
      emit('extracting', 0.0, detail: 'Reading file...');

      String text;
      if (fileName.endsWith('.pdf')) {
        text = await _extractPdfText(file.path!);
      } else if (fileName.endsWith('.txt')) {
        text = await File(file.path!).readAsString();
      } else {
        throw ArgumentError('Unsupported file format: $fileName');
      }

      if (text.trim().isEmpty) {
        throw FormatException('No extractable text found in $fileName. '
            'Note: scanned PDFs may not contain selectable text.');
      }

      emit('chunking', 0.2, detail: 'Splitting text into chunks...');

      // ── Step 2: Chunk ─────────────────────────────────────
      final chunks = _chunker.chunkBySliding(
        text,
        pageTitle: fileName,
      );

      if (chunks.isEmpty) {
        throw FormatException('Text too short to chunk: $fileName');
      }

      emit('embedding', 0.4, detail: 'Embedding ${chunks.length} chunks...');

      // ── Step 3: Embed ─────────────────────────────────────
      final texts = chunks.map((c) => c.content).toList();
      final result = await _embedder.embedBatch(texts);

      if (result.vectors.isEmpty) {
        throw Exception('Embedding produced no vectors for $fileName');
      }
      await _recordEmbeddingDimension(result.vectors);

      emit('storing', 0.7,
          detail: 'Storing ${result.vectors.length} vectors...');

      // ── Step 4: Store ─────────────────────────────────────
      await _vectorStore.insertChunks(
        chunks,
        result.vectors,
        sourceType: 'book',
        bookId: bookId,
        profileId: _profileId,
      );

      await _vectorStore.upsertBook(
        id: bookId,
        fileName: fileName,
        displayName: _suggestDisplayName(fileName),
        chunkCount: result.vectors.length,
        profileId: _profileId,
      );

      emit('done', 1.0, detail: 'Imported ${result.vectors.length} chunks.');

      return BookImportResult(
        bookId: bookId,
        fileName: fileName,
        chunkCount: result.vectors.length,
      );
    } catch (e) {
      onProgress?.call(BookImportProgress(
        fileName: fileName,
        stage: 'error',
        fraction: 1.0,
        error: e.toString(),
      ));
      rethrow;
    }
  }

  /// Imports multiple book files sequentially.
  Future<List<BookImportResult>> importFiles(
    List<PlatformFile> files, {
    void Function(BookImportProgress)? onProgress,
  }) async {
    final results = <BookImportResult>[];
    for (var i = 0; i < files.length; i++) {
      final result = await importFile(
        files[i],
        onProgress: (progress) {
          onProgress?.call(progress.copyWith(
            detail: '${progress.detail ?? ''} (${i + 1}/${files.length})',
          ));
        },
      );
      results.add(result);
    }
    return results;
  }

  Future<void> _recordEmbeddingDimension(List<List<double>> vectors) async {
    if (_onEmbeddingDimensionDetected == null || vectors.isEmpty) return;
    final dimension = vectors
        .firstWhere(
          (vector) => vector.isNotEmpty,
          orElse: () => const <double>[],
        )
        .length;
    if (dimension > 0) {
      await _onEmbeddingDimensionDetected(dimension);
    }
  }

  /// Extracts text from a PDF file using syncfusion_flutter_pdf.
  Future<String> _extractPdfText(String filePath) async {
    final document =
        PdfDocument(inputBytes: await File(filePath).readAsBytes());
    try {
      final extractor = PdfTextExtractor(document);
      return extractor.extractText();
    } finally {
      document.dispose();
    }
  }

  /// Generates a readable display name from the file name.
  String _suggestDisplayName(String fileName) {
    // Strip extension and replace underscores/hyphens with spaces.
    var name = p.basenameWithoutExtension(fileName);
    name = name.replaceAll(RegExp(r'[_\-]+'), ' ');
    // Capitalize first letter of each word.
    return name.split(' ').map((w) {
      if (w.isEmpty) return w;
      return w[0].toUpperCase() + w.substring(1);
    }).join(' ');
  }
}
