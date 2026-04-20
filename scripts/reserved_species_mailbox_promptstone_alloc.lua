-- Prompt Stone reserved-slot allocation helpers (loaded by reserved_species_mailbox.lua).

return function(deps)
    local M = deps.M
    local _attachState = deps._attachState
    local _reservedSpeciesAllocated = deps._reservedSpeciesAllocated

    local function nextPromptStoneReservedSlotIndex(count)
        local skip = M.PROMPT_STONE_SKIP_INITIAL_RESERVED_SLOTS or 0
        if not count or count <= 0 then
            return 0
        end
        if skip >= count then
            skip = 0
        end
        local usable = count - skip
        if usable <= 0 then
            return 0
        end
        local idx = _attachState.promptStoneSlotCursor % usable
        _attachState.promptStoneSlotCursor = _attachState.promptStoneSlotCursor + 1
        return skip + idx
    end

    -- Reserve a target reserved species id for this request.
    -- Prefer rows not yet assigned this session, and avoid selecting prevSpecies when possible.
    local function reserveNextPromptStoneSpeciesId(mb, prevSpecies)
        local count = mb and mb.count or 0
        if count <= 0 or not mb.targetSpecies then
            return nil, nil
        end
        local skip = M.PROMPT_STONE_SKIP_INITIAL_RESERVED_SLOTS or 0
        if skip >= count then
            skip = 0
        end
        local usable = count - skip
        if usable <= 0 then
            return nil, nil
        end
        local start = _attachState.promptStoneSlotCursor % usable
        local chosenIdx = nil
        local chosenSlot = nil
        local chosenSpecies = nil

        local function tryPick(requireFresh, avoidPrev)
            for off = 0, usable - 1 do
                local idx = (start + off) % usable
                local slot = skip + idx
                local species = mb.targetSpecies + slot
                if (not avoidPrev or species ~= prevSpecies) and (not requireFresh or not _reservedSpeciesAllocated[species]) then
                    chosenIdx = idx
                    chosenSlot = slot
                    chosenSpecies = species
                    return true
                end
            end
            return false
        end

        if not tryPick(true, true) then
            if not tryPick(false, true) then
                tryPick(false, false)
            end
        end
        if not chosenSpecies then
            return nil, nil
        end
        local delta = (chosenIdx - start + usable) % usable
        _attachState.promptStoneSlotCursor = _attachState.promptStoneSlotCursor + delta + 1
        _reservedSpeciesAllocated[chosenSpecies] = true
        return chosenSpecies, chosenSlot
    end

    -- When pokegen returns result_species == party species, the evolution scene will not run and ROM patches
    -- would stomp the same gSpeciesInfo row. Return the next species id inside the reserved mailbox window.
    local function nextReservedSpeciesIdAfter(mb, prev)
        local first = mb.targetSpecies
        local n = mb.count
        if not first or not n or n <= 0 then
            return nil
        end
        local last = first + n - 1
        local skip = M.PROMPT_STONE_SKIP_INITIAL_RESERVED_SLOTS or 0
        local floorId = first + math.min(skip, math.max(0, n - 1))
        if prev < first or prev > last then
            return nil
        end
        if prev < last then
            return prev + 1
        end
        return floorId
    end

    return {
        nextPromptStoneReservedSlotIndex = nextPromptStoneReservedSlotIndex,
        reserveNextPromptStoneSpeciesId = reserveNextPromptStoneSpeciesId,
        nextReservedSpeciesIdAfter = nextReservedSpeciesIdAfter,
    }
end
