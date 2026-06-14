// Downloads a slice of the public Lichess puzzle DB (.zst) and curates a small
// set of approachable puzzles into assets/fallback_puzzles.json.
// Run: node tool/fetch_fallback_puzzles.mjs
import zlib from 'node:zlib';
import { writeFileSync, mkdirSync } from 'node:fs';

const URL = 'https://database.lichess.org/lichess_db_puzzle.csv.zst';
const WANT = 60;

const res = await fetch(URL, { headers: { Range: 'bytes=0-16000000' } });
const buf = Buffer.from(await res.arrayBuffer());
console.error(`downloaded ${buf.length} compressed bytes (HTTP ${res.status})`);

// Decompress as much as possible from the truncated slice. Do NOT call end()
// (which would error on the incomplete final frame and drop buffered output);
// instead write, let it emit, then stop.
const chunks = [];
const dec = zlib.createZstdDecompress();
dec.on('data', (d) => chunks.push(d));
dec.on('error', () => {});
dec.write(buf);
await new Promise((resolve) => setTimeout(resolve, 2500));
dec.destroy();
const text = Buffer.concat(chunks).toString('utf8');
const lines = text.split('\n');
console.error(`decompressed ${lines.length} lines`);

// CSV: PuzzleId,FEN,Moves,Rating,RatingDeviation,Popularity,NbPlays,Themes,GameUrl,OpeningTags
const picked = [];
for (let i = 1; i < lines.length && picked.length < WANT; i++) {
  const f = lines[i].split(',');
  if (f.length < 8) continue;
  const [id, fen, moves, rating, , popularity, nbPlays, themes] = f;
  const mv = moves.trim().split(' ');
  const r = parseInt(rating, 10);
  if (!id || !fen || mv.length < 2) continue;
  if (Number.isNaN(r) || r < 800 || r > 1700) continue;
  if (mv.length > 6) continue; // 1..2 solver moves, keep it short for an alarm
  if (parseInt(nbPlays, 10) < 30) continue;
  if (parseInt(popularity, 10) < 50) continue;
  if (themes.includes('veryLong') || themes.includes('long')) continue;
  picked.push({
    id,
    fen,
    moves: mv.join(' '),
    rating: r,
    themes: themes.trim().split(' ').slice(0, 6),
  });
}

mkdirSync('assets', { recursive: true });
writeFileSync('assets/fallback_puzzles.json', JSON.stringify(picked, null, 0));
console.error(`wrote ${picked.length} puzzles to assets/fallback_puzzles.json`);
if (picked.length) console.error('sample:', JSON.stringify(picked[0]));
