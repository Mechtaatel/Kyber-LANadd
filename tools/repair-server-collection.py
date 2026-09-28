#!/usr/bin/env python3
"""Write a server-compatible metadata-only .kbcollection for original kyber-cli.

Original kyber-cli reads nested mod filenames from .kbcollection. Some exported
collections carry display/download names there while the installed .fbcollection
manifest contains the real filenames. This tool updates only those metadata
lists; it neither renames mods nor changes the CLI's loading behavior.
"""

import argparse
import json
import struct
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile


class Reader:
    def __init__(self, data: bytes):
        self.data = data
        self.offset = 0

    def u32(self) -> int:
        value = struct.unpack_from("<I", self.data, self.offset)[0]
        self.offset += 4
        return value

    def cstring(self) -> bytes:
        end = self.data.index(b"\0", self.offset)
        value = self.data[self.offset:end]
        self.offset = end + 1
        return value

    def sized(self) -> bytes:
        size = self.data[self.offset]
        self.offset += 1
        value = self.data[self.offset : self.offset + size]
        self.offset += size
        return value


def cstring(value: bytes) -> bytes:
    if b"\0" in value:
        raise ValueError("NUL in collection metadata")
    return value + b"\0"


def read_frosty_mod_names(file: Path) -> list[str]:
    with file.open("rb") as stream:
        header = stream.read(16)
        if len(header) != 16:
            raise ValueError(f"Truncated Frosty collection: {file}")
        magic, _version, offset, size = struct.unpack("<4I", header)
        if magic != 0x46434F4C:
            raise ValueError(f"Invalid Frosty collection: {file}")
        stream.seek(offset)
        manifest = json.loads(stream.read(size).decode("utf-8"))
    names = manifest["mods"]
    if not isinstance(names, list) or not all(isinstance(name, str) for name in names):
        raise ValueError(f"Invalid mods list in {file}")
    return names


def relative_mod_path(root: Path, collection: Path, name: str) -> Path:
    # Frosty manifests can use Windows separators even on a Linux server.
    if Path(name.replace("\\", "/")).is_absolute():
        raise ValueError(f"Absolute mod path in Frosty manifest: {name}")
    path = (collection.parent / name.replace("\\", "/")).resolve()
    if not path.is_relative_to(root):
        raise ValueError(f"Mod path escapes mod folder: {name}")
    if not path.is_file():
        raise FileNotFoundError(f"Frosty manifest references missing file: {path}")
    return path.relative_to(root)


def repair(metadata: bytes, root: Path) -> tuple[bytes, list[str]]:
    reader = Reader(metadata)
    version = reader.u32()
    if version != 1:
        raise ValueError(f"Unsupported .kbcollection version: {version}")

    output = bytearray(struct.pack("<I", version))
    output += cstring(reader.cstring())
    for _ in range(2):
        value = reader.sized()
        output += bytes([len(value)]) + value
    output += struct.pack("<I", reader.u32())  # isCosmetic
    count = reader.u32()
    output += struct.pack("<I", count)
    changes = []

    for _ in range(count):
        fields = [reader.cstring() for _ in range(6)]
        filename = fields[3].decode("latin-1")
        is_collection = fields[4] == b"true"
        if is_collection:
            collection = (root / filename).resolve()
            if not collection.is_relative_to(root) or not collection.is_file():
                raise FileNotFoundError(f"Frosty collection not found: {collection}")
            names = read_frosty_mod_names(collection)
            relative_names = [str(relative_mod_path(root, collection, name)).replace("\\", "/") for name in names]
            if any("," in name for name in relative_names):
                raise ValueError("A mod filename contains a comma; .kbcollection cannot represent it")
            fields[5] = ",".join(relative_names).encode("latin-1")
            changes.append(f"{filename}: {len(names)} nested mods")
        for field in fields:
            output += cstring(field)

    if reader.offset != len(metadata):
        raise ValueError("Unexpected trailing metadata; refusing to rewrite it")
    return bytes(output), changes


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("collection", type=Path, help="Existing metadata-only .kbcollection")
    parser.add_argument("--mod-folder", required=True, type=Path, help="Folder visible as KYBER_MOD_FOLDER in Docker")
    parser.add_argument("--output", required=True, type=Path, help="New .kbcollection; must not already exist")
    args = parser.parse_args()
    root = args.mod_folder.resolve(strict=True)
    if not root.is_dir():
        parser.error("--mod-folder is not a directory")
    if args.output.exists():
        parser.error("--output already exists; choose a new path")

    with ZipFile(args.collection) as source:
        if source.namelist() != ["METADATA"]:
            parser.error("Input must be a metadata-only .kbcollection with one METADATA entry")
        repaired, changes = repair(source.read("METADATA"), root)

    with ZipFile(args.output, "x", compression=ZIP_DEFLATED) as target:
        target.writestr("METADATA", repaired)
    print(f"Wrote {args.output}")
    for change in changes:
        print(change)
    print("Replace the old .kbcollection in KYBER_MOD_FOLDER with this file; keep exactly one there.")


if __name__ == "__main__":
    main()
