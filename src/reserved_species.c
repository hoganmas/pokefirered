#include "global.h"
#include "reserved_species.h"
#include "pokemon.h"
#include "data.h" // gMonShinyPaletteTable
#include "constants/reserved_species_config.h"

EWRAM_DATA struct ReservedSpeciesScriptMailbox gReservedSpeciesScriptMailbox = {0};

// Emulator/runtime scripting may overwrite these ROM bytes (not possible on a real cartridge).
ALIGNED(4) const u8 gReservedRuntimeRomLzScratch[RESERVED_RUNTIME_ROM_SCRATCH_SIZE] __attribute__((section(".rom_runtime_lz"))) = {0};

STATIC_ASSERT(sizeof(struct ReservedSpeciesScriptMailbox) == 72, ReservedSpeciesMailboxLayout);

void ReservedSpecies_InitScriptMailbox(void)
{
    const u16 target = SPECIES_CHIMECHO + 1;

    gReservedSpeciesScriptMailbox.magic = RESERVED_SPECIES_MAILBOX_MAGIC;
    gReservedSpeciesScriptMailbox.version = 2;
    gReservedSpeciesScriptMailbox.count = NUM_RESERVED_CUSTOM_SPECIES;
    gReservedSpeciesScriptMailbox.speciesInfo = (u32)gSpeciesInfo;
    gReservedSpeciesScriptMailbox.levelUpLearnsets = (u32)gLevelUpLearnsets;
    gReservedSpeciesScriptMailbox.monFrontPicTable = (u32)gMonFrontPicTable;
    gReservedSpeciesScriptMailbox.monBackPicTable = (u32)gMonBackPicTable;
    gReservedSpeciesScriptMailbox.monPaletteTable = (u32)gMonPaletteTable;
    gReservedSpeciesScriptMailbox.monShinyPaletteTable = (u32)gMonShinyPaletteTable;
    gReservedSpeciesScriptMailbox.speciesNames = (u32)gSpeciesNames;
    gReservedSpeciesScriptMailbox.sizeofSpeciesInfo = sizeof(struct SpeciesInfo);
    gReservedSpeciesScriptMailbox.targetSpecies = target;
    gReservedSpeciesScriptMailbox.padding16 = 0;
    gReservedSpeciesScriptMailbox.speciesInfoRowPtr = (u32)&gSpeciesInfo[target];
    gReservedSpeciesScriptMailbox.levelUpLearnsetEntryAddr = (u32)&gLevelUpLearnsets[target];
    {
        const u32 romScratch = (u32)gReservedRuntimeRomLzScratch;

        gReservedSpeciesScriptMailbox.runtimeFrontLzAddr = romScratch;
        gReservedSpeciesScriptMailbox.runtimeBackLzAddr = romScratch + RESERVED_RUNTIME_FRONT_LZ_CAP;
        gReservedSpeciesScriptMailbox.runtimePalLzAddr = romScratch + RESERVED_RUNTIME_FRONT_LZ_CAP + RESERVED_RUNTIME_BACK_LZ_CAP;
        gReservedSpeciesScriptMailbox.runtimeShinyPalLzAddr =
            romScratch + RESERVED_RUNTIME_FRONT_LZ_CAP + RESERVED_RUNTIME_BACK_LZ_CAP + RESERVED_RUNTIME_PAL_LZ_CAP;
    }
    gReservedSpeciesScriptMailbox.trailMagic = RESERVED_SPECIES_MAILBOX_TRAIL;
    ReservedSpecies_MgbaScriptHandshake();
}

void ReservedSpecies_MgbaScriptHandshake(void)
{
}
