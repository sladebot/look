#!/usr/bin/env python3
"""Add Swift source files to Look.xcodeproj/project.pbxproj (objectVersion 56, manual refs).

Usage: add_files_to_pbxproj.py <group> <file.swift> [<file.swift> ...]
  <group> is the PBXGroup name to attach the file refs to ("Look" or "Views").
Files are added to PBXBuildFile, PBXFileReference, the group's children, and the
Sources build phase. Idempotent: skips files already present.
"""
import re
import sys
import uuid


def gen_id(existing):
    while True:
        candidate = uuid.uuid4().hex[:24].upper()
        if candidate not in existing:
            existing.add(candidate)
            return candidate


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(1)
    group = sys.argv[1]
    files = sys.argv[2:]

    path = "Look.xcodeproj/project.pbxproj"
    with open(path) as f:
        text = f.read()

    existing_ids = set(re.findall(r"\b([0-9A-F]{24})\b", text))

    for fname in files:
        if f"/* {fname} */" in text:
            print(f"skip (already present): {fname}")
            continue
        file_ref = gen_id(existing_ids)
        build_ref = gen_id(existing_ids)

        # 1. PBXBuildFile
        build_line = (
            f"\t\t{build_ref} /* {fname} in Sources */ = "
            f"{{isa = PBXBuildFile; fileRef = {file_ref} /* {fname} */; }};\n"
        )
        text = text.replace(
            "/* Begin PBXBuildFile section */\n",
            "/* Begin PBXBuildFile section */\n" + build_line,
            1,
        )

        # 2. PBXFileReference
        ref_line = (
            f"\t\t{file_ref} /* {fname} */ = "
            f"{{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; "
            f"path = {fname}; sourceTree = \"<group>\"; }};\n"
        )
        text = text.replace(
            "/* Begin PBXFileReference section */\n",
            "/* Begin PBXFileReference section */\n" + ref_line,
            1,
        )

        # 3. Group children — match the named group block, insert into its children=( ... )
        group_pat = re.compile(
            r"(/\* " + re.escape(group) + r" \*/ = \{\s*isa = PBXGroup;\s*children = \(\n)"
        )
        m = group_pat.search(text)
        if not m:
            raise SystemExit(f"Group not found: {group}")
        child_line = f"\t\t\t\t{file_ref} /* {fname} */,\n"
        text = text[: m.end()] + child_line + text[m.end():]

        # 4. Sources build phase
        src_line = f"\t\t\t\t{build_ref} /* {fname} in Sources */,\n"
        text = text.replace(
            "/* Begin PBXSourcesBuildPhase section */\n",
            "/* Begin PBXSourcesBuildPhase section */\n",
        )
        # Insert into the files=( ) list of the Sources phase
        src_pat = re.compile(r"(isa = PBXSourcesBuildPhase;\s*buildActionMask = \d+;\s*files = \(\n)")
        ms = src_pat.search(text)
        if not ms:
            raise SystemExit("Sources build phase not found")
        text = text[: ms.end()] + src_line + text[ms.end():]

        print(f"added: {fname} (group={group})")

    with open(path, "w") as f:
        f.write(text)


if __name__ == "__main__":
    main()
