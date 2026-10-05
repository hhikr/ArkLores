# Reading font

`LXGWWenKaiScreen.ttf` is LXGW WenKai Screen v1.522 (霞鹜文楷 屏幕阅读版, SIL Open Font
License 1.1, see `OFL.txt`), **cut down to the characters the reader can show** (about 8,300:
the knowledge base's story text, GB2312, ASCII, punctuation) with `tools/subset_reading_font.js`.
The full font is 25.7 MB and made the reader stutter; a character outside the subset is drawn
in the system font. Regenerate it from the original release when the knowledge base gains
characters. `lxgw-wenkai/` holds the web fonts of the wiki reader.
