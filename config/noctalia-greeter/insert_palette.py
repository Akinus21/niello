#!/usr/bin/env python3
"""Insert Purple Haze palette into builtin_palettes.cpp"""
import sys

# v3: ensure newline separator between Purple Haze and Tokyo-Night
palette_file = '/tmp/purple_haze.txt'
source_file = '/tmp/noctalia-greeter/src/theme/builtin_palettes.cpp'
target = '.name = "Tokyo-Night"'

with open(palette_file, 'r') as f:
    palette = f.read()

with open(source_file, 'r') as f:
    content = f.read()

if target not in content:
    sys.exit(f"ERROR: Could not find '{target}' in builtin_palettes.cpp")

content = content.replace(target, palette.rstrip('\n') + '\n' + target)

with open(source_file, 'w') as f:
    f.write(content)

print(f"Successfully inserted Purple Haze palette")