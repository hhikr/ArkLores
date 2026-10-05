// Makes assets/fonts/LXGWWenKaiScreen.ttf: the LXGW WenKai Screen v1.522 TTF
// (https://github.com/lxgw/LxgwWenKai-Screen/releases, OFL) cut down to the
// characters the reader can show. The full font is 25.7 MB; Flutter reads and
// shapes the whole file, which made the reader stutter on a phone.
//
//   npm install subset-font
//   node tools/subset_reading_font.js <full.ttf> <chars.txt> assets/fonts/LXGWWenKaiScreen.ttf
//
// <chars.txt> holds every character of the knowledge base's story lines, names
// and synopses (one line, any order); GB2312, ASCII and the usual punctuation
// are added here. A character outside the subset falls back to the system font.
const fs = require('fs');
const subsetFont = require('subset-font');

(async () => {
  const [full, chars, out] = process.argv.slice(2);
  if (!full || !chars || !out) {
    console.error('usage: node subset_reading_font.js <full.ttf> <chars.txt> <out.ttf>');
    process.exit(64);
  }
  let text = fs.readFileSync(chars, 'utf8');
  const decoder = new TextDecoder('gbk');
  for (let hi = 0xa1; hi <= 0xf7; hi++) {
    const bytes = [];
    for (let lo = 0xa1; lo <= 0xfe; lo++) bytes.push(hi, lo);
    text += decoder.decode(new Uint8Array(bytes)).replace(/\uFFFD/g, '');
  }
  for (let c = 0x20; c < 0x7f; c++) text += String.fromCharCode(c);
  text += '\u00a0\u2014\u2018\u2019\u201c\u201d\u2026\u3000';
  const subset = await subsetFont(fs.readFileSync(full), text, { targetFormat: 'sfnt' });
  fs.writeFileSync(out, subset);
  console.log(`${new Set([...text]).size} characters, ${subset.length} bytes`);
})();
