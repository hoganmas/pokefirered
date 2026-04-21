-- Bootstrap/wiring for reserved species mailbox modules.

local function getThisScriptDir()
    local info = debug.getinfo(1, "S")
    if info and info.source and info.source:sub(1, 1) == "@" then
        return (info.source:sub(2):gsub("[/\\][^/\\]*$", ""))
    end
    return "."
end

return function(M, _dbg)
    local thisScriptDir = getThisScriptDir()
    local function loadMailboxModule(filename)
        return dofile(thisScriptDir .. "/" .. filename)
    end

    -- Shared attach / Prompt Stone state.
    local _attachState = { cbid = nil, base = nil, promptStoneSlotCursor = 0 }
    local _promptStonePollId = nil
    local _promptStoneLoggedReq = {}
    local _bridgeReqSent = {}
    local _prevNppStatus = {}
    local _promptStoneAssignedSpecies = {}
    local _reservedSpeciesAllocated = {}

    local _busMod = loadMailboxModule("reserved_species_mailbox_bus.lua")
    local _bus = _busMod(M)

    local _speciesMod = loadMailboxModule("reserved_species_mailbox_species.lua")
    local _species = _speciesMod({
        M = M,
        _dbg = _dbg,
        r8 = _bus.r8,
        w8 = _bus.w8,
        w32 = _bus.w32,
        r32 = _bus.r32,
    })

    local _runtimeMod = loadMailboxModule("reserved_species_mailbox_runtime.lua")
    local _runtime = _runtimeMod({
        M = M,
        _dbg = _dbg,
        trimPath = _bus.trimPath,
        shellSucceeded = _bus.shellSucceeded,
        readFileMaybe = _bus.readFileMaybe,
        w8 = _bus.w8,
    })

    local _psAllocMod = loadMailboxModule("reserved_species_mailbox_promptstone_alloc.lua")
    local _psAlloc = _psAllocMod({
        M = M,
        _attachState = _attachState,
        _reservedSpeciesAllocated = _reservedSpeciesAllocated,
    })

    local _httpMod = loadMailboxModule("reserved_species_mailbox_http.lua")
    local _http = _httpMod(M)

    return {
        -- State
        _attachState = _attachState,
        _promptStonePollId = _promptStonePollId,
        _promptStoneLoggedReq = _promptStoneLoggedReq,
        _bridgeReqSent = _bridgeReqSent,
        _prevNppStatus = _prevNppStatus,
        _promptStoneAssignedSpecies = _promptStoneAssignedSpecies,
        _reservedSpeciesAllocated = _reservedSpeciesAllocated,

        -- Bus helpers
        r32 = _bus.r32,
        r16 = _bus.r16,
        r8 = _bus.r8,
        w32 = _bus.w32,
        w16 = _bus.w16,
        w8 = _bus.w8,
        shellSucceeded = _bus.shellSucceeded,
        readFileMaybe = _bus.readFileMaybe,
        trimPath = _bus.trimPath,

        -- Other module exports
        encodeGen3Text = _species.encodeGen3Text,
        pickRandomRsDexWithSprites = _runtime.pickRandomRsDexWithSprites,
        nextPromptStoneReservedSlotIndex = _psAlloc.nextPromptStoneReservedSlotIndex,
        reserveNextPromptStoneSpeciesId = _psAlloc.reserveNextPromptStoneSpeciesId,
        nextReservedSpeciesIdAfter = _psAlloc.nextReservedSpeciesIdAfter,
        jsonEscapeForBridge = _http.jsonEscapeForBridge,
        pokegenHttpPostCurl = _http.pokegenHttpPostCurl,
        pokegenHttpGetCurl = _http.pokegenHttpGetCurl,
        parsePokegenPayloadResponse = _http.parsePokegenPayloadResponse,
    }
end
