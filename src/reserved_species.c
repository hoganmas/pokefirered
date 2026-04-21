#include "global.h"
#include "reserved_species.h"
#include "pokemon.h"
#include "data.h" // gMonShinyPaletteTable
#include "pokemon_icon.h"
#include "constants/reserved_species_config.h"
#include "constants/pokedex.h"

EWRAM_DATA static u32 sNextNewPokemonRequestId = 1;

EWRAM_DATA struct ReservedSpeciesScriptMailbox gReservedSpeciesScriptMailbox = {0};
EWRAM_DATA struct NewPokemonInfo gNewPokemonInfo = {0};
EWRAM_DATA struct NewPokemonPendingSlot gNewPokemonPending[NEW_POKEMON_PENDING_MAX] = {0};
ALIGNED(4) const u8 gReservedSpeciesPokedexCategory[NUM_RESERVED_CUSTOM_SPECIES][RESERVED_POKEDEX_CATEGORY_TEXT_LEN + 1] = {0};
ALIGNED(4) const u8 gReservedSpeciesPokedexDescription[NUM_RESERVED_CUSTOM_SPECIES][RESERVED_POKEDEX_DESCRIPTION_TEXT_LEN + 1] = {0};
ALIGNED(4) const u16 gReservedRuntimeLevelUpLearnsets[NUM_RESERVED_CUSTOM_SPECIES][MAX_LEVEL_UP_MOVES + 1] = {0};

// Emulator/runtime scripting may overwrite these ROM bytes (not possible on a real cartridge).
ALIGNED(4) const u8 gReservedRuntimeRomLzScratch[RESERVED_RUNTIME_ROM_SCRATCH_SIZE] = {0};

extern const u8 *const gMonFootprintTable[];

STATIC_ASSERT(sizeof(struct ReservedSpeciesScriptMailbox) == 120, ReservedSpeciesMailboxLayout);
STATIC_ASSERT(sizeof(struct NewPokemonInfo) == 132, NewPokemonInfoLayout);
STATIC_ASSERT(sizeof(struct NewPokemonPendingSlot) == 8, NewPokemonPendingSlotLayout);

static s16 ReservedSpecies_NdexToSlot(u16 nationalDex)
{
    if (nationalDex < NATIONAL_DEX_RESERVED_CUSTOM_FIRST || nationalDex > NATIONAL_DEX_RESERVED_CUSTOM_LAST)
        return -1;
    return (s16)(nationalDex - NATIONAL_DEX_RESERVED_CUSTOM_FIRST);
}

u8 ReservedSpecies_AllocPendingNewPokemonRequest(void)
{
    u32 i;

    if (sNextNewPokemonRequestId == 0) // EWRAM can be zero before .data init in some loads
        sNextNewPokemonRequestId = 1;

    for (i = 0; i < NEW_POKEMON_PENDING_MAX; i++)
    {
        if (gNewPokemonPending[i].status == NEW_POKEMON_REQ_EMPTY
            || gNewPokemonPending[i].status == NEW_POKEMON_REQ_DONE
            || gNewPokemonPending[i].status == NEW_POKEMON_REQ_FAILED)
        {
            gNewPokemonPending[i].requestId = sNextNewPokemonRequestId++;
            gNewPokemonPending[i].status = NEW_POKEMON_REQ_PENDING;
            // Shared payload; clear so host/Lua cannot leave a stale result from a prior completion.
            gNewPokemonInfo.resultSpecies = SPECIES_NONE;
            return (u8)i;
        }
    }
    return 0xFF;
}

bool8 ReservedSpecies_GetPokedexTextPtrsByNationalDex(u16 nationalDex, const u8 **outCategory, const u8 **outDescription)
{
    bool8 any = FALSE;
    s16 slot = ReservedSpecies_NdexToSlot(nationalDex);

    if (slot < 0)
        return FALSE;
    if (outCategory != NULL
        && gReservedSpeciesPokedexCategory[slot][0] != 0
        && gReservedSpeciesPokedexCategory[slot][0] != 0xFF)
    {
        *outCategory = gReservedSpeciesPokedexCategory[slot];
        any = TRUE;
    }
    if (outDescription != NULL
        && gReservedSpeciesPokedexDescription[slot][0] != 0
        && gReservedSpeciesPokedexDescription[slot][0] != 0xFF)
    {
        *outDescription = gReservedSpeciesPokedexDescription[slot];
        any = TRUE;
    }
    return any;
}

void ReservedSpecies_InitScriptMailbox(void)
{
    const u16 target = SPECIES_CHIMECHO + 1;

    gReservedSpeciesScriptMailbox.magic = RESERVED_SPECIES_MAILBOX_MAGIC;
    gReservedSpeciesScriptMailbox.version = 7;
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
    gReservedSpeciesScriptMailbox.pokedexCategoryText = (u32)&gReservedSpeciesPokedexCategory[0][0];
    gReservedSpeciesScriptMailbox.pokedexDescriptionText = (u32)&gReservedSpeciesPokedexDescription[0][0];
    gReservedSpeciesScriptMailbox.pokedexCategoryStride = sizeof(gReservedSpeciesPokedexCategory[0]);
    gReservedSpeciesScriptMailbox.pokedexDescriptionStride = sizeof(gReservedSpeciesPokedexDescription[0]);
    gReservedSpeciesScriptMailbox.reservedLearnsetData = (u32)&gReservedRuntimeLevelUpLearnsets[0][0];
    gReservedSpeciesScriptMailbox.reservedLearnsetStride = sizeof(gReservedRuntimeLevelUpLearnsets[0]);
    gReservedSpeciesScriptMailbox.reservedLearnsetMaxEntries = MAX_LEVEL_UP_MOVES + 1;
    gReservedSpeciesScriptMailbox.monIconTable = (u32)gMonIconTable;
    gReservedSpeciesScriptMailbox.monFootprintTable = (u32)gMonFootprintTable;
    {
        const u32 romScratch = (u32)gReservedRuntimeRomLzScratch;

        gReservedSpeciesScriptMailbox.runtimeFrontLzAddr = romScratch;
        gReservedSpeciesScriptMailbox.runtimeBackLzAddr = romScratch + RESERVED_RUNTIME_FRONT_LZ_CAP;
        gReservedSpeciesScriptMailbox.runtimePalLzAddr = romScratch + RESERVED_RUNTIME_FRONT_LZ_CAP + RESERVED_RUNTIME_BACK_LZ_CAP;
        gReservedSpeciesScriptMailbox.runtimeShinyPalLzAddr =
            romScratch + RESERVED_RUNTIME_FRONT_LZ_CAP + RESERVED_RUNTIME_BACK_LZ_CAP + RESERVED_RUNTIME_PAL_LZ_CAP;
        gReservedSpeciesScriptMailbox.runtimeIconAddr =
            romScratch + RESERVED_RUNTIME_FRONT_LZ_CAP + RESERVED_RUNTIME_BACK_LZ_CAP + RESERVED_RUNTIME_PAL_LZ_CAP + RESERVED_RUNTIME_PAL_LZ_CAP;
        gReservedSpeciesScriptMailbox.runtimeFootprintAddr =
            gReservedSpeciesScriptMailbox.runtimeIconAddr + RESERVED_RUNTIME_ICON_DATA_CAP;
        gReservedSpeciesScriptMailbox.runtimeRomScratchEndExclusive = romScratch + RESERVED_RUNTIME_ROM_SCRATCH_SIZE;
    }
    gReservedSpeciesScriptMailbox.newPokemonInfo = (u32)&gNewPokemonInfo;
    gReservedSpeciesScriptMailbox.newPokemonPendingSlots = (u32)&gNewPokemonPending[0];
    gReservedSpeciesScriptMailbox.trailMagic = RESERVED_SPECIES_MAILBOX_TRAIL;
    ReservedSpecies_MgbaScriptHandshake();
}

void ReservedSpecies_MgbaScriptHandshake(void)
{
}
