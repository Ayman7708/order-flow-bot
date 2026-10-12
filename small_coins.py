with open('lib/main.dart', 'r', encoding='utf-8') as f:
    src = f.read()

# Replace WATCH list
old_watch = """const List<String> WATCH = [
  'BTCUSDT', 'ETHUSDT', 'SOLUSDT', 'BNBUSDT', 'XRPUSDT',
  'DOGEUSDT', 'ADAUSDT', 'AVAXUSDT', 'LINKUSDT', 'DOTUSDT',
  'MATICUSDT', 'NEARUSDT', 'APTUSDT', 'ARBUSDT', 'OPUSDT',
];"""

new_watch = """const List<String> WATCH = [
  // 🥇 Top small coins (high volume + volatility)
  'SOLUSDT',   // سيولة عالية + تقلب 4%
  'AVAXUSDT',  // تقلب 5%
  'NEARUSDT',  // تقلب 6%
  'SUIUSDT',   // تقلب 7%
  'APTUSDT',   // تقلب 6%
  'INJUSDT',   // تقلب 7%
  'ARBUSDT',   // تقلب 5%
  'OPUSDT',    // تقلب 5%
  'MATICUSDT', // تقلب 5%
  'DOTUSDT',   // تقلب 4%
  'LINKUSDT',  // تقلب 4%
  'ATOMUSDT',  // تقلب 4%
  'FILUSDT',   // تقلب 5%
  'DOGEUSDT',  // تقلب 6%
  'CFXUSDT',   // تقلب 8%
];"""

if old_watch in src:
    src = src.replace(old_watch, new_watch)
    print("✅ Updated WATCH list to small coins")
else:
    print("⚠️ WATCH pattern not found")

# Lower whale threshold for small coins (from $50K to $20K)
with open('lib/main.dart', 'r', encoding='utf-8') as f:
    current = f.read()

old_detector = "final _detector = WhaleDetector(windowSeconds: 10, whaleThreshold: 50000);"
new_detector = "final _detector = WhaleDetector(windowSeconds: 8, whaleThreshold: 20000);"

if old_detector in current:
    current = current.replace(old_detector, new_detector)
    print("✅ Lowered whale threshold: $50K → $20K")

# Also update in _onEvent (event value check)
old_check = "if (e.value > 50000) _totalWhales++;"
new_check = "if (e.value > 20000) _totalWhales++;"

if old_check in current:
    current = current.replace(old_check, new_check)
    print("✅ Updated event whale counter")

# Faster loop for small coins (3s → 2s)
old_loop = "const int LOOP_MS = 3000;"
new_loop = "const int LOOP_MS = 2000;"

if old_loop in current:
    current = current.replace(old_loop, new_loop)
    print("✅ Loop: 3s → 2s")

# Increase max positions per symbol (3 → 5) for scalping
old_max = "const int MAX_POS_PER_SYMBOL = 3;"
new_max = "const int MAX_POS_PER_SYMBOL = 5;"

if old_max in current:
    current = current.replace(old_max, new_max)
    print("✅ Max positions per symbol: 3 → 5")

# Slightly higher leverage for small coins (5 → 7)
old_lev = "const int LEVERAGE = 5;"
new_lev = "const int LEVERAGE = 7;"

if old_lev in current:
    current = current.replace(old_lev, new_lev)
    print("✅ Leverage: 5x → 7x")

with open('lib/main.dart', 'w', encoding='utf-8') as f:
    f.write(current)

# Verify braces
with open('lib/main.dart', 'r', encoding='utf-8') as f:
    final = f.read()
print(f"\nBraces: {final.count('{')} / {final.count('}')}")
print(f"WATCH contains SUIUSDT: {'SUIUSDT' in final}")
print(f"Whale threshold: {'20000' in final}")
