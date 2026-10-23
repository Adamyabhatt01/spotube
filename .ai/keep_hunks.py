#!/usr/bin/env python3
"""Split a `git diff` file into hunks and keep only the ones that match a marker.

Usage: keep_hunks.py <diff> <out> <--grep REGEX|--not REGEX> [--grep/--not ...]
A hunk is kept when every --grep pattern matches it and no --not pattern does.
"""
import re
import sys


def main():
    diff_path, out_path = sys.argv[1], sys.argv[2]
    greps, nots = [], []
    flags = sys.argv[3:]
    bucket = None
    for tok in flags:
        if tok == '--grep':
            bucket = greps
            continue
        if tok == '--not':
            bucket = nots
            continue
        bucket.append(tok)

    with open(diff_path) as f:
        lines = f.read().split('\n')

    header, hunks, current = [], [], None
    in_hunk = False
    for line in lines:
        if line.startswith('@@'):
            in_hunk = True
            if current is not None:
                hunks.append(current)
            current = [line]
            continue
        if not in_hunk:
            header.append(line)
        else:
            current.append(line)
    if current is not None:
        hunks.append(current)

    kept, dropped = [], []
    for hunk in hunks:
        body = '\n'.join(hunk)
        if all(re.search(p, body) for p in greps) and not any(
            re.search(p, body) for p in nots
        ):
            kept.append(hunk)
        else:
            dropped.append(hunk)

    out = '\n'.join(header).rstrip('\n') + '\n'
    for hunk in kept:
        # Strip the trailing empty line the split produced, rejoin hunks.
        body = hunk[:]
        while body and body[-1] == '':
            body.pop()
        out += '\n'.join(body) + '\n'
    with open(out_path, 'w') as f:
        f.write(out)

    print(f'{len(hunks)} hunk(s): kept {len(kept)}, dropped {len(dropped)}')
    for hunk in dropped:
        print(f'  dropped: {hunk[0]}')


if __name__ == '__main__':
    main()
