#!/usr/bin/env python3
import sys
import xml.etree.ElementTree as ET


def main() -> int:
    if len(sys.argv) != 2:
        print("Usage: check_xctrace_leaks.py <leaks.xml>", file=sys.stderr)
        return 2

    tree = ET.parse(sys.argv[1])
    leak_counts: dict[str, int] = {}
    for row in tree.iter("row"):
        leaked_object = row.get("leaked-object", "")
        if not leaked_object or leaked_object.startswith("Malloc"):
            continue
        leak_counts[leaked_object] = leak_counts.get(leaked_object, 0) + int(
            row.get("count", "1")
        )

    if leak_counts:
        print("Memory leaks detected:")
        for symbol, count in sorted(leak_counts.items()):
            print(f"- {symbol}: {count}")
        return 1

    print("No leaks found.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
