from pathlib import Path
import re, json
root=Path(__file__).resolve().parents[1]
modules=list((root/'ServerScriptService/SpicyFeatures').glob('*.luau'))
expect=['WalletService','PaintballService','SkyLiftService','PoolZoneService','AlleyPatrolService','RoofRouteService','RoofRouteData']
assert sorted(p.stem for p in modules)==sorted(expect),[p.stem for p in modules]
for f in modules:
    s=f.read_text(encoding='utf-8')
    assert 'return ' in s, f.name
    assert s.count('(')==s.count(')'), f.name
    assert s.count('{')==s.count('}'), f.name
    assert 'HttpService' not in s, f.name
    print('STATIC OK',f.name,len(s),'bytes')
b=(root/'ServerScriptService/Example_Manual_Bootstrap.server.luau').read_text()
assert 'local ENABLE = false' in b and 'if not ENABLE then return end' in b
s=json.loads((root/'STATUS.json').read_text())
assert s['runtime_tested'] is False
print('PASS: files present, simple lexical checks, disabled bootstrap, explicit untested status.')
