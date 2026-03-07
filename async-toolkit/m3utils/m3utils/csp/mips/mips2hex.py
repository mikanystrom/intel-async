#!/usr/bin/env python3
"""mips2hex.py — Convert MIPS ELF binary to hex files for MiniMIPS simulator.

Usage: python3 mips2hex.py <input.elf> [--text program.hex] [--data data.hex]

Reads a MIPS ELF binary and produces:
  program.hex — .text section as 32-bit hex words (one per line)
  data.hex    — .data/.rodata/.bss sections as bytes (optional)
"""

import struct
import sys
import argparse


def read_elf(path):
    """Parse a MIPS ELF binary and return section data."""
    with open(path, "rb") as f:
        data = f.read()

    # ELF header
    if data[:4] != b"\x7fELF":
        raise ValueError("Not an ELF file")

    ei_class = data[4]  # 1=32-bit, 2=64-bit
    ei_data = data[5]   # 1=little-endian, 2=big-endian

    if ei_class != 1:
        raise ValueError("Expected 32-bit ELF")

    endian = "<" if ei_data == 1 else ">"

    # ELF32 header fields
    (e_type, e_machine, e_version, e_entry, e_phoff, e_shoff,
     e_flags, e_ehsize, e_phentsize, e_phnum, e_shentsize,
     e_shnum, e_shstrndx) = struct.unpack_from(endian + "HHIIIIIHHHHHH", data, 16)

    if e_machine != 8:  # EM_MIPS
        raise ValueError(f"Not a MIPS ELF (machine={e_machine})")

    # Read section headers
    sections = []
    for i in range(e_shnum):
        off = e_shoff + i * e_shentsize
        (sh_name, sh_type, sh_flags, sh_addr, sh_offset, sh_size,
         sh_link, sh_info, sh_addralign, sh_entsize) = struct.unpack_from(
            endian + "IIIIIIIIII", data, off)
        sections.append({
            "name_off": sh_name, "type": sh_type, "flags": sh_flags,
            "addr": sh_addr, "offset": sh_offset, "size": sh_size,
        })

    # Read section name string table
    if e_shstrndx < len(sections):
        strtab = sections[e_shstrndx]
        strtab_data = data[strtab["offset"]:strtab["offset"] + strtab["size"]]
    else:
        strtab_data = b""

    def get_name(off):
        end = strtab_data.find(b"\x00", off)
        if end < 0:
            return ""
        return strtab_data[off:end].decode("ascii", errors="replace")

    # Extract named sections
    result = {}
    for s in sections:
        name = get_name(s["name_off"])
        if s["size"] > 0 and s["type"] != 0:  # skip NULL sections
            result[name] = {
                "addr": s["addr"],
                "data": data[s["offset"]:s["offset"] + s["size"]],
                "size": s["size"],
            }

    return result, endian, e_entry


def write_text_hex(sections, endian, outpath):
    """Write .text section as 32-bit hex words."""
    text = sections.get(".text")
    if not text:
        raise ValueError("No .text section found")

    word_fmt = endian + "I"
    data = text["data"]

    # Pad to word boundary
    if len(data) % 4 != 0:
        data += b"\x00" * (4 - len(data) % 4)

    with open(outpath, "w") as f:
        f.write(f"// {outpath} — {len(data) // 4} words, "
                f"base address 0x{text['addr']:08X}\n")
        for i in range(0, len(data), 4):
            word = struct.unpack_from(word_fmt, data, i)[0]
            f.write(f"{word:08X}\n")

    print(f"Wrote {len(data) // 4} words to {outpath}")


def write_data_hex(sections, endian, outpath):
    """Write .data/.rodata sections as hex words. Always creates the file."""
    # Collect all data sections, sorted by address
    data_sects = []
    for name in (".data", ".rodata", ".sdata"):
        if name in sections:
            data_sects.append(sections[name])

    if not data_sects:
        # Write empty data file (comment only)
        with open(outpath, "w") as f:
            f.write(f"// {outpath} — 0 bytes (no data section)\n")
        print(f"Wrote 0 words to {outpath} (no data section)")
        return

    data_sects.sort(key=lambda s: s["addr"])
    base = data_sects[0]["addr"]

    # Build contiguous data image
    end_addr = max(s["addr"] + s["size"] for s in data_sects)
    image = bytearray(end_addr - base)
    for s in data_sects:
        off = s["addr"] - base
        image[off:off + s["size"]] = s["data"]

    with open(outpath, "w") as f:
        f.write(f"// {outpath} — {len(image)} bytes, "
                f"base address 0x{base:08X}\n")
        for i in range(0, len(image), 4):
            chunk = image[i:i+4]
            # Write as 32-bit word (pad if needed)
            while len(chunk) < 4:
                chunk += b"\x00"
            word = struct.unpack_from(endian + "I", bytes(chunk), 0)[0]
            f.write(f"{word:08X}\n")

    print(f"Wrote {len(image)} bytes ({len(image) // 4} words) to {outpath}")


def main():
    parser = argparse.ArgumentParser(
        description="Convert MIPS ELF to hex for MiniMIPS simulator")
    parser.add_argument("elf", help="Input MIPS ELF binary")
    parser.add_argument("--text", default="program.hex",
                        help="Output text hex file (default: program.hex)")
    parser.add_argument("--data", default=None,
                        help="Output data hex file (default: none)")
    parser.add_argument("--info", action="store_true",
                        help="Print section info and exit")
    args = parser.parse_args()

    sections, endian, entry = read_elf(args.elf)

    if args.info:
        e = "little" if endian == "<" else "big"
        print(f"ELF: {args.elf} ({e}-endian, entry=0x{entry:08X})")
        for name, s in sorted(sections.items(), key=lambda x: x[1]["addr"]):
            print(f"  {name:16s}  addr=0x{s['addr']:08X}  "
                  f"size=0x{s['size']:04X} ({s['size']})")
        return

    write_text_hex(sections, endian, args.text)
    if args.data is not None:
        write_data_hex(sections, endian, args.data)


if __name__ == "__main__":
    main()
