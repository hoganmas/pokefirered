#ifndef GUARD_RESERVED_SPECIES_H
#define GUARD_RESERVED_SPECIES_H

#include "global.h"

// Written once at boot for external tooling (mGBA Lua, etc.). Bus addresses (0x08… ROM, 0x02… EWRAM).
// Layout is duplicated in tools/mgba_scripts/reserved_species_mailbox.lua (OFFSET_*).
struct ReservedSpeciesScriptMailbox
{
    u32 magic; // RESERVED_SPECIES_MAILBOX_MAGIC
    u16 version;
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
    u32 trailMagic;            // RESERVED_SPECIES_MAILBOX_TRAIL — verifies struct size for Lua scan
};

#define RESERVED_SPECIES_MAILBOX_MAGIC 0x31505352u // 'RSP1' when viewed as little-endian bytes
#define RESERVED_SPECIES_MAILBOX_TRAIL 0x544C4252u // 'RLBT' — end marker for bounds checks

extern struct ReservedSpeciesScriptMailbox gReservedSpeciesScriptMailbox;

void ReservedSpecies_InitScriptMailbox(void);
// Empty body; set an mGBA execution breakpoint here to run after the mailbox is filled.
void ReservedSpecies_MgbaScriptHandshake(void);

/*
  mGBA: load tools/mgba_scripts/reserved_species_mailbox.lua (Scripting window), then
  ReservedSpeciesMailbox.attach() to scan EWRAM for magic+trail and read row pointers.

  Tests (no emulator): make test-mailbox-lua
*/

#endif // GUARD_RESERVED_SPECIES_H
