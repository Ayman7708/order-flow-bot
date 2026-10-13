with open('lib/flow_engine.dart', 'r', encoding='utf-8') as f:
    src = f.read()

# Reduce max margin from 15% to 3%
old = 'final maxMargin = balance * 0.15;'
new = 'final maxMargin = balance * 0.03;'

if old in src:
    src = src.replace(old, new)
    print("✅ Flow engine margin 15% → 3%")
else:
    print("❌ Pattern not found in flow_engine.dart")
    # Show current values
    import re
    for m in re.finditer(r'balance \* [0-9.]+', src):
        print(f"  Found: {m.group(0)}")

with open('lib/flow_engine.dart', 'w', encoding='utf-8') as f:
    f.write(src)

# Verify
with open('lib/flow_engine.dart', 'r', encoding='utf-8') as f:
    final = f.read()
print(f"Braces: {final.count('{')} / {final.count('}')}")
