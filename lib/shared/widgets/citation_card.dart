import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/theme_provider.dart';

/// Source type for a citation.
enum CitationSourceType {
  wiki('Wiki'),
  book('Book');

  final String label;
  const CitationSourceType(this.label);
}

/// A collapsible citation card that displays a referenced text passage
/// with its source attribution.
///
/// Visual distinction:
/// - 🌐 Wiki source → theme accent color
/// - 📚 Book source → amber/brown color
///
/// Clicking the citation opens the card to reveal the full source text
/// and a "View in Wiki" button (Wiki sources only).
class CitationCard extends ConsumerStatefulWidget {
  final String title;
  final String content;
  final CitationSourceType sourceType;
  final String? sourceUrl;
  final String? sourceDetail; // e.g. "PRTS Wiki · Chapter 3" or "Book · filename"

  const CitationCard({
    super.key,
    required this.title,
    required this.content,
    required this.sourceType,
    this.sourceUrl,
    this.sourceDetail,
  });

  @override
  ConsumerState<CitationCard> createState() => _CitationCardState();
}

class _CitationCardState extends ConsumerState<CitationCard>
    with SingleTickerProviderStateMixin {
  bool _isExpanded = false;
  late AnimationController _animController;
  late Animation<double> _heightFactor;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _heightFactor = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _animController.forward();
      } else {
        _animController.reverse();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);

    final badgeColor = widget.sourceType == CitationSourceType.wiki
        ? theme.wikiBadgeColor
        : theme.bookBadgeColor;

    final badgeIcon = widget.sourceType == CitationSourceType.wiki
        ? '🌐'
        : '📚';

    final badgeLabel = widget.sourceType == CitationSourceType.wiki
        ? 'Wiki'
        : 'Book';

    return GestureDetector(
      onTap: _toggle,
      child: AnimatedBuilder(
        animation: _heightFactor,
        builder: (context, child) {
          return Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              color: theme.cardSurface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: badgeColor.withValues(alpha: 0.4),
                width: 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Header (always visible) ──────────────────
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Text(
                        badgeIcon,
                        style: const TextStyle(fontSize: 16),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: badgeColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          badgeLabel,
                          style: theme.bodyFont.copyWith(
                            color: badgeColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.title,
                          style: theme.titleFont.copyWith(
                            fontSize: 14,
                            color: theme.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Icon(
                        _isExpanded
                            ? Icons.expand_less_rounded
                            : Icons.expand_more_rounded,
                        color: theme.textSecondary,
                        size: 20,
                      ),
                    ],
                  ),
                ),

                // ── Expandable content ───────────────────────
                ClipRect(
                  child: Align(
                    heightFactor: _heightFactor.value,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Divider(height: 1),
                          const SizedBox(height: 10),
                          // Source detail.
                          if (widget.sourceDetail != null) ...[
                            Text(
                              widget.sourceDetail!,
                              style: theme.bodyFont.copyWith(
                                color: badgeColor,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 6),
                          ],
                          // Quoted content.
                          Text(
                            widget.content,
                            style: theme.bodyFont.copyWith(
                              color: theme.textPrimary,
                              fontSize: 13,
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 10),
                          // "View in Wiki" button (Wiki only).
                          if (widget.sourceType == CitationSourceType.wiki &&
                              widget.sourceUrl != null &&
                              widget.sourceUrl!.isNotEmpty)
                            InkWell(
                              onTap: () {
                                // TODO(v0.7): Navigate to Wiki WebView with the URL.
                                // For now, the button is a visual placeholder.
                              },
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.open_in_new_rounded,
                                    size: 14,
                                    color: theme.accentPrimary,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'View in Wiki',
                                    style: theme.bodyFont.copyWith(
                                      color: theme.accentPrimary,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// A simplified expand/collapse widget that animates its child height.
///
/// Flutter's [AnimatedCrossFade] doesn't provide height-only animation
/// control, so we use this lightweight wrapper.
class AnimatedBuilder extends AnimatedWidget {
  final Widget Function(BuildContext context, Widget? child) builder;

  const AnimatedBuilder({
    super.key,
    required super.listenable,
    required this.builder,
  });

  @override
  Widget build(BuildContext context) {
    return builder(context, null);
  }
}
