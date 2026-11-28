#!/usr/bin/env python3
"""Agent v2 K1 codemod (docs/research/agent-v2.md). Kept for the length of K1 so each wave can be rerun and reviewed.

Usage: scripts/k1-codemod.py <wave> [--check]
  k1a   ToolSpec.inputSchemaJSON (String) becomes schema (JSONSchema), everywhere it is declared, passed or read.
  k1a2  ChatDelta and StepEvent .usage(prompt:completion:) becomes .usage(Usage), where a usage is built. Matches
        (`case .usage(let prompt, let completion)`) mean something different at each site and are rewritten by hand.
--check only lists the files a wave would change.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FOLDERS = ["App", "Core", "Design", "Engines", "Features", "Shared", "Controls", "Share", "Tests", "UITests"]
# Files whose schema code is rewritten by hand in the same wave.
# Readers that want the schema itself, not its text, are rewritten by hand after the script runs: AnyRouterEngine.wireTool,
# LocalToolFormat, AppleDynamicTool and PinnedTool.mcpTool.
K1A_BY_HAND = {"Core/Tools.swift"}

RAW = r'(?:#+"(?:[^"]|"(?!#))*"#+|"(?:[^"\\]|\\.)*")'   # a raw or plain one-line string literal


def k1a(text: str) -> str:
    # Declarations: a stored property or a protocol requirement typed String.
    text = re.sub(r'\bvar inputSchemaJSON: String\b', 'var schema: JSONSchema', text)
    # `let inputSchemaJSON = <literal>` in a tool, and `static let`.
    text = re.sub(r'\b(static )?let inputSchemaJSON = (' + RAW + ')', r'\1let schema: JSONSchema = \2', text)
    # One binding of a list: `let name = "x", inputSchemaJSON = "{}"`.
    text = re.sub(r', inputSchemaJSON = (' + RAW + ')', r', schema: JSONSchema = \1', text)
    # `let inputSchemaJSON = SomeLogic.constant` (a String constant kept as it is).
    text = re.sub(r'\b(static )?let inputSchemaJSON = ([A-Za-z_][\w.]*)', r'\1let schema = JSONSchema(parsing: \2)', text)
    # Argument labels. Order matters: the most specific value first.
    text = re.sub(r'\binputSchemaJSON: String\b', 'schema: JSONSchema', text)
    text = re.sub(r'\binputSchemaJSON: (' + RAW + ')', r'schema: \1', text)
    text = re.sub(r'\binputSchemaJSON: ([A-Za-z_][\w.]*)\.inputSchema\.jsonString\(\)', r'schema: JSONSchema(\1.inputSchema)', text)
    text = re.sub(r'\binputSchemaJSON: ([A-Za-z_][\w.]*)\.inputSchemaJSON\b', r'schema: \1.schema', text)
    text = re.sub(r'\binputSchemaJSON: inputSchemaJSON\b', 'schema: schema', text)
    text = re.sub(r'\binputSchemaJSON: ([A-Za-z_][\w.]*)', r'schema: JSONSchema(parsing: \1)', text)
    # Reads that want the text.
    text = re.sub(r'\.inputSchemaJSON\b', '.schema.json', text)
    return text


def k1a2(text: str) -> str:
    return re.sub(r'\.usage\(prompt: ([^,()]+), completion: ([^()]+?)\)', r'.usage(Usage(input: \1, output: \2))', text)


WAVES = {"k1a": (k1a, K1A_BY_HAND), "k1a2": (k1a2, set())}


def main() -> int:
    if len(sys.argv) < 2 or sys.argv[1] not in WAVES:
        print(__doc__)
        return 2
    transform, by_hand = WAVES[sys.argv[1]]
    check = "--check" in sys.argv
    changed = []
    for folder in FOLDERS:
        for path in sorted((ROOT / folder).rglob("*.swift")) if (ROOT / folder).exists() else []:
            rel = str(path.relative_to(ROOT))
            if rel in by_hand:
                continue
            old = path.read_text(encoding="utf-8")
            new = transform(old)
            if new != old:
                changed.append(rel)
                if not check:
                    path.write_text(new, encoding="utf-8")
    print("\n".join(changed))
    print(f"{len(changed)} files {'would change' if check else 'changed'}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
