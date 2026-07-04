#!/usr/bin/env python3
"""Insert Purple Haze palette into builtin_palettes.cpp (idempotent)"""
import sys

palette_file = '/tmp/purple_haze.txt'
source_file = '/tmp/noctalia-greeter/src/theme/builtin_palettes.cpp'
tokyo_target = '.name = "Tokyo-Night"'

with open(source_file, 'r') as f:
    content = f.read()

# Idempotency check - don't insert if Purple Haze already exists
if '.name = "Purple Haze"' in content:
    print("Purple Haze already present, skipping insertion")
else:
    with open(palette_file, 'r') as f:
        palette = f.read()

    if tokyo_target not in content:
        sys.exit(f"ERROR: Could not find '{tokyo_target}' in builtin_palettes.cpp")

    # Strip any trailing newline from palette so we control spacing
    palette = palette.rstrip('\n')
    content = content.replace(tokyo_target, palette + '\n' + tokyo_target)

    with open(source_file, 'w') as f:
        f.write(content)

    print("Successfully inserted Purple Haze palette")