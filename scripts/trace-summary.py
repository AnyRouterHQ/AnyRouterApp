#!/usr/bin/env python3
"""Reads an `xctrace export` of a Time Profiler table and prints where the samples went.

Usage: trace-summary.py <time-profile.xml> [rows]
Prints samples per thread, the frames that are on the stack in the most samples (inclusive), the frames that are
on top of the stack (self), and the inclusive list for the app's own binary only. The export writes each frame,
binary, thread and backtrace once with an id and refers to it with ref= after that.
"""
import collections
import sys
import xml.etree.ElementTree as ET

path = sys.argv[1]
rows = int(sys.argv[2]) if len(sys.argv) > 2 else 40
app_binary = "AnyRouter"

binaries, frames, backtraces, threads = {}, {}, {}, {}


def binary_name(element):
    if element is None:
        return ""
    if element.get("ref"):
        return binaries.get(element.get("ref"), "")
    binaries[element.get("id")] = element.get("name", "")
    return element.get("name", "")


def frame(element):
    if element.get("ref"):
        return frames[element.get("ref")]
    info = (element.get("name") or element.get("addr") or "?", binary_name(element.find("binary")))
    frames[element.get("id")] = info
    return info


def backtrace(element):
    if element is None:
        return ()
    if element.get("ref"):
        return backtraces[element.get("ref")]
    stack = tuple(frame(f) for f in element.findall("frame"))
    backtraces[element.get("id")] = stack
    return stack


def thread(element):
    if element is None:
        return "?"
    if element.get("ref"):
        return threads[element.get("ref")]
    threads[element.get("id")] = element.get("fmt", "?")
    return threads[element.get("id")]


total = 0
per_thread, inclusive, own, top = (collections.Counter() for _ in range(4))
for _, element in ET.iterparse(path, events=("end",)):
    if element.tag != "row":
        continue
    stack = backtrace(element.find("backtrace"))
    per_thread[thread(element.find("thread"))] += 1
    element.clear()
    if not stack:
        continue
    total += 1
    top[stack[0][0]] += 1
    for name in {name for name, _ in stack}:
        inclusive[name] += 1
    for name in {name for name, binary in stack if binary == app_binary}:
        own[name] += 1


def table(title, counter):
    print(f"\n{title}")
    for name, count in counter.most_common(rows):
        print(f"{count:7d} {100 * count / max(total, 1):5.1f}%  {name[:160]}")


print(f"{total} samples with a stack")
table("Samples per thread", per_thread)
table("Inclusive (on the stack)", inclusive)
table("Self (top of the stack)", top)
table(f"Inclusive, {app_binary} binary only", own)
