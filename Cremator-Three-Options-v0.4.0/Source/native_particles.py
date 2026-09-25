"""Minimal, fingerprint-locked original-resource experiment; no borrowed effects."""
from pathlib import Path
import hashlib
import math
import struct
import sys

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / 'analysis'))
from particle_format import decode

RESOURCE = 0xa4f17daba8ecd8e5
PARTICLES = 0xa8193123526fad64
ARCHIVE = 'df16f5c644edc2b1.patch_0'
SOURCE = ROOT / 'analysis/native_effects/cremator-df16f5c644edc2b1.main.bin'
SOURCE_SHA = 'a1cf46aa69383df2ef2804d51dc4448f80bb2348cb62ba1857b2e8af5f9d409f'
FACTOR = 1.4

def patch_particle():
    original = SOURCE.read_bytes()
    assert hashlib.sha256(original).hexdigest() == SOURCE_SHA
    systems = decode(original)
    modified = bytearray(original)
    changes = []
    def change(system, offset, fmt, value, field):
        old = struct.unpack_from(fmt, original, offset)[0]
        struct.pack_into(fmt, modified, offset, value)
        changes.append({'system': system['index'], 'offset': offset, 'field': field,
                        'old': old, 'new': struct.unpack_from(fmt, modified, offset)[0]})
    # Systems retaining the original collision-result handler (opcode 32).
    # Its event path is documented in analysis/particle_engine/collision.txt.
    selected = [s for s in systems if any(x['op'] == 32 for x in s['sim'])]
    assert [s['index'] for s in selected] == [0, 1, 2, 3, 4, 8, 12, 13]
    for s in selected:
        for i, old in enumerate(s['lifetime']):
            change(s, s['lifetime_offset'] + i * 4, '<f', old * FACTOR, 'lifetime_' + ['min', 'max'][i])
        # Headroom only: do not increase the original emission rate or burst counts.
        change(s, s['offset'], '<I', math.ceil(s['capacity'] * FACTOR), 'capacity')
        for instruction in s['sim']:
            if instruction['op'] == 28:
                change(s, instruction['offset'] + 16, '<f', instruction['drag'] / FACTOR, 'drag_scale')
    decode(modified)  # Revalidate boundaries and counts after the fixed-width writes.
    report = {'source_sha256': SOURCE_SHA, 'resource': hex(RESOURCE), 'archive': ARCHIVE,
              'particle_version': '0x73', 'factor': FACTOR, 'target_range_m': 35,
              'range_measured': False, 'modified_sha256': hashlib.sha256(modified).hexdigest(),
              'changes': changes, 'changed_bytes': sum(a != b for a, b in zip(original, modified))}
    return bytes(modified), report

def make_patch():
    # Reuse the established upstream archive writer with a local module instance.
    import importlib.util
    path = ROOT.parent / 'research/upstream/BingusSharedLoader/scripts/archive.py'
    spec = importlib.util.spec_from_file_location('particle_archive_writer', path)
    writer = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(writer)
    assert writer.resource_hash('particles') == PARTICLES
    writer.TYPE = PARTICLES
    data, report = patch_particle()
    archive = bytearray(writer.make_archive({RESOURCE: data}))
    # Match the original particle type's secondary alignment (empty sidecars).
    struct.pack_into('<I', archive, 100, 64)
    struct.pack_into('<I', archive, 104 + 72, 64)
    return bytes(archive), report
