#include "global.h"
#include "reserved_species.h"
#include "pokemon.h"
#include "data.h"
#include "constants/reserved_species_config.h"

EWRAM_DATA struct ReservedSpeciesScriptMailbox gReservedSpeciesScriptMailbox = {0};

STATIC_ASSERT(sizeof(struct ReservedSpeciesScriptMailbox) == 52, ReservedSpeciesMailboxLayout);

void ReservedSpecies_InitScriptMailbox(void)
{
    const u16 target = SPECIES_CHIMECHO + 1;

    gReservedSpeciesScriptMailbox.magic = RESERVED_SPECIES_MAILBOX_MAGIC;
    gReservedSpeciesScriptMailbox.version = 1;
    gReservedSpeciesScriptMailbox.count = NUM_RESERVED_CUSTOM_SPECIES;
    gReservedSpeciesScriptMailbox.speciesInfo = (u32)gSpeciesInfo;
    gReservedSpeciesScriptMailbox.levelUpLearnsets = (u32)gLevelUpLearnsets;
    gReservedSpeciesScriptMailbox.monFrontPicTable = (u32)gMonFrontPicTable;
    gReservedSpeciesScriptMailbox.monBackPicTable = (u32)gMonBackPicTable;
    gReservedSpeciesScriptMailbox.monPaletteTable = (u32)gMonPaletteTable;
    gReservedSpeciesScriptMailbox.speciesNames = (u32)gSpeciesNames;
    gReservedSpeciesScriptMailbox.sizeofSpeciesInfo = sizeof(struct SpeciesInfo);
    gReservedSpeciesScriptMailbox.targetSpecies = target;
    gReservedSpeciesScriptMailbox.padding16 = 0;
    gReservedSpeciesScriptMailbox.speciesInfoRowPtr = (u32)&gSpeciesInfo[target];
    gReservedSpeciesScriptMailbox.levelUpLearnsetEntryAddr = (u32)&gLevelUpLearnsets[target];
    gReservedSpeciesScriptMailbox.trailMagic = RESERVED_SPECIES_MAILBOX_TRAIL;
    ReservedSpecies_MgbaScriptHandshake();
}

void ReservedSpecies_MgbaScriptHandshake(void)
{
}
