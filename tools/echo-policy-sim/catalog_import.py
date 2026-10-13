"""Parse the generated PerkDatabase as data, never execute client Lua.

Generated catalog and receipt must stay under this checkout's ignored build/.
No MPQ content is bundled or published by this tool.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re

FIELDS = ('maxStack', 'classMask', 'minLevel', 'quality', 'groupId', 'requiredSpell')
STRING = r'"(?:[^"\\]|\\.)*"'
ROW = re.compile(r'\s*\[(\d+)\]\s*=\s*\{\s*' +
    ''.join(rf'{name}\s*=\s*(\d+)\s*,\s*' for name in FIELDS) +
    rf'comment\s*=\s*({STRING})\s*(?:,\s*families\s*=\s*\{{([^{{}}]*)\}}\s*)?\}}\s*,?\s*')


def parse(text):
    start = re.search(r'^ProjectEbonhold\.PerkDatabase\s*=\s*\{\s*$', text, re.M)
    if not start:
        raise ValueError('PerkDatabase declaration not found')
    rows = {}
    closed = False
    for line in text[start.end():].splitlines():
        if line.strip() == '}':
            closed = True
            break
        if not line.strip() or line.lstrip().startswith('--'):
            continue
        end_after_row = line.rstrip().endswith(',}')
        if end_after_row:
            line = line.rstrip()[:-1]
        match = ROW.fullmatch(line)
        if not match:
            raise ValueError('Unsupported catalog row; refusing partial import')
        spell = int(match[1])
        if spell <= 0 or spell in rows:
            raise ValueError('Duplicate or invalid spell ID')
        row = dict(zip(FIELDS, map(int, match.group(*range(2, 8)))))
        role_text = match[9] or ''
        if role_text.strip() and not re.fullmatch(rf'\s*{STRING}(?:\s*,\s*{STRING})*\s*,?\s*', role_text):
            raise ValueError('Invalid role list')
        roles = re.findall(STRING, role_text)
        if re.sub(STRING, '', role_text).strip(' ,\t'):
            raise ValueError('Unsupported role expression')
        row['roles'] = [json.loads(s) for s in roles]
        if len(set(row['roles'])) != len(row['roles']) or any(not s for s in row['roles']):
            raise ValueError('Duplicate or empty role')
        if row['maxStack'] < 1 or not 1 <= row['minLevel'] <= 80 or row['quality'] > 4:
            raise ValueError('Invalid catalog bounds')
        rows[spell] = row
        if end_after_row:
            closed = True
            break
    if not closed or not rows:
        raise ValueError('Incomplete catalog')
    return rows


def render(rows, source_hash):
    lines = ['-- LOCAL reference facts; do not publish this generated file.',
             'return {schema="local-perk-catalog/v1",sourceSha256="'+source_hash+'",rows={']
    for spell, row in sorted(rows.items()):
        fields = ','.join(f'{name}={row[name]}' for name in FIELDS)
        roles = ','.join(json.dumps(s, ensure_ascii=True) for s in row['roles'])
        # Role labels are data; escape-free ASCII avoids Lua/JSON escape ambiguity.
        if any(not re.fullmatch(r'[A-Za-z ]+', s) for s in row['roles']):
            raise ValueError('Unsupported role characters')
        lines.append(f'[{spell}]={{{fields},roles={{{roles}}}}},')
    lines.append('}}')
    return '\n'.join(lines)+'\n'


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('source', type=Path)
    p.add_argument('--output', type=Path, default=Path('build/catalog/catalog.lua'))
    args = p.parse_args()
    root = Path('build').resolve()
    output = args.output.resolve()
    if not output.is_relative_to(root):
        p.error('Private reference output must be inside build/')
    raw = args.source.read_bytes()
    source_hash = hashlib.sha256(raw).hexdigest()
    rows = parse(raw.decode('utf-8-sig'))
    rendered = render(rows, source_hash)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(rendered, encoding='utf-8', newline='\n')
    receipt = dict(schema='local-perk-catalog/v1', source=str(args.source.resolve()),
        source_sha256=source_hash, output_sha256=hashlib.sha256(output.read_bytes()).hexdigest(),
        entries=len(rows), groups=len({r['groupId'] for r in rows.values()}),
        roles=sorted({s for r in rows.values() for s in r['roles']}),
        classification='STATIC_CLIENT_FACTS; not server draw probabilities')
    output.with_suffix('.json').write_text(json.dumps(receipt, indent=2)+'\n', encoding='utf-8')
    print(json.dumps(receipt, indent=2))


if __name__ == '__main__':
    main()
