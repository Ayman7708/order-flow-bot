# Read current workflow
with open('.github/workflows/build.yml', 'r', encoding='utf-8') as f:
    src = f.read()

# Find the line that adds the service declaration via sed
old_line = """          # 2. Add background service inside <application
          # Replace closing </application> with service + closing
          sed -i 's|</application>|<service android:name="id.flutter.flutter_background_service.BackgroundService" android:foregroundServiceType="dataSync" android:exported="false" android:stopWithTask="false" /></application>|' "$MANIFEST"
"""

new_line = """          # NOTE: The library flutter_background_service_android auto-registers
          # its <service> declaration via its own AndroidManifest. We do NOT
          # add it here to avoid duplicate declaration errors.
"""

if old_line in src:
    src = src.replace(old_line, new_line)
    print("✅ Removed manual service declaration")
else:
    print("⚠️ Pattern not found - trying alternative")
    # Try simpler version without comments
    import re
    pattern = re.compile(r'\s*# 2\. Add background service.*?sed -i.*?BackgroundService.*?\n', re.DOTALL)
    if pattern.search(src):
        src = pattern.sub('\n          # Service auto-registered by library\n', src)
        print("✅ Removed via regex")

with open('.github/workflows/build.yml', 'w', encoding='utf-8') as f:
    f.write(src)

# Verify
with open('.github/workflows/build.yml', 'r', encoding='utf-8') as f:
    final = f.read()

has_bg_service = 'BackgroundService' in final
has_sed_declaration = 'flutter_background_service.BackgroundService' in final

print(f"\n📊 Results:")
print(f"  - Manual declaration removed: {not has_sed_declaration}")
print(f"  - Workflow intact: {len(final) > 3000}")
