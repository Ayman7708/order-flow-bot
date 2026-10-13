with open('lib/main.dart', 'r', encoding='utf-8') as f:
    src = f.read()

checks = []

# 1) Reduce RISK_PCT (smaller positions)
src = src.replace(
    'const double RISK_PCT = 0.01;',
    'const double RISK_PCT = 0.003;'  # 1% → 0.3%
)
checks.append(('Risk 0.3%', 'RISK_PCT = 0.003' in src))

# 2) Increase LEVERAGE (smaller margin for same position)
src = src.replace(
    'const int LEVERAGE = 7;',
    'const int LEVERAGE = 20;'  # 7x → 20x
)
checks.append(('Leverage 20x', 'LEVERAGE = 20' in src))

# 3) Reduce MAX_POS_PER_SYMBOL (less positions per coin)
src = src.replace(
    'const int MAX_POS_PER_SYMBOL = 5;',
    'const int MAX_POS_PER_SYMBOL = 2;'  # 5 → 2
)
checks.append(('Max 2/symbol', 'MAX_POS_PER_SYMBOL = 2' in src))

# 4) Add MAX_TOTAL_MARGIN_PCT constant
old_const = 'const int LEVERAGE = 20;'
new_const = 'const int LEVERAGE = 20;\nconst double MAX_TOTAL_MARGIN_PCT = 0.25; // max 25% of balance in open margins'
if 'MAX_TOTAL_MARGIN_PCT' not in src:
    src = src.replace(old_const, new_const)
    checks.append(('Max margin const', 'MAX_TOTAL_MARGIN_PCT' in src))
else:
    checks.append(('Max margin const', True))

# 5) Add total margin check in _lookForEntries
old_check = """  void _lookForEntries() {
    for (final sym in WATCH) {
      final snap = _snapshots[sym];
      if (snap == null) continue;

      final current = _positions[sym]?.length ?? 0;
      if (current >= MAX_POS_PER_SYMBOL) continue;"""

new_check = """  double get _totalMarginLocked {
    double t = 0;
    for (final list in _positions.values) {
      for (final p in list) t += p.margin;
    }
    return t;
  }

  bool get _hasRoomForMore {
    if (_initialBalance <= 0) return false;
    final totalExposure = _totalMarginLocked + _balance;
    if (totalExposure <= 0) return false;
    final marginPct = _totalMarginLocked / (_totalMarginLocked + _balance);
    return marginPct < MAX_TOTAL_MARGIN_PCT;
  }

  void _lookForEntries() {
    // Stop opening if total margin > MAX_TOTAL_MARGIN_PCT
    if (!_hasRoomForMore) return;

    for (final sym in WATCH) {
      final snap = _snapshots[sym];
      if (snap == null) continue;

      final current = _positions[sym]?.length ?? 0;
      if (current >= MAX_POS_PER_SYMBOL) continue;"""

if old_check in src:
    src = src.replace(old_check, new_check)
    checks.append(('Max margin check', '_hasRoomForMore' in src))
else:
    checks.append(('Max margin check', False))

# 6) Also check inside loop after each open
old_after_open = """      _openPosition(sym, sig, margin, snap);
    }
  }"""
new_after_open = """      _openPosition(sym, sig, margin, snap);
      // Check again after opening
      if (!_hasRoomForMore) break;
    }
  }"""
if old_after_open in src:
    src = src.replace(old_after_open, new_after_open)
    checks.append(('Re-check room', 'if (!_hasRoomForMore) break;' in src))
else:
    checks.append(('Re-check room', False))

# 7) Reduce calcMargin max from 15% to 3% of balance
src = src.replace(
    'final maxMargin = balance * 0.15;',
    'final maxMargin = balance * 0.03;'
)
checks.append(('Margin max 3%', 'balance * 0.03' in src))

# 8) Add Close All button
old_reset_btn = """          IconButton(
            icon: const Icon(Icons.restart_alt, color: Color(0xFFEF4444)),
            onPressed: _resetAll,
          ),"""
new_reset_btn = """          IconButton(
            icon: const Icon(Icons.close_fullscreen, color: Color(0xFFF59E0B)),
            onPressed: _closeAll,
            tooltip: 'إغلاق الكل',
          ),
          IconButton(
            icon: const Icon(Icons.restart_alt, color: Color(0xFFEF4444)),
            onPressed: _resetAll,
          ),"""
if old_reset_btn in src:
    src = src.replace(old_reset_btn, new_reset_btn)
    checks.append(('Close All button', '_closeAll' in src))
else:
    checks.append(('Close All button', False))

# 9) Add _closeAll method
old_manual_close = "  void _manualClose(String sym, int idx) {"
new_manual_close = """  void _closeAll() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF131A26),
        title: const Text('إغلاق كل الصفقات', style: TextStyle(color: Colors.white)),
        content: Text('سيتم إغلاق ${_positions.values.fold<int>(0, (s, l) => s + l.length)} صفقة. متأكد؟',
            style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                for (final sym in _positions.keys.toList()) {
                  final list = _positions[sym]!;
                  final price = _prices[sym] ?? 0;
                  for (final p in list) {
                    final pnl = price > 0 ? p.pnl(price) : 0.0;
                    _balance += p.margin + pnl;
                  }
                  _positions.remove(sym);
                }
              });
              _saveState();
            },
            child: const Text('نعم', style: TextStyle(color: Color(0xFFEF4444))),
          ),
        ],
      ),
    );
  }

  void _manualClose(String sym, int idx) {"""

if old_manual_close in src and 'void _closeAll()' not in src:
    src = src.replace(old_manual_close, new_manual_close)
    checks.append(('Close All method', 'void _closeAll()' in src))
else:
    checks.append(('Close All method', 'void _closeAll()' in src))

with open('lib/main.dart', 'w', encoding='utf-8') as f:
    f.write(src)

print('=== Fix Results ===')
for name, ok in checks:
    print(('✅' if ok else '❌') + ' ' + name)
print('===================')

# Verify braces
with open('lib/main.dart', 'r', encoding='utf-8') as f:
    final = f.read()
print(f"\nBraces: {final.count('{')} / {final.count('}')}")
