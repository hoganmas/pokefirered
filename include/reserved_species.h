#ifndef GUARD_RESERVED_SPECIES_H
#define GUARD_RESERVED_SPECIES_H

#include "global.h"

// Written once at boot for external tooling (mGBA Lua, etc.). Bus addresses (0x08… ROM, 0x02… EWRAM).
struct ReservedSpeciesScriptMailbox
{
    u32 magic; // RESERVED_SPECIES_MAILBOX_MAGIC
    u16 version;
    u16 count; // mirrors NUM_RESERVED_CUSTOM_SPECIES
    u32 speciesInfo;
    u32 levelUpLearnsets;
    u32 monFrontPicTable;
    u32 monBackPicTable;
    u32 monPaletteTable;
    u32 speciesNames;
    u32 sizeofSpeciesInfo;
};

#define RESERVED_SPECIES_MAILBOX_MAGIC 0x31505352u // 'RSP1' when viewed as little-endian bytes

extern struct ReservedSpeciesScriptMailbox gReservedSpeciesScriptMailbox;

void ReservedSpecies_InitScriptMailbox(void);
// Empty body; set an mGBA execution breakpoint here to run after the mailbox is filled.
void ReservedSpecies_MgbaScriptHandshake(void);

/*
  mGBA Lua (see https://mgba.io/docs/scripting.html and the newer dev docs):

  - After boot, `gReservedSpeciesScriptMailbox` is filled with bus addresses (ROM for tables,
    EWRAM for this struct). Find its address in pokefirered.map / pokefirered.sym, or set an
    execution breakpoint on `ReservedSpecies_MgbaScriptHandshake` (dev builds expose
    `emu:setBreakpoint(callback, address)` on CoreAdapter) and read the mailbox from RAM.

  Example (addresses are build-specific; replace 0x0203f470 after checking your map):
    local m = 0x0203f470
    if emu:read32(m) == 0x31505352 then
      console:log(string.format("gSpeciesInfo @ %08X", emu:read32(m + 8)))
    end
*/

#endif // GUARD_RESERVED_SPECIES_H
