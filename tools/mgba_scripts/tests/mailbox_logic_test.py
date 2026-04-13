#!/usr/bin/env python3
"""
Logic tests for the reserved-species scripting mailbox (same layout as
tools/mgba_scripts/reserved_species_mailbox.lua and include/reserved_species.h).

Run: python3 tools/mgba_scripts/tests/mailbox_logic_test.py
"""
from __future__ import annotations

# --- sync with reserved_species_mailbox.lua / reserved_species.h ---
MAGIC = 0x31505352
TRAIL = 0x544C4252
VERSION = 1
OFFSET_MAGIC = 0
OFFSET_VERSION = 4
OFFSET_COUNT = 6
OFFSET_SPECIES_INFO = 8
OFFSET_LEVEL_UP_LEARNSETS = 12
OFFSET_MON_FRONT_PIC = 16
OFFSET_MON_BACK_PIC = 20
OFFSET_MON_PALETTE = 24
OFFSET_SPECIES_NAMES = 28
OFFSET_SIZEOF_SPECIES_INFO = 32
OFFSET_TARGET_SPECIES = 36
OFFSET_PADDING16 = 38
OFFSET_SPECIES_INFO_ROW_PTR = 40
OFFSET_LEVEL_UP_LEARNSET_ENTRY_ADDR = 44
OFFSET_TRAIL_MAGIC = 48
MAILBOX_SIZE = 52


class EmuShim:
    def __init__(self, words: dict[int, int]) -> None:
        self._w = words

    def read32(self, addr: int) -> int:
        if addr % 4:
            raise ValueError("unaligned read32")
        return self._w.get(addr, 0)

    def read16(self, addr: int) -> int:
        if addr % 2:
            raise ValueError("unaligned read16")
        w = self.read32(addr - (addr % 4))
        if addr % 4 == 0:
            return w & 0xFFFF
        return (w >> 16) & 0xFFFF


def place_mailbox(mem: dict[int, int], base: int, **fields) -> None:
    mem[base + OFFSET_MAGIC] = MAGIC
    v = fields["version"]
    c = fields["count"]
    mem[base + OFFSET_VERSION] = v | (c << 16)
    mem[base + OFFSET_SPECIES_INFO] = fields["speciesInfo"]
    mem[base + OFFSET_LEVEL_UP_LEARNSETS] = fields["levelUpLearnsets"]
    mem[base + OFFSET_MON_FRONT_PIC] = fields.get("monFrontPicTable", 0)
    mem[base + OFFSET_MON_BACK_PIC] = fields.get("monBackPicTable", 0)
    mem[base + OFFSET_MON_PALETTE] = fields.get("monPaletteTable", 0)
    mem[base + OFFSET_SPECIES_NAMES] = fields.get("speciesNames", 0)
    mem[base + OFFSET_SIZEOF_SPECIES_INFO] = fields["sizeofSpeciesInfo"]
    tgt = fields["targetSpecies"]
    pad = fields.get("padding16", 0)
    mem[base + OFFSET_TARGET_SPECIES] = tgt | (pad << 16)
    mem[base + OFFSET_SPECIES_INFO_ROW_PTR] = fields["speciesInfoRowPtr"]
    mem[base + OFFSET_LEVEL_UP_LEARNSET_ENTRY_ADDR] = fields["levelUpLearnsetEntryAddr"]
    mem[base + OFFSET_TRAIL_MAGIC] = TRAIL


def validate_mailbox(emu: EmuShim, base: int) -> tuple[bool, str]:
    if emu.read32(base + OFFSET_MAGIC) != MAGIC:
        return False, "bad magic"
    if emu.read32(base + OFFSET_TRAIL_MAGIC) != TRAIL:
        return False, "bad trail"
    if emu.read16(base + OFFSET_VERSION) != VERSION:
        return False, "bad version"
    return True, ""


def find_mailbox(emu: EmuShim, start_addr: int, end_addr: int) -> int | None:
    start_addr -= start_addr % 4
    end_addr -= end_addr % 4
    for a in range(start_addr, end_addr - MAILBOX_SIZE + 1, 4):
        if emu.read32(a + OFFSET_MAGIC) == MAGIC and emu.read32(a + OFFSET_TRAIL_MAGIC) == TRAIL:
            ok, _ = validate_mailbox(emu, a)
            if ok:
                return a
    return None


def read_mailbox(emu: EmuShim, base: int) -> dict:
    return {
        "magic": emu.read32(base + OFFSET_MAGIC),
        "version": emu.read16(base + OFFSET_VERSION),
        "count": emu.read16(base + OFFSET_COUNT),
        "speciesInfo": emu.read32(base + OFFSET_SPECIES_INFO),
        "sizeofSpeciesInfo": emu.read32(base + OFFSET_SIZEOF_SPECIES_INFO),
        "targetSpecies": emu.read16(base + OFFSET_TARGET_SPECIES),
        "speciesInfoRowPtr": emu.read32(base + OFFSET_SPECIES_INFO_ROW_PTR),
        "trailMagic": emu.read32(base + OFFSET_TRAIL_MAGIC),
    }


def species_info_row_ptr_from_base(species_info_base: int, species_id: int, sizeof_si: int) -> int:
    return species_info_base + species_id * sizeof_si


def row_ptr_matches_computed(emu: EmuShim, base: int) -> bool:
    mb = read_mailbox(emu, base)
    if mb["magic"] != MAGIC or mb["trailMagic"] != TRAIL:
        return False
    computed = species_info_row_ptr_from_base(mb["speciesInfo"], mb["targetSpecies"], mb["sizeofSpeciesInfo"])
    return mb["speciesInfoRowPtr"] == computed


def main() -> None:
    mem: dict[int, int] = {}
    base = 0x2000
    species_info = 0x08000000
    sizeof_si = 28
    target = 412
    row_ptr = species_info + target * sizeof_si
    place_mailbox(
        mem,
        base,
        version=VERSION,
        count=16,
        speciesInfo=species_info,
        levelUpLearnsets=0x08010000,
        sizeofSpeciesInfo=sizeof_si,
        targetSpecies=target,
        speciesInfoRowPtr=row_ptr,
        levelUpLearnsetEntryAddr=0x08020000 + target * 4,
    )
    emu = EmuShim(mem)
    assert find_mailbox(emu, 0x1000, 0x3000) == base
    assert validate_mailbox(emu, base)[0]
    mb = read_mailbox(emu, base)
    assert mb["magic"] == MAGIC and mb["trailMagic"] == TRAIL
    assert mb["version"] == VERSION and mb["count"] == 16
    assert mb["targetSpecies"] == target
    assert mb["speciesInfoRowPtr"] == row_ptr
    assert row_ptr_matches_computed(emu, base)

    mem2: dict[int, int] = {}
    place_mailbox(
        mem2,
        0x5000,
        version=99,
        count=1,
        speciesInfo=0,
        levelUpLearnsets=0,
        sizeofSpeciesInfo=1,
        targetSpecies=0,
        speciesInfoRowPtr=0,
        levelUpLearnsetEntryAddr=0,
    )
    assert not validate_mailbox(EmuShim(mem2), 0x5000)[0]

    assert species_info_row_ptr_from_base(0x08000000, 5, 28) == 0x08000000 + 5 * 28

    print("OK: mailbox_logic_test.py (all assertions passed)")


if __name__ == "__main__":
    main()
