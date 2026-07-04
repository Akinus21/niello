#!/usr/bin/env python3
"""Insert Purple Haze palette into builtin_palettes.cpp before the kPalettes array closer."""

import sys

PURPLE_HAZE_ENTRY = """
    {
        .name = "Purple Haze",
        .dark =
            FixedPaletteMode{
                .palette =
                    Palette{
                        .primary = hex("#A8E000"),
                        .onPrimary = hex("#0C0E00"),
                        .secondary = hex("#8A4FB0"),
                        .onSecondary = hex("#F0ECFF"),
                        .tertiary = hex("#AA7AD0"),
                        .onTertiary = hex("#F5EEFF"),
                        .error = hex("#FF3C4E"),
                        .onError = hex("#0b070d"),
                        .surface = hex("#0b070d"),
                        .onSurface = hex("#ad9bbb"),
                        .surfaceVariant = hex("#241330"),
                        .onSurfaceVariant = hex("#9878C0"),
                        .outline = hex("#8A4FB0"),
                        .shadow = hex("#0E0814"),
                        .hover = hex("#301460"),
                        .onHover = hex("#ad9bbb"),
                    },
                .terminal =
                    TerminalPalette{
                        .normal =
                            TerminalAnsiColors{
                                .black = hex("#0b070d"),
                                .red = hex("#FF3C4E"),
                                .green = hex("#A8E000"),
                                .yellow = hex("#FFCC00"),
                                .blue = hex("#8A4FB0"),
                                .magenta = hex("#AA7AD0"),
                                .cyan = hex("#00E8CC"),
                                .white = hex("#ad9bbb"),
                            },
                        .bright =
                            TerminalAnsiColors{
                                .black = hex("#7AAB20"),
                                .red = hex("#FF6070"),
                                .green = hex("#C8F055"),
                                .yellow = hex("#FFD740"),
                                .blue = hex("#A870C8"),
                                .magenta = hex("#CC99E8"),
                                .cyan = hex("#55EEE0"),
                                .white = hex("#F5F0FF"),
                            },
                        .foreground = hex("#ad9bbb"),
                        .background = hex("#0b070d"),
                        .selectionFg = hex("#F0ECFF"),
                        .selectionBg = hex("#4E2478"),
                        .cursorText = hex("#0C0E00"),
                        .cursor = hex("#A8E000"),
                    },
            },
        .light =
            FixedPaletteMode{
                .palette =
                    Palette{
                        .primary = hex("#6E34A0"),
                        .onPrimary = hex("#FFFFFF"),
                        .secondary = hex("#527800"),
                        .onSecondary = hex("#FFFFFF"),
                        .tertiary = hex("#9A68C8"),
                        .onTertiary = hex("#FFFFFF"),
                        .error = hex("#CC2F3F"),
                        .onError = hex("#FFFFFF"),
                        .surface = hex("#F4F0FA"),
                        .onSurface = hex("#0b070d"),
                        .surfaceVariant = hex("#EAE0FF"),
                        .onSurfaceVariant = hex("#301454"),
                        .outline = hex("#8A4FB0"),
                        .shadow = hex("#EAE4F8"),
                        .hover = hex("#DDD0F8"),
                        .onHover = hex("#0b070d"),
                    },
                .terminal =
                    TerminalPalette{
                        .normal =
                            TerminalAnsiColors{
                                .black = hex("#0b070d"),
                                .red = hex("#CC2F3F"),
                                .green = hex("#527800"),
                                .yellow = hex("#8A6000"),
                                .blue = hex("#4E2478"),
                                .magenta = hex("#6E34A0"),
                                .cyan = hex("#007A60"),
                                .white = hex("#F4F0FA"),
                            },
                        .bright =
                            TerminalAnsiColors{
                                .black = hex("#7AAB20"),
                                .red = hex("#A02030"),
                                .green = hex("#3A5800"),
                                .yellow = hex("#6A4A00"),
                                .blue = hex("#7850B0"),
                                .magenta = hex("#9A60D8"),
                                .cyan = hex("#005A45"),
                                .white = hex("#FFFFFF"),
                            },
                        .foreground = hex("#0b070d"),
                        .background = hex("#F4F0FA"),
                        .selectionFg = hex("#0b070d"),
                        .selectionBg = hex("#D0B8F8"),
                        .cursorText = hex("#FFFFFF"),
                        .cursor = hex("#6E34A0"),
                    },
            },
    },
"""


def main():
    filepath = "/tmp/noctalia-greeter/src/theme/builtin_palettes.cpp"

    with open(filepath, "r") as f:
        content = f.read()

    # Find the last }; in the file - that's the kPalettes array closer
    last_brace = content.rfind("};")
    if last_brace == -1:
        sys.exit("Error: Could not find closing }; in builtin_palettes.cpp")

    # Insert Purple Haze before the last };
    content = content[:last_brace] + PURPLE_HAZE_ENTRY + content[last_brace:]

    with open(filepath, "w") as f:
        f.write(content)

    print(f"Successfully inserted Purple Haze palette into {filepath}")


if __name__ == "__main__":
    main()
