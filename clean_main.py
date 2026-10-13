with open('lib/main.dart', 'r', encoding='utf-8') as f:
    src = f.read()

# Remove import
src = src.replace("import 'bg_service.dart';\n", "")
src = src.replace("import 'package:connectivity_plus/connectivity_plus.dart';\n", "")

# Remove connectivity subscription references
src = src.replace("  bool _hasInternet = true;\n", "")
src = src.replace("  StreamSubscription? _connSub;\n", "")

# Remove the connectivity listener block
import re
pattern1 = re.compile(r"// Init background service\n.*?initBackgroundService\(\);", re.DOTALL)
src = pattern1.sub("", src)

pattern2 = re.compile(r"// Listen to connectivity\n.*?\}\);\n", re.DOTALL)
src = pattern2.sub("", src)

# Remove _connSub?.cancel();
src = src.replace("    _connSub?.cancel();\n", "")

# Remove auto-init in toggle
pattern3 = re.compile(r"// Init and start background service.*?\} catch \(e\) \{\n        debugPrint\('BG service start error: \$e'\);\n      \}", re.DOTALL)
src = pattern3.sub("", src)

src = src.replace("await startBgService();\n", "")
src = src.replace("await stopBgService();\n", "")

# Remove initBackgroundService call from _loadState (if any)
src = src.replace("    initBackgroundService();\n", "")

with open('lib/main.dart', 'w', encoding='utf-8') as f:
    f.write(src)

# Verify
with open('lib/main.dart', 'r', encoding='utf-8') as f:
    final = f.read()

print("=== Cleanup Result ===")
print(f"bg_service references: {final.count('bg_service')}")
print(f"connectivity references: {final.count('connectivity')}")
print(f"_connSub references: {final.count('_connSub')}")
print(f"_hasInternet references: {final.count('_hasInternet')}")
print(f"startBgService: {final.count('startBgService')}")
print(f"initBackgroundService: {final.count('initBackgroundService')}")
print(f"Braces: {final.count('{')} / {final.count('}')}")
