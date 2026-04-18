#ifndef GUARD_RESERVED_SPECIES_H
#define GUARD_RESERVED_SPECIES_H

#include "global.h"

// LZ staging caps for mGBA runtime uploads (see tools/runtime_reserved_png_to_lz.py + reserved_species_mailbox.lua).
// Payloads live in a dedicated ROM scratch region (not EWRAM); the emulator patches those bytes when applying PNGs.
#define RESERVED_RUNTIME_FRONT_LZ_CAP 0x3000u
#define RESERVED_RUNTIME_BACK_LZ_CAP 0x3000u
#define RESERVED_RUNTIME_PAL_LZ_CAP 0x200u
#define RESERVED_RUNTIME_ROM_SCRATCH_SIZE \
    (RESERVED_RUNTIME_FRONT_LZ_CAP + RESERVED_RUNTIME_BACK_LZ_CAP + RESERVED_RUNTIME_PAL_LZ_CAP + RESERVED_RUNTIME_PAL_LZ_CAP)

// Written once at boot for external tooling (mGBA Lua, etc.). Bus addresses (0x08… ROM, 0x02… EWRAM).
// Layout is duplicated in tools/mgba_scripts/reserved_species_mailbox.lua (OFFSET_*).
struct ReservedSpeciesScriptMailbox
{
    u32 magic; // RESERVED_SPECIES_MAILBOX_MAGIC
    u16 version; // 3: runtimeRomScratchEndExclusive + LZ slot pointers (see getRuntimeLzScratchLayout in mailbox Lua)
    u16 count; // mirrors NUM_RESERVED_CUSTOM_SPECIES
    u32 speciesInfo;           // &gSpeciesInfo[0]
    u32 levelUpLearnsets;      // &gLevelUpLearnsets[0]
    u32 monFrontPicTable;
    u32 monBackPicTable;
    u32 monPaletteTable;
    u32 speciesNames;
    u32 sizeofSpeciesInfo;
    u16 targetSpecies;         // species id used for rowPtr fields below (default: first reserved slot)
    u16 padding16;
    u32 speciesInfoRowPtr;     // &gSpeciesInfo[targetSpecies]
    u32 levelUpLearnsetEntryAddr; // &gLevelUpLearnsets[targetSpecies] (ROM slot holding const u16*)
    u32 runtimeFrontLzAddr;    // ROM scratch: LZ77 front tiles (Lua fills, then patches monFrontPicTable row)
    u32 runtimeBackLzAddr;
    u32 runtimePalLzAddr;
    u32 runtimeShinyPalLzAddr;
    u32 monShinyPaletteTable;  // &gMonShinyPaletteTable[0]
    // One-past-end bus address for gReservedRuntimeRomLzScratch[] (Lua derives per-slot LZ max from gaps).
    u32 runtimeRomScratchEndExclusive;
    u32 trailMagic; // RESERVED_SPECIES_MAILBOX_TRAIL — verifies struct size for Lua scan
};

#define RESERVED_SPECIES_MAILBOX_MAGIC 0x31505352u // 'RSP1' when viewed as little-endian bytes
#define RESERVED_SPECIES_MAILBOX_TRAIL 0x544C4252u // 'RLBT' — end marker for bounds checks

extern struct ReservedSpeciesScriptMailbox gReservedSpeciesScriptMailbox;
extern const u8 gReservedRuntimeRomLzScratch[RESERVED_RUNTIME_ROM_SCRATCH_SIZE];

void ReservedSpecies_InitScriptMailbox(void);
// Empty body; set an mGBA execution breakpoint here after boot — Lua reads gReservedSpeciesScriptMailbox
// (including runtime LZ ROM pointers and runtimeRomScratchEndExclusive) from EWRAM; no fixed addresses in scripts.
void ReservedSpecies_MgbaScriptHandshake(void);

/*
  mGBA: load tools/mgba_scripts/reserved_species_mailbox.lua (Scripting window), then
  ReservedSpeciesMailbox.attach() to scan EWRAM for magic+trail and read row pointers.

  Runtime PNG → LZ77 + ROM table patches (host-side convert, emu writes): ReservedSpeciesMailbox.applyRuntimePngPair(...)
  Pass the real pokefirered path as the last arg (mGBA Lua); placeholder paths make conversion fail.
  Slot addresses and max LZ sizes come from the mailbox (ReservedSpeciesMailbox.getRuntimeLzScratchLayout); do not hardcode ROM.

  Tests (no emulator): make test-mailbox-lua, make test-mailbox-runtime
*/

#endif // GUARD_RESERVED_SPECIES_H
