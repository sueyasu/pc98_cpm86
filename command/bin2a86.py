#!/usr/bin/env python3
import argparse
from pathlib import Path


def asm86_hex_byte(b: int) -> str:
    # Digital Research ASM-86 requires a leading decimal digit for hex
    # constants whose first hex digit would be A..F.  Emitting all bytes as
    # three hex digits is simple and unambiguous: 0FAh, 00Eh, 080h, etc.
    return f"0{b:02X}h"


def main():
    p = argparse.ArgumentParser(description='Convert a binary blob to a Digital Research ASM-86 INCLUDE file.')
    p.add_argument('input')
    p.add_argument('output')
    p.add_argument('--label', required=True)
    p.add_argument('--expect-size', type=lambda s: int(s, 0), default=None)
    p.add_argument('--bytes-per-line', type=int, default=16)
    args = p.parse_args()

    data = Path(args.input).read_bytes()
    if args.expect_size is not None and len(data) != args.expect_size:
        raise SystemExit(f'{args.input}: expected {args.expect_size} bytes, got {len(data)}')
    if not (1 <= args.bytes_per_line <= 32):
        raise SystemExit('--bytes-per-line must be 1..32')

    out = [f'; Generated from {Path(args.input).name} by bin2a86.py; DO NOT EDIT.\n',
           f'{args.label}:\n']
    for off in range(0, len(data), args.bytes_per_line):
        chunk = data[off:off + args.bytes_per_line]
        vals = ','.join(asm86_hex_byte(b) for b in chunk)
        out.append(f'        DB      {vals}\n')
    text = ''.join(out).replace('\n', '\r\n')
    Path(args.output).write_bytes(text.encode('ascii') + b'\x1a')


if __name__ == '__main__':
    main()
