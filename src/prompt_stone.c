#include "global.h"
#include "gflib.h"
#include "characters.h"
#include "string.h"
#include "strings.h"
#include "task.h"
#include "party_menu.h"
#include "pokemon.h"
#include "naming_screen.h"
#include "reserved_species.h"
#include "item.h"
#include "item_use.h"
#include "field_message_box.h"
#include "quest_log.h"
#include "overworld.h"
#include "prompt_stone.h"
#include "script.h"
#include "evolution_scene.h"
#include "constants/items.h"
#include "constants/songs.h"
#include "constants/species.h"

extern const u8 gText_CantBeUsedOnPkmn[];

static EWRAM_DATA u8 sPromptStonePendingSlot = 0;
static EWRAM_DATA u8 sPromptStonePartyIndex = 0;

static void Task_PromptStoneWaitForResolution(u8 taskId);
static void Task_PromptStoneWaitFieldMessageThenOpenMenu(u8 taskId);
static void Task_PromptStoneAfterTextUnlock(u8 taskId);

/* CreateTask must not run until after ResumeMap/ResetTasks when returning from naming. */
static bool8 FieldCB_PromptStone_CreateWaitTask(void);
static bool8 FieldCB_PromptStone_CreateFieldMessageThenMenuTask(void);

static void PromptStone_ShowFieldMessageThenUnlock(const u8 *msg)
{
    LockPlayerFieldControls();
    ShowFieldMessage(msg);
    CreateTask(Task_PromptStoneAfterTextUnlock, 0x50);
}

static void Task_PromptStoneAfterTextUnlock(u8 taskId)
{
    if (IsFieldMessageBoxHidden() == TRUE)
    {
        UnlockPlayerFieldControls();
        DestroyTask(taskId);
    }
}

static void PromptStone_OnRequestFinished(u8 waitTaskId, bool8 failed)
{
    struct Pokemon *mon;
    u16 curSpecies;
    u16 targetSpecies;
    u16 prevSpeciesSnapshot;
    u16 resultSpeciesSnapshot;

    // Snapshot before hiding UI; host may share gNewPokemonInfo with tooling.
    resultSpeciesSnapshot = gNewPokemonInfo.resultSpecies;
    prevSpeciesSnapshot = gNewPokemonInfo.prevEvolutionSpecies;

    HideFieldMessageBox();
    DestroyTask(waitTaskId);

    if (failed)
    {
        UnlockPlayerFieldControls();
        PromptStone_ShowFieldMessageThenUnlock(gText_PromptStoneFailed);
        return;
    }

    if (sPromptStonePartyIndex >= PARTY_SIZE)
    {
        UnlockPlayerFieldControls();
        PromptStone_ShowFieldMessageThenUnlock(gText_PromptStoneProcessed);
        return;
    }

    mon = &gPlayerParty[sPromptStonePartyIndex];
    curSpecies = GetMonData(mon, MON_DATA_SPECIES);
    if (curSpecies != prevSpeciesSnapshot)
    {
        UnlockPlayerFieldControls();
        PromptStone_ShowFieldMessageThenUnlock(gText_PromptStonePartyChanged);
        return;
    }

    targetSpecies = resultSpeciesSnapshot;
    if (targetSpecies != SPECIES_NONE
        && targetSpecies != SPECIES_EGG
        && targetSpecies != curSpecies)
    {
        UnlockPlayerFieldControls();
        gCB2_AfterEvolution = CB2_ReturnToField;
        BeginEvolutionScene(mon, targetSpecies, TRUE, sPromptStonePartyIndex);
        return;
    }

    UnlockPlayerFieldControls();
    PromptStone_ShowFieldMessageThenUnlock(gText_PromptStoneProcessed);
}

void CB2_PromptStoneAfterPartyClose(void)
{
    struct Pokemon *mon = &gPlayerParty[gPartyMenu.slotId];
    u16 species = GetMonData(mon, MON_DATA_SPECIES);
    u32 personality = GetMonData(mon, MON_DATA_PERSONALITY);
    u8 gender = GetMonGender(mon);

    if (species == SPECIES_NONE || species == SPECIES_EGG)
    {
        PlaySE(SE_SELECT);
        ShowFieldMessage(gText_CantBeUsedOnPkmn);
        gFieldCallback2 = FieldCB_PromptStone_CreateFieldMessageThenMenuTask;
        SetMainCallback2(CB2_ReturnToField);
        return;
    }

    sPromptStonePartyIndex = gPartyMenu.slotId;
    memset(gNewPokemonInfo.promptText, EOS, sizeof(gNewPokemonInfo.promptText));
    gNewPokemonInfo.prevEvolutionSpecies = species;
    gNewPokemonInfo.resultSpecies = SPECIES_NONE;
    DoNamingScreen(NAMING_SCREEN_PROMPT_STONE, gNewPokemonInfo.promptText, species, gender, personality, CB2_PromptStoneAfterNaming);
}

void CB2_PromptStoneAfterNaming(void)
{
    u8 slot = ReservedSpecies_AllocPendingNewPokemonRequest();

    if (slot == 0xFF)
    {
        ShowFieldMessage(gText_PromptStoneQueueFull);
        gFieldCallback2 = FieldCB_PromptStone_CreateFieldMessageThenMenuTask;
        SetMainCallback2(CB2_ReturnToField);
        return;
    }

    sPromptStonePendingSlot = slot;
    RemoveBagItem(ITEM_PROMPT_STONE, 1);
    ItemUse_SetQuestLogEvent(QL_EVENT_USED_ITEM, &gPlayerParty[gPartyMenu.slotId], ITEM_PROMPT_STONE, 0xFFFF);
    gFieldCallback2 = FieldCB_PromptStone_CreateWaitTask;
    SetMainCallback2(CB2_ReturnToField);
}

static bool8 FieldCB_PromptStone_CreateWaitTask(void)
{
    CreateTask(Task_PromptStoneWaitForResolution, 0x50);
    return TRUE;
}

static bool8 FieldCB_PromptStone_CreateFieldMessageThenMenuTask(void)
{
    CreateTask(Task_PromptStoneWaitFieldMessageThenOpenMenu, 0x50);
    return TRUE;
}

/*
 * data[0] wait phase:
 *   0 = show "used item on Pokémon"
 *   1 = wait until that message is dismissed
 *   2 = show "..." and poll host/Lua for DONE/FAILED
 * data[1] = 1 once the "used item" message has been shown (avoids skipping if the box is briefly "hidden").
 */
static void Task_PromptStoneWaitForResolution(u8 taskId)
{
    u8 slot = sPromptStonePendingSlot;
    s16 *phase = &gTasks[taskId].data[0];

    switch (*phase)
    {
    case 0:
        LockPlayerFieldControls();
        gTasks[taskId].data[1] = 0;
        GetMonNickname(&gPlayerParty[sPromptStonePartyIndex], gStringVar1);
        CopyItemName(ITEM_PROMPT_STONE, gStringVar2);
        StringExpandPlaceholders(gStringVar4, gText_PromptStoneUsedOn);
        ShowFieldMessage(gStringVar4);
        *phase = 1;
        break;
    case 1:
        if (IsFieldMessageBoxHidden() != TRUE)
            gTasks[taskId].data[1] = 1;
        if (gTasks[taskId].data[1] != 0 && IsFieldMessageBoxHidden() == TRUE)
        {
            ShowFieldMessage(gText_PromptStoneWaiting);
            *phase = 2;
        }
        break;
    case 2:
        if (gNewPokemonPending[slot].status == NEW_POKEMON_REQ_FAILED)
            PromptStone_OnRequestFinished(taskId, TRUE);
        else if (gNewPokemonPending[slot].status == NEW_POKEMON_REQ_DONE)
            PromptStone_OnRequestFinished(taskId, FALSE);
        break;
    }
}

static void Task_PromptStoneWaitFieldMessageThenOpenMenu(u8 taskId)
{
    if (IsFieldMessageBoxHidden() == TRUE)
    {
        SetMainCallback2(CB2_ReturnToFieldWithOpenMenu);
        DestroyTask(taskId);
    }
}
