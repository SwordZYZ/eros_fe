"""Read-only evidence collector for the six vendored ML Kit arm64 archives."""
import collections, hashlib, json, mmap, pathlib, struct, sys
ROOT = pathlib.Path(__file__).resolve().parents[2]
PODS = ROOT / 'ios/Pods'

def regions(data):
    magic = struct.unpack_from('>I', data)[0]
    if magic not in (0xcafebabe, 0xcafebabf):
        return [(0, len(data))]
    result = []
    offset = 8
    for _ in range(struct.unpack_from('>I', data, 4)[0]):
        if magic == 0xcafebabf:
            cpu, _, start, size = struct.unpack_from('>iIQQ', data, offset)
            offset += 32
        else:
            cpu, _, start, size, _ = struct.unpack_from('>iIIII', data, offset)
            offset += 20
        if cpu == 0x100000c:
            result.append((start, size))
    return result

def members(data, start, size):
    if data[start:start+8] != b'!<arch>\n':
        return [start]
    offsets = []
    position = start + 8
    while position + 60 <= start + size:
        name = bytes(data[position:position+16]).rstrip()
        length = int(bytes(data[position+48:position+58]).strip())
        body = position + 60
        offsets.append(body + int(name[3:]) if name.startswith(b'#1/') else body)
        position = body + length + length % 2
    return offsets

def platforms(data):
    counts = collections.Counter()
    for start, size in regions(data):
        for offset in members(data, start, size):
            if data[offset:offset+4] != b'\xcf\xfa\xed\xfe':
                continue
            if struct.unpack_from('<I', data, offset + 4)[0] != 0x100000c:
                continue
            commands = struct.unpack_from('<I', data, offset + 16)[0]
            command_offset = offset + 32
            found = False
            for _ in range(commands):
                command, length = struct.unpack_from('<II', data, command_offset)
                if command == 0x32:
                    counts[str(struct.unpack_from('<I', data, command_offset + 8)[0])] += 1
                    found = True
                command_offset += length
            if not found:
                counts['without_LC_BUILD_VERSION'] += 1
    return dict(counts)

label = sys.argv[1]
expected = sys.argv[2] if len(sys.argv) > 2 else None
records = []
for pattern in ('MLKit*/Frameworks/*.framework/*', 'MLImage*/Frameworks/*.framework/*'):
    for path in sorted(PODS.glob(pattern)):
        if not path.is_file() or path.name != path.parent.stem:
            continue
        with path.open('rb') as file:
            digest = hashlib.file_digest(file, 'sha256').hexdigest()
            with mmap.mmap(file.fileno(), 0, access=mmap.ACCESS_READ) as data:
                counts = platforms(data)
        records.append({'binary':str(path.relative_to(PODS)), 'sha256':digest, 'platform_counts':counts})
output = {'state':label, 'expected_platform':expected, 'binaries':records}
(ROOT/'artifacts/ios-step4-20260930'/f'mlkit-{label}.json').write_text(json.dumps(output, indent=2)+'\n')
print(json.dumps({'state':label, 'platform_counts':{r['binary']:r['platform_counts'] for r in records}}, indent=2))
assert len(records) == 6, 'Expected six ML Kit framework binaries'
if expected:
    for record in records:
        actual = set(record['platform_counts']) - {'without_LC_BUILD_VERSION'}
        assert actual <= {expected}, (record['binary'], actual, expected)
        assert actual or record['platform_counts'].get('without_LC_BUILD_VERSION'), 'No arm64 evidence'
