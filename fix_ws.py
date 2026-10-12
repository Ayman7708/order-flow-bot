with open('lib/ws_service.dart', 'r', encoding='utf-8') as f:
    src = f.read()

# Change from /stream?streams= format to /ws/ format (single stream = more reliable)
old_url = "final url = 'wss://fstream.binance.com/stream?streams=\$streams';"
new_url = "final url = 'wss://fstream.binance.com/stream?streams=\$streams';"

# The URL is actually correct. Let's add better debugging instead
old_msg = """  void _onMessage(dynamic data) {
    try {
      final raw = data is String ? data : utf8.decode(data);
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final d = json['data'] as Map<String, dynamic>?;
      if (d == null) return;"""

new_msg = """  void _onMessage(dynamic data) {
    try {
      final raw = data is String ? data : utf8.decode(data);
      debugPrint('WS RAW: ${raw.substring(0, raw.length > 200 ? 200 : raw.length)}');
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final d = json['data'] as Map<String, dynamic>?;
      if (d == null) {
        debugPrint('No data field');
        return;
      }"""

if old_msg in src:
    src = src.replace(old_msg, new_msg)
    print("✅ Added WS debugging")
else:
    print("⚠️ Pattern not found")

with open('lib/ws_service.dart', 'w', encoding='utf-8') as f:
    f.write(src)

# Verify
with open('lib/ws_service.dart', 'r', encoding='utf-8') as f:
    final = f.read()
print(f"Braces: {final.count('{')} / {final.count('}')}")
