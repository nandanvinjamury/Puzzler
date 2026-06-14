"""Curate ~60 approachable puzzles from a slice of the public Lichess puzzle DB.
Run: python tool/fetch_fallback_puzzles.py"""
import io, json, os, urllib.request
import zstandard as zstd

URL = "https://database.lichess.org/lichess_db_puzzle.csv.zst"
WANT = 60

req = urllib.request.Request(URL, headers={"Range": "bytes=0-8000000"})
comp = urllib.request.urlopen(req).read()
print(f"downloaded {len(comp)} compressed bytes")

# Decompress incrementally; stop when the truncated slice runs out.
dctx = zstd.ZstdDecompressor()
reader = dctx.stream_reader(io.BytesIO(comp))
out = bytearray()
try:
    while len(out) < 60_000_000:
        chunk = reader.read(1 << 20)
        if not chunk:
            break
        out += chunk
except zstd.ZstdError:
    pass  # truncated final frame — keep what we decompressed
text = out.decode("utf-8", errors="ignore")
lines = text.split("\n")
print(f"decompressed {len(lines)} lines")

# CSV: PuzzleId,FEN,Moves,Rating,RatingDeviation,Popularity,NbPlays,Themes,GameUrl,OpeningTags
picked = []
for line in lines[1:]:
    f = line.split(",")
    if len(f) < 8:
        continue
    pid, fen, moves, rating, _dev, popularity, nbplays, themes = f[:8]
    mv = moves.strip().split(" ")
    try:
        r = int(rating); pop = int(popularity); plays = int(nbplays)
    except ValueError:
        continue
    if not pid or not fen or len(mv) < 2 or len(mv) > 6:
        continue
    if r < 800 or r > 1700 or plays < 30 or pop < 50:
        continue
    if "veryLong" in themes or "long" in themes:
        continue
    picked.append({
        "id": pid,
        "fen": fen,
        "moves": " ".join(mv),
        "rating": r,
        "themes": themes.strip().split(" ")[:6],
    })
    if len(picked) >= WANT:
        break

os.makedirs("assets", exist_ok=True)
with open("assets/fallback_puzzles.json", "w") as fp:
    json.dump(picked, fp)
print(f"wrote {len(picked)} puzzles")
if picked:
    print("sample:", json.dumps(picked[0]))
