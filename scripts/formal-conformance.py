#!/usr/bin/env python3
r"""Checks that the Swift code still matches formal/LocalModelLifecycle.tla.

The model is only worth what its tie to the code is worth. Every step of the model carries comment lines that
name the Swift line it comes from. This script fails when one of those lines is gone or moved out of its function,
when the order of steps the model relies on changed, when a new file starts to use the gate or the cache, or
when the configs and the spec disagree. It does not prove the code correct. It tells you the model needs another
look before you trust a green TLC run.

Directives, each one a spec comment line that starts with "\*" (an optional "WHEN Flag=VALUE" before the word applies
it only when formal/LocalModelLifecycle.cfg sets the flag to VALUE):

  CODE   <file> :: <scope> :: <text>        text appears in the body of the scope ("-" is the whole file)
  ORDER  <file> :: <scope> :: a >> b >> c   each text appears after the one before it
  COUNT  <file> :: <scope> :: <text> :: <n> text appears exactly n times
  ABSENT <file> :: <text>                   text appears nowhere in the file
  ONLY   <f1>, <f2> :: <regex>              the non-test Swift files that match the regex are exactly these

Usage: python3 -I scripts/formal-conformance.py
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SPEC = os.path.join(ROOT, "formal", "LocalModelLifecycle.tla")
MAIN_CFG = os.path.join(ROOT, "formal", "LocalModelLifecycle.cfg")
MUTANTS = os.path.join(ROOT, "formal", "mutants")
# Every action of the model must say which code it comes from.
ACTIONS = ["StartChat", "GateExit", "RunFinish", "Cancel", "StartWarm", "CacheRequest", "LoadSucceed",
           "LoadFail", "Release", "UnloadAll", "UnloadIfEffect", "RemoveFilesEffect", "DeleteStep1"]

errors = []
checked = 0


def fail(message):
    errors.append(message)


def read(path):
    with open(os.path.join(ROOT, path), encoding="utf-8") as handle:
        return handle.read()


def code_lines(path):
    """The lines of a Swift file without comments, so a commented-out call does not count."""
    lines = []
    for raw in read(path).splitlines():
        stripped = raw.lstrip()
        if stripped.startswith("//"):
            lines.append("")
            continue
        cut = raw.find(" //")
        lines.append(raw[:cut] if cut >= 0 and raw[:cut].count('"') % 2 == 0 else raw)
    return lines


def scope_body(path, scope):
    """The lines from the line that holds scope to the brace that closes it."""
    lines = code_lines(path)
    if scope == "-":
        return lines
    for start, line in enumerate(lines):
        if scope in line:
            break
    else:
        return None
    depth, opened, body = 0, False, []
    for line in lines[start:]:
        body.append(line)
        for char in line:
            if char == "{":
                depth, opened = depth + 1, True
            elif char == "}":
                depth -= 1
        if opened and depth <= 0:
            break
    return body


def cfg_flags():
    flags = {}
    for line in read("formal/LocalModelLifecycle.cfg").splitlines():
        match = re.match(r"^\s+(\w+) = (TRUE|FALSE)\s*$", line)
        if match:
            flags[match.group(1)] = match.group(2)
    return flags


def parse_directives():
    out = []
    for number, line in enumerate(read("formal/LocalModelLifecycle.tla").splitlines(), 1):
        match = re.match(r"^\\\* (?:WHEN (\w+)=(TRUE|FALSE) )?(CODE|ORDER|COUNT|ABSENT|ONLY) (.*)$", line)
        if match:
            out.append((number, match.group(1), match.group(2), match.group(3), match.group(4)))
    return out


def run_directive(number, kind, rest):
    global checked
    where = "formal/LocalModelLifecycle.tla:%d" % number
    parts = [part.strip() for part in rest.split(" :: ")]
    if kind == "ONLY":
        files, pattern = [f.strip() for f in parts[0].split(",")], parts[1]
        found = set()
        for folder in ("App", "Core", "Engines", "Features"):
            for base, _, names in os.walk(os.path.join(ROOT, folder)):
                for name in names:
                    if name.endswith(".swift"):
                        rel = os.path.relpath(os.path.join(base, name), ROOT)
                        if any(re.search(pattern, line) for line in code_lines(rel)):
                            found.add(rel)
        checked += 1
        if found != set(files):
            fail("%s: files that match /%s/ changed.\n    model says: %s\n    code has:   %s\n"
                 "    A new caller is a new interleaving. Add it to the model, then update this line."
                 % (where, pattern, sorted(files), sorted(found)))
        return
    path = parts[0]
    if not os.path.exists(os.path.join(ROOT, path)):
        fail("%s: %s does not exist" % (where, path))
        return
    if kind == "ABSENT":
        checked += 1
        if any(parts[1] in line for line in code_lines(path)):
            fail("%s: %s still has %r, which the model says is gone" % (where, path, parts[1]))
        return
    scope, text = parts[1], parts[2]
    body = scope_body(path, scope)
    if body is None:
        fail("%s: %s has no %r" % (where, path, scope))
        return
    joined_lines = body
    checked += 1
    if kind == "CODE":
        if not any(text in line for line in joined_lines):
            fail("%s: %r is gone from %s in %s" % (where, text, scope, path))
    elif kind == "COUNT":
        expected = int(parts[3])
        count = sum(line.count(text) for line in joined_lines)
        if count != expected:
            fail("%s: %r appears %d times in %s of %s, the model has %d" % (where, text, count, scope, path, expected))
    elif kind == "ORDER":
        position = 0
        for step in [s.strip() for s in text.split(" >> ")]:
            for index in range(position, len(joined_lines)):
                if step in joined_lines[index]:
                    position = index + 1
                    break
            else:
                fail("%s: in %s of %s, %r is missing or comes before an earlier step of %s"
                     % (where, scope, path, step, text))
                return


def check_actions_have_code():
    global checked
    lines = read("formal/LocalModelLifecycle.tla").splitlines()
    for action in ACTIONS:
        index = next((i for i, line in enumerate(lines) if re.match(r"^%s(\(|\s*==)" % action, line)), None)
        if index is None:
            fail("spec has no action %s; update ACTIONS in this script" % action)
            continue
        block = []
        cursor = index - 1
        while cursor >= 0 and (lines[cursor].startswith("\\*") or not lines[cursor].strip()):
            block.append(lines[cursor])
            cursor -= 1
        checked += 1
        if not any(re.match(r"^\\\* (CODE|ORDER) ", line) for line in block):
            fail("spec action %s has no CODE line above it: say which Swift line it comes from" % action)


def check_configs():
    global checked
    main = cfg_flags()
    spec = read("formal/LocalModelLifecycle.tla")
    for flag in main:
        if not re.search(r"\b%s\b" % flag, spec):
            fail("the main cfg sets %s, which the spec does not declare" % flag)
    main_text = read("formal/LocalModelLifecycle.cfg")
    invariants = set(re.findall(r"^\s{4}(\w+)\s*$", main_text.split("INVARIANTS")[1], re.M))
    for name in invariants:
        if not re.search(r"^%s\s*==" % name, spec, re.M):
            fail("main cfg checks %s, which the spec does not define" % name)
    for name in sorted(os.listdir(MUTANTS)):
        text = read("formal/mutants/" + name)
        flags = {}
        for line in text.splitlines():
            match = re.match(r"^\s+(\w+) = (TRUE|FALSE)\s*$", line)
            if match:
                flags[match.group(1)] = match.group(2)
        changed = [flag for flag in main if flags.get(flag) != main[flag]]
        expect = re.search(r"^\\\* EXPECT (\w+)", text, re.M)
        checked += 1
        if len(changed) != 1:
            fail("mutant %s changes %d flags (%s); it must change exactly one" % (name, len(changed), changed))
        if not expect or expect.group(1) not in invariants:
            fail("mutant %s expects an invariant that the main cfg does not check" % name)
    for flag in main:
        if not any(("%s = " % flag) in read("formal/mutants/" + n) and cfg_flags_of(n).get(flag) != main[flag]
                   for n in os.listdir(MUTANTS)):
            fail("no mutant turns %s back; its invariant was never seen to fail" % flag)


def cfg_flags_of(name):
    flags = {}
    for line in read("formal/mutants/" + name).splitlines():
        match = re.match(r"^\s+(\w+) = (TRUE|FALSE)\s*$", line)
        if match:
            flags[match.group(1)] = match.group(2)
    return flags


def main():
    flags = cfg_flags()
    directives = parse_directives()
    for number, flag, value, kind, rest in directives:
        if flag and flags.get(flag) != value:
            continue
        run_directive(number, kind, rest)
    check_actions_have_code()
    check_configs()
    if errors:
        print("The Swift code no longer matches formal/LocalModelLifecycle.tla (%d problems):" % len(errors))
        for message in errors:
            print("  - " + message)
        print("Read .claude/skills/verify-local-model-lifecycle/SKILL.md, update the model or the code, run TLC.")
        return 1
    print("OK: %d checks tie the model to the code" % checked)
    return 0


if __name__ == "__main__":
    sys.exit(main())
