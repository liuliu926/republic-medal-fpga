"""Build a validated, 8.3-named staging catalog from the supplied PPT assets.

This is preparation on the PC. It does not implement FPGA FAT32 access and
must not be copied over an existing TF card layout without integration work.
"""
import hashlib
import json
import re
import shutil
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'assets_ppt_720p'
DEST = ROOT / 'prepared_resource_catalog'
CANVAS_W, CANVAS_H = 1280, 720
SHORT_NAME = re.compile(r'^[A-Z0-9]{1,8}\.BMP$')


def inspect_bmp(path):
    with path.open('rb') as f:
        h = f.read(54)
    if len(h) != 54 or h[:2] != b'BM':
        raise ValueError(f'{path}: not a BMP')
    size, offset = struct.unpack_from('<I4xI', h, 2)
    dib, width, height, planes, bits, compression = struct.unpack_from('<IiiHHI', h, 14)
    if dib < 40 or width <= 0 or height == 0 or planes != 1 or bits != 24 or compression != 0:
        raise ValueError(f'{path}: expected uncompressed 24-bit BMP')
    stride = ((width * 3 + 3) // 4) * 4
    if size != path.stat().st_size or offset + stride * abs(height) > size:
        raise ValueError(f'{path}: truncated or inconsistent BMP')
    return {'width': width, 'height': abs(height), 'bottom_up': height > 0,
            'row_stride_bytes': stride, 'pixel_offset_bytes': offset, 'bytes': size}


def sha256(path):
    digest = hashlib.sha256()
    with path.open('rb') as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


def main():
    assets = json.loads((SOURCE / 'asset_index.json').read_text(encoding='utf-8'))
    text_index = json.loads((SOURCE / 'bilingual_text_index.json').read_text(encoding='utf-8'))
    entries, used, pages, portraits = [], set(), {}, []
    def stage(source_name, name, kind):
        if not SHORT_NAME.fullmatch(name) or name in used:
            raise ValueError(f'duplicate or invalid 8.3 filename: {name}')
        used.add(name)
        source = SOURCE / source_name
        meta = inspect_bmp(source)
        if not meta['bottom_up']:
            raise ValueError(f'{source}: top-down BMP not supported by current pilot')
        digest = sha256(source)
        entries.append({'file': name, 'source': source_name, 'kind': kind, 'sha256': digest, **meta})
        return meta

    for a in assets['assets']:
        meta = stage(a['file'], a['file'].upper(), a['type'])
        if meta['width'] != a['width'] or meta['height'] != a['height']:
            raise ValueError(f"size mismatch: {a['file']}")
        if a['type'] == 'page_background':
            pages[a['slide']] = {'slide': a['slide'], 'person': a['person'],
                                 'page': a['page'], 'background': a['file'].upper(), 'layers': []}
        elif a['type'] == 'portrait_layer':
            portraits.append({'person': a['person'], 'file': a['file'].upper()})
        else:
            raise ValueError(f"unknown asset type {a['type']}")

    for page in text_index['pages']:
        slide = page['slide']
        if slide not in pages or pages[slide]['person'] != page['person_zh'] or pages[slide]['page'] != page['page']:
            raise ValueError(f'page mapping mismatch: {slide}')
        for i, layer in enumerate(page['layers'], start=1):
            if i > 99:
                raise ValueError('too many layers for short filename')
            names = {}
            for language, suffix in (('zh', 'C'), ('en', 'E')):
                name = f'T{slide:03}{i:02}{suffix}.BMP'
                meta = stage(layer[f'{language}_file'], name, f'text_{language}')
                if (meta['width'], meta['height']) != (layer['width'], layer['height']):
                    raise ValueError(f'{name}: layer size mismatch')
                names[language] = name
            x, y, width, height = (layer[k] for k in ('x', 'y', 'width', 'height'))
            if x < 0 or y < 0 or x + width > CANVAS_W or y + height > CANVAS_H:
                raise ValueError(f'{slide} {i}: layer outside 720p canvas')
            pages[slide]['layers'].append({'id': layer['layer'], 'files': names,
                'x': x, 'y': y, 'width': width, 'height': height,
                'key4_reveal_step': layer['key4_reveal_step']})

    if len(pages) != 53 or len(portraits) != 13 or len(entries) != 462:
        raise ValueError(f'unexpected counts: {len(pages)} pages, {len(portraits)} portraits, {len(entries)} files')
    DEST.mkdir(exist_ok=True)
    files = DEST / 'files'
    files.mkdir(exist_ok=True)
    for entry in entries:
        target = files / entry['file']
        if not target.exists() or sha256(target) != entry['sha256']:
            shutil.copyfile(SOURCE / entry['source'], target)
        if sha256(target) != entry['sha256']:
            raise ValueError(f'copy verification failed: {target}')
    catalog = {'status': 'PC staging only; FPGA FAT32 lookup and compositor are not integrated',
               'canvas': [CANVAS_W, CANVAS_H], 'portrait_order': portraits,
               'pages': [pages[i] for i in sorted(pages)], 'assets': entries}
    (DEST / 'catalog.json').write_text(json.dumps(catalog, ensure_ascii=False, indent=2), encoding='utf-8')
    (DEST / 'README.md').write_text(
        '# 素材预备目录\n\n53 页背景、13 张头像和 396 个中英文字幕图层。'
        '文件均为 24 位 BMP、采用 8.3 短文件名，索引见 catalog.json。\n\n'
        '**这只是电脑端预备包，尚不能用于当前 FPGA 位流；不要直接复制到 TF 卡。**'
        '正式读取需要实现 FAT32 文件查找、页面资源调度、字幕叠加及渐显。'
        '英文内容仍需人工核校。\n', encoding='utf-8')
    print(f'OK: {len(pages)} pages, {len(portraits)} portraits, {len(entries)} validated and hash-checked BMPs')
    print(f'Catalog: {DEST / "catalog.json"}')

if __name__ == '__main__':
    main()
