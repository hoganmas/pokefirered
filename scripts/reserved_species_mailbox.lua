-- Reserved species / scripting mailbox helpers for mGBA Lua.
-- Byte layout must match struct ReservedSpeciesScriptMailbox (include/reserved_species.h), 104 bytes.
--
-- mGBA: Tools → Scripting → Load this file, then: ReservedSpeciesMailbox.attach()
-- ROM patches use emu.memory.cart0 (etc.), not raw bus writes, to avoid "Unimplemented memory Store" on 0x08…
-- Tests: make test-mailbox-lua

local M = {}

local function _dbg(msg)
    if console and console.log then
        console:log("[ReservedSpeciesMailbox] " .. msg)
    else
        print("[ReservedSpeciesMailbox] " .. msg)
    end
end

_dbg("loaded")

M.MAGIC = 0x31505352
M.TRAIL = 0x544C4252
M.VERSION = 6
M.SPECIES_SHINY_TAG = 500
M.LEVEL_UP_MOVE_ID = 0x01FF
M.LEVEL_UP_MOVE_LV = 0xFE00
M.LEVEL_UP_END = 0xFFFF

M.OFFSET_MAGIC = 0
M.OFFSET_VERSION = 4
M.OFFSET_COUNT = 6
M.OFFSET_SPECIES_INFO = 8
M.OFFSET_LEVEL_UP_LEARNSETS = 12
M.OFFSET_MON_FRONT_PIC = 16
M.OFFSET_MON_BACK_PIC = 20
M.OFFSET_MON_PALETTE = 24
M.OFFSET_SPECIES_NAMES = 28
M.OFFSET_SIZEOF_SPECIES_INFO = 32
M.OFFSET_TARGET_SPECIES = 36
M.OFFSET_PADDING16 = 38
M.OFFSET_SPECIES_INFO_ROW_PTR = 40
M.OFFSET_LEVEL_UP_LEARNSET_ENTRY_ADDR = 44
M.OFFSET_RUNTIME_FRONT_LZ = 48
M.OFFSET_RUNTIME_BACK_LZ = 52
M.OFFSET_RUNTIME_PAL_LZ = 56
M.OFFSET_RUNTIME_SHINY_PAL_LZ = 60
M.OFFSET_MON_SHINY_PALETTE = 64
M.OFFSET_POKEDEX_CATEGORY_TEXT = 68
M.OFFSET_POKEDEX_DESCRIPTION_TEXT = 72
M.OFFSET_POKEDEX_CATEGORY_STRIDE = 76
M.OFFSET_POKEDEX_DESCRIPTION_STRIDE = 78
M.OFFSET_RESERVED_LEARNSET_DATA = 80
M.OFFSET_RESERVED_LEARNSET_STRIDE = 84
M.OFFSET_RESERVED_LEARNSET_MAX_ENTRIES = 86
M.OFFSET_RUNTIME_SCRATCH_END = 88
M.OFFSET_NEW_POKEMON_INFO = 92
M.OFFSET_NEW_POKEMON_PENDING = 96
M.OFFSET_TRAIL_MAGIC = 100

M.MAILBOX_SIZE = 104

-- struct NewPokemonInfo (include/reserved_species.h), minimal payload.
M.NEW_POKEMON_INFO_SIZE = 132
M.NEW_POKEMON_PENDING_SLOT_SIZE = 8
M.NEW_POKEMON_PENDING_MAX = 4
M.NEW_POKEMON_PROMPT_TEXT_LEN = 127
M.OFFSET_NPI_PREV_EVOLUTION_SPECIES = 0
M.OFFSET_NPI_PROMPT_TEXT = 2
M.OFFSET_NPI_RESULT_SPECIES = 130 -- u16; host writes before marking slot DONE (0 = no evolution scene)
M.OFFSET_NPP_STATUS = 0
M.OFFSET_NPP_REQUEST_ID = 4
M.NEW_POKEMON_REQ_PENDING = 1
M.NEW_POKEMON_REQ_DONE = 3
M.NEW_POKEMON_REQ_FAILED = 4
-- When true, mGBA Lua picks the next reserved species slot, clones ROM tables from the party mon's species
-- into that slot (stats, learnset pointer, front/back palettes), sets the species name from the prompt text,
-- writes resultSpecies, and marks DONE so the evolution scene can run without external tooling.
M.PROMPT_STONE_AUTO_STUB = true
-- Skip this many low reserved slots for Prompt Stone (slot 0 is often the build fixture, e.g. NEXOMON).
M.PROMPT_STONE_SKIP_INITIAL_RESERVED_SLOTS = 1
-- After cloning stats from the party mon, replace battle sprites with a random RS Gen III PNG pair (dex 1..386).
M.PROMPT_STONE_AUTO_RANDOM_RS_SPRITES = true
M.PROMPT_STONE_RS_SPRITE_DEX_MIN = 1
M.PROMPT_STONE_RS_SPRITE_DEX_MAX = 386
M.PROMPT_STONE_RS_SPRITE_PICK_TRIES = 48
-- Pokegen HTTP: mGBA Lua POSTs to pokegen-server via host `curl` (blocking; requires curl + io.popen or os.execute).
-- If result_species equals the party mon's species, Lua bumps to the next id in the reserved species window so evolution + ROM patches use a new row (repeat Prompt Stone on same mon).
M.POKEGEN_BRIDGE_ENABLED = true
M.POKEGEN_HTTP_URL = "http://127.0.0.1:8765/v1/generate"
M.POKEGEN_HTTP_MAX_TIME_SEC = 30
M.POKEMON_NAME_LENGTH = 10
M.SPECIES_NAME_STRIDE = M.POKEMON_NAME_LENGTH + 1
M.SPRITE_SHEET_ENTRY_SIZE = 8 -- sizeof(struct CompressedSpriteSheet)
M.PALETTE_ENTRY_SIZE = 8

local _init = dofile((debug.getinfo(1, "S").source:sub(2):gsub("[/\\][^/\\]*$", "")) .. "/reserved_species_mailbox_init.lua")(M, _dbg)
local _attachState = _init._attachState
local _promptStonePollId = _init._promptStonePollId
local _promptStoneLoggedReq = _init._promptStoneLoggedReq
local _bridgeReqSent = _init._bridgeReqSent
local _prevNppStatus = _init._prevNppStatus
local _promptStoneAssignedSpecies = _init._promptStoneAssignedSpecies
local _reservedSpeciesAllocated = _init._reservedSpeciesAllocated
local r32 = _init.r32
local r16 = _init.r16
local r8 = _init.r8
local w32 = _init.w32
local w16 = _init.w16
local w8 = _init.w8
local shellSucceeded = _init.shellSucceeded
local readFileMaybe = _init.readFileMaybe
local trimPath = _init.trimPath

local _moveNameToId = nil
local function loadMoveNameTable()
    if _moveNameToId then
        return _moveNameToId
    end
    local t = {}
    local root = trimPath(M._REPO_ROOT or ".")
    local path = root .. "/include/constants/moves.h"
    local f = io.open(path, "r")
    if not f then
        _moveNameToId = t
        return t
    end
    for line in f:lines() do
        local name, num = line:match("^#define%s+(MOVE_[A-Z0-9_]+)%s+(%d+)")
        if name and num then
            t[name] = tonumber(num)
        end
    end
    f:close()
    _moveNameToId = t
    return t
end

-- M.readMailbox is provided by reserved_species_mailbox_bus.lua.
local encodeGen3Text = _init.encodeGen3Text
local pickRandomRsDexWithSprites = _init.pickRandomRsDexWithSprites
local nextPromptStoneReservedSlotIndex = _init.nextPromptStoneReservedSlotIndex
local reserveNextPromptStoneSpeciesId = _init.reserveNextPromptStoneSpeciesId
local nextReservedSpeciesIdAfter = _init.nextReservedSpeciesIdAfter
local jsonEscapeForBridge = _init.jsonEscapeForBridge
local pokegenHttpPostCurl = _init.pokegenHttpPostCurl

--- Must be declared before promptStoneApplySuccess (Lua local scoping).
local function promptStoneDisplayNameFromPrompt(promptAscii)
    if not promptAscii then
        return nil
    end
    local s = tostring(promptAscii):gsub("^%s+", ""):gsub("%s+$", "")
    if s == "" then
        return nil
    end
    return s:sub(1, M.POKEMON_NAME_LENGTH)
end

--- Clone/sprites/name/resultSpecies/DONE + logs (shared by auto-stub and pokegen HTTP).
local function promptStoneApplySuccess(emu, base, mb, infoAddr, row, targetSpecies, prev, promptText, rsSlotLog)
    if prev ~= 0 then
        M.copyPokemonSpeciesTablesFromSource(emu, base, targetSpecies, prev)
    end
    local rndDex, rndFront, rndBack = nil, nil, nil
    if M.PROMPT_STONE_AUTO_RANDOM_RS_SPRITES == true then
        local repoRoot = trimPath(M._REPO_ROOT or ".")
        rndDex, rndFront, rndBack = pickRandomRsDexWithSprites(repoRoot)
        if rndFront and rndBack then
            local ok, err = pcall(function()
                M.applyRuntimePngPair(emu, base, targetSpecies, rndFront, rndBack, repoRoot)
            end)
            if not ok then
                if console and console.log then
                    console:log(
                        "[ReservedSpeciesMailbox] Prompt Stone: random RS sprites failed (using cloned tables only): "
                            .. tostring(err)
                    )
                end
            end
        elseif console and console.log then
            console:log(
                "[ReservedSpeciesMailbox] Prompt Stone: no RS sprite PNG pair under ../sprites/... (stats clone only). tries="
                    .. tostring(M.PROMPT_STONE_RS_SPRITE_PICK_TRIES)
            )
        end
    end
    local disp = promptStoneDisplayNameFromPrompt(promptText)
    local pk = rsSlotLog
    if pk == nil then
        pk = targetSpecies % 1000
    end
    M.writeSpeciesNameById(emu, base, targetSpecies, disp or string.format("PKMN%d", pk))
    w16(emu, infoAddr + M.OFFSET_NPI_RESULT_SPECIES, targetSpecies)
    w8(emu, row + M.OFFSET_NPP_STATUS, M.NEW_POKEMON_REQ_DONE)
    if console and console.log then
        if rndDex then
            console:log(
                string.format(
                    "[ReservedSpeciesMailbox] Prompt Stone: reservedSlot=%s resultSpecies=%u prevSpecies=%u RS_dex=%u -> DONE",
                    tostring(rsSlotLog),
                    targetSpecies,
                    prev,
                    rndDex
                )
            )
        else
            console:log(
                string.format(
                    "[ReservedSpeciesMailbox] Prompt Stone: reservedSlot=%s resultSpecies=%u (cloned from species %u) -> DONE",
                    tostring(rsSlotLog),
                    targetSpecies,
                    prev
                )
            )
        end
    end
end

local function writeAsciiEosStringToRom(emu, addr, text, maxChars)
    local enc = encodeGen3Text(text or "", maxChars)
    for i = 0, maxChars do
        w8(emu, addr + i, 0xFF) -- EOS fill
    end
    for i = 1, #enc do
        w8(emu, addr + (i - 1), enc[i])
    end
end

function M.getReservedPokedexCategoryAddr(emu, base, slot)
    local mb = M.readMailbox(emu, base)
    if slot < 0 or slot >= mb.count then
        error(string.format("slot out of range: %d (count=%d)", slot, mb.count))
    end
    return mb.pokedexCategoryText + slot * mb.pokedexCategoryStride
end

function M.getReservedPokedexDescriptionAddr(emu, base, slot)
    local mb = M.readMailbox(emu, base)
    if slot < 0 or slot >= mb.count then
        error(string.format("slot out of range: %d (count=%d)", slot, mb.count))
    end
    return mb.pokedexDescriptionText + slot * mb.pokedexDescriptionStride
end

function M.writeReservedPokedexCategory(emu, base, slot, asciiText)
    local mb = M.readMailbox(emu, base)
    local addr = M.getReservedPokedexCategoryAddr(emu, base, slot)
    local maxChars = math.max(0, mb.pokedexCategoryStride - 1)
    writeAsciiEosStringToRom(emu, addr, asciiText, maxChars)
    return addr
end

function M.writeReservedPokedexDescription(emu, base, slot, asciiText)
    local mb = M.readMailbox(emu, base)
    local addr = M.getReservedPokedexDescriptionAddr(emu, base, slot)
    local maxChars = math.max(0, mb.pokedexDescriptionStride - 1)
    writeAsciiEosStringToRom(emu, addr, asciiText, maxChars)
    return addr
end

local function packLevelUpMove(level, moveId)
    if level < 0 or level > 127 then
        error("level out of range (0..127): " .. tostring(level))
    end
    if moveId < 0 or moveId > M.LEVEL_UP_MOVE_ID then
        error("move id out of range (0..511): " .. tostring(moveId))
    end
    return level * 512 + moveId
end

local function normalizeLevelUpEntry(entry)
    if type(entry) == "number" then
        if entry < 0 or entry > 0xFFFF then
            error("packed level-up entry out of range: " .. tostring(entry))
        end
        return entry
    end
    if type(entry) == "table" then
        if entry.level ~= nil and entry.move ~= nil then
            local mv = entry.move
            if type(mv) == "string" then
                mv = loadMoveNameTable()[mv]
            end
            return packLevelUpMove(tonumber(entry.level) or -1, tonumber(mv) or -1)
        end
        if #entry >= 2 then
            local mv = entry[2]
            if type(mv) == "string" then
                mv = loadMoveNameTable()[mv]
            end
            return packLevelUpMove(tonumber(entry[1]) or -1, tonumber(mv) or -1)
        end
    end
    if type(entry) == "string" then
        local moveId = loadMoveNameTable()[entry]
        if moveId then
            -- Default level 1 when only move name is provided.
            return packLevelUpMove(1, moveId)
        end
    end
    error("invalid learnset entry; use packed u16 or {level=..., move=...} or {level, move}")
end

function M.getReservedLearnsetAddr(emu, base, slot)
    local mb = M.readMailbox(emu, base)
    if slot < 0 or slot >= mb.count then
        error(string.format("slot out of range: %d (count=%d)", slot, mb.count))
    end
    return mb.reservedLearnsetData + slot * mb.reservedLearnsetStride
end

function M.patchReservedLearnsetPointerById(emu, base, speciesId, learnsetAddr)
    local mb = M.readMailbox(emu, base)
    local ptrAddr = mb.levelUpLearnsets + speciesId * 4
    w32(emu, ptrAddr, learnsetAddr)
    return ptrAddr
end

function M.writeReservedLevelUpMoveset(emu, base, slot, entries)
    local mb = M.readMailbox(emu, base)
    local speciesId = M.getReservedSpeciesIdForSlot(emu, base, slot)
    local rowAddr = M.getReservedLearnsetAddr(emu, base, slot)
    local maxEntries = mb.reservedLearnsetMaxEntries
    local maxMoves = math.max(0, maxEntries - 1)
    local moves = entries or {}

    if type(moves) ~= "table" then
        error("entries must be a table")
    end
    if #moves > maxMoves then
        error(string.format("too many level-up moves (%d > max %d)", #moves, maxMoves))
    end

    for i = 0, maxEntries - 1 do
        w16(emu, rowAddr + i * 2, M.LEVEL_UP_END)
    end
    for i = 1, #moves do
        local packed = normalizeLevelUpEntry(moves[i])
        w16(emu, rowAddr + (i - 1) * 2, packed)
    end

    local ptrAddr = M.patchReservedLearnsetPointerById(emu, base, speciesId, rowAddr)
    _dbg(
        string.format(
            "writeReservedLevelUpMoveset(slot=%d species=%d entries=%d row=0x%08X ptr=0x%08X)",
            slot,
            speciesId,
            #moves,
            rowAddr,
            ptrAddr
        )
    )
    return rowAddr, ptrAddr
end

-- Convenience helper: accepts {{level, "MOVE_NAME"}, ...} or {{level=..., move="MOVE_NAME"}, ...}
function M.writeReservedLevelUpMovesetByName(emu, base, slot, namedEntries)
    return M.writeReservedLevelUpMoveset(emu, base, slot, namedEntries)
end

function M.patchFrontPicEntry(emu, base, speciesId, picPtr, uncompSize, tag)
    _dbg(string.format("patchFrontPicEntry(base=0x%08X, speciesId=%d, picPtr=0x%08X, uncompSize=%u, tag=%d)", base, speciesId, picPtr, uncompSize, tag))
    local mb = M.readMailbox(emu, base)
    local a = mb.monFrontPicTable + speciesId * M.SPRITE_SHEET_ENTRY_SIZE
    w32(emu, a + 0, picPtr)
    w32(emu, a + 4, uncompSize + (tag * 65536))
    return a
end

function M.patchBackPicEntry(emu, base, speciesId, picPtr, uncompSize, tag)
    _dbg(string.format("patchBackPicEntry(base=0x%08X, speciesId=%d, picPtr=0x%08X, uncompSize=%u, tag=%d)", base, speciesId, picPtr, uncompSize, tag))
    local mb = M.readMailbox(emu, base)
    local a = mb.monBackPicTable + speciesId * M.SPRITE_SHEET_ENTRY_SIZE
    w32(emu, a + 0, picPtr)
    w32(emu, a + 4, uncompSize + (tag * 65536))
    return a
end

function M.patchPaletteEntry(emu, base, speciesId, palPtr, tag)
    _dbg(string.format("patchPaletteEntry(base=0x%08X, speciesId=%d, palPtr=0x%08X, tag=%d)", base, speciesId, palPtr, tag))
    local mb = M.readMailbox(emu, base)
    local a = mb.monPaletteTable + speciesId * M.PALETTE_ENTRY_SIZE
    w32(emu, a + 0, palPtr)
    w32(emu, a + 4, tag % 65536)
    return a
end

function M.patchShinyPaletteEntry(emu, base, speciesId, palPtr, tag)
    _dbg(string.format("patchShinyPaletteEntry(base=0x%08X, speciesId=%d, palPtr=0x%08X, tag=%d)", base, speciesId, palPtr, tag))
    local mb = M.readMailbox(emu, base)
    local a = mb.monShinyPaletteTable + speciesId * M.PALETTE_ENTRY_SIZE
    w32(emu, a + 0, palPtr)
    w32(emu, a + 4, tag % 65536)
    return a
end

-- Runtime PNG/LZ conversion and per-species scratch patching now live in
-- reserved_species_mailbox_runtime.lua.

function M.validateMailbox(emu, base)
    if r32(emu, base + M.OFFSET_MAGIC) ~= M.MAGIC then
        return false, "bad magic"
    end
    if r32(emu, base + M.OFFSET_TRAIL_MAGIC) ~= M.TRAIL then
        return false, "bad trail"
    end
    if r16(emu, base + M.OFFSET_VERSION) ~= M.VERSION then
        return false, "bad version"
    end
    return true
end

--- Scan [startAddr, endAddr) step 4. Two cheap reads per candidate (magic + trail).
function M.findMailbox(emu, startAddr, endAddr)
    startAddr = startAddr - (startAddr % 4)
    endAddr = endAddr - (endAddr % 4)
    for a = startAddr, endAddr - M.MAILBOX_SIZE, 4 do
        if r32(emu, a + M.OFFSET_MAGIC) == M.MAGIC and r32(emu, a + M.OFFSET_TRAIL_MAGIC) == M.TRAIL then
            local ok, err = M.validateMailbox(emu, a)
            if ok then
                return a
            end
        end
    end
    return nil
end

function M.speciesInfoRowPtrFromBase(speciesInfoBase, speciesId, sizeofSpeciesInfo)
    return speciesInfoBase + speciesId * sizeofSpeciesInfo
end

function M.rowPtrMatchesComputed(emu, base)
    local mb = M.readMailbox(emu, base)
    if mb.magic ~= M.MAGIC or mb.trailMagic ~= M.TRAIL then
        return false
    end
    local computed = M.speciesInfoRowPtrFromBase(mb.speciesInfo, mb.targetSpecies, mb.sizeofSpeciesInfo)
    return mb.speciesInfoRowPtr == computed
end

--- Poll gNewPokemonPending from EWRAM; log PENDING rows and optionally auto-complete (see M.PROMPT_STONE_AUTO_STUB).
function M.startPromptStonePendingPoll()
    if _promptStonePollId ~= nil then
        return
    end
    if not rawget(_G, "emu") or not rawget(_G, "callbacks") then
        return
    end
    local emu = rawget(_G, "emu")
    _promptStonePollId = callbacks:add("frame", function()
        local base = _attachState.base
        if not base then
            return
        end
        local mb = M.readMailbox(emu, base)
        local infoAddr = mb.newPokemonInfo
        local pendAddr = mb.newPokemonPendingSlots
        if infoAddr == 0 or pendAddr == 0 then
            return
        end
        for slot = 0, M.NEW_POKEMON_PENDING_MAX - 1 do
            local row = pendAddr + slot * M.NEW_POKEMON_PENDING_SLOT_SIZE
            local st = r8(emu, row + M.OFFSET_NPP_STATUS)
            if st == M.NEW_POKEMON_REQ_PENDING then
                local prevSt = _prevNppStatus[slot]
                if prevSt ~= M.NEW_POKEMON_REQ_PENDING then
                    local prefix = tostring(slot) .. ":"
                    for k in pairs(_bridgeReqSent) do
                        if type(k) == "string" and k:sub(1, #prefix) == prefix then
                            _bridgeReqSent[k] = nil
                        end
                    end
                    for k in pairs(_promptStoneLoggedReq) do
                        if type(k) == "string" and k:sub(1, #prefix) == prefix then
                            _promptStoneLoggedReq[k] = nil
                        end
                    end
                    for k in pairs(_promptStoneAssignedSpecies) do
                        if type(k) == "string" and k:sub(1, #prefix) == prefix then
                            _promptStoneAssignedSpecies[k] = nil
                        end
                    end
                end
                local prev = r16(emu, infoAddr + M.OFFSET_NPI_PREV_EVOLUTION_SPECIES)
                local promptText = M.readGen3StringFromEmu(emu, infoAddr + M.OFFSET_NPI_PROMPT_TEXT, M.NEW_POKEMON_PROMPT_TEXT_LEN)
                local reqId = r32(emu, row + M.OFFSET_NPP_REQUEST_ID)
                local logKey = slot .. ":" .. reqId
                if not _promptStoneLoggedReq[logKey] then
                    _promptStoneLoggedReq[logKey] = true
                    local spName = M.readSpeciesNameFromTable(emu, mb.speciesNames, prev)
                    local line = string.format(
                        "Prompt Stone: PENDING slot=%d requestId=%u speciesId=%u speciesName=%q prompt=%q",
                        slot,
                        reqId,
                        prev,
                        spName,
                        promptText
                    )
                    if console and console.log then
                        console:log("[ReservedSpeciesMailbox] " .. line)
                    else
                        _dbg(line)
                    end
                end
                if M.POKEGEN_BRIDGE_ENABLED == true then
                    if not _bridgeReqSent[logKey] then
                        local assignedSpecies = _promptStoneAssignedSpecies[logKey]
                        local assignedSlot = nil
                        if not assignedSpecies then
                            assignedSpecies, assignedSlot = reserveNextPromptStoneSpeciesId(mb, prev)
                            _promptStoneAssignedSpecies[logKey] = assignedSpecies
                        end
                        if not assignedSpecies or assignedSpecies == 0 then
                            w8(emu, row + M.OFFSET_NPP_STATUS, M.NEW_POKEMON_REQ_FAILED)
                            if console and console.log then
                                console:log(
                                    "[ReservedSpeciesMailbox] pokegen: no reserved species id available for this request (window exhausted?)"
                                )
                            end
                        end
                        if console and console.log and assignedSlot ~= nil then
                            console:log(
                                string.format(
                                    "[ReservedSpeciesMailbox] pokegen: reserved slot=%u speciesId=%u for requestId=%u",
                                    assignedSlot,
                                    assignedSpecies,
                                    reqId
                                )
                            )
                        end
                        _bridgeReqSent[logKey] = true
                        local rid = tostring(slot) .. "-" .. tostring(reqId)
                        local body = string.format(
                            '{"request_id":"%s","prev_evolution_species":%d,"prompt_text":"%s"}',
                            rid,
                            prev,
                            jsonEscapeForBridge(promptText)
                        )
                        local url = M.POKEGEN_HTTP_URL or "http://127.0.0.1:8765/v1/generate"
                        local pc, okHttp, st, species, httpErr = pcall(pokegenHttpPostCurl, url, body)
                        if not pc then
                            w8(emu, row + M.OFFSET_NPP_STATUS, M.NEW_POKEMON_REQ_FAILED)
                            if console and console.log then
                                console:log(
                                    "[ReservedSpeciesMailbox] pokegen: Lua error: " .. tostring(okHttp)
                                )
                            end
                        elseif not okHttp then
                            w8(emu, row + M.OFFSET_NPP_STATUS, M.NEW_POKEMON_REQ_FAILED)
                            if console and console.log then
                                console:log("[ReservedSpeciesMailbox] pokegen: " .. tostring(httpErr))
                            end
                        else
                            if console and console.log then
                                console:log(
                                    "[ReservedSpeciesMailbox] pokegen: status="
                                        .. tostring(st)
                                        .. " result_species="
                                        .. tostring(species)
                                )
                            end
                        end
                        if pc and okHttp and st == "done" and species ~= nil and species ~= 0 then
                            local targetSpecies = _promptStoneAssignedSpecies[logKey] or species
                            if targetSpecies ~= species and console and console.log then
                                console:log(
                                    string.format(
                                        "[ReservedSpeciesMailbox] pokegen: mapping server result_species=%u -> reserved targetSpecies=%u",
                                        species,
                                        targetSpecies
                                    )
                                )
                            end
                            if targetSpecies == prev then
                                local bumped = nextReservedSpeciesIdAfter(mb, prev)
                                if bumped and bumped ~= prev then
                                    targetSpecies = bumped
                                    if console and console.log then
                                        console:log(
                                            string.format(
                                                "[ReservedSpeciesMailbox] pokegen: result_species equals party species (%u); using next reserved species id %u",
                                                prev,
                                                targetSpecies
                                            )
                                        )
                                    end
                                else
                                    w8(emu, row + M.OFFSET_NPP_STATUS, M.NEW_POKEMON_REQ_FAILED)
                                    if console and console.log then
                                        console:log(
                                            "[ReservedSpeciesMailbox] pokegen: targetSpecies equals party species and no next id in reserved window"
                                        )
                                    end
                                end
                            end
                            if r8(emu, row + M.OFFSET_NPP_STATUS) == M.NEW_POKEMON_REQ_PENDING then
                                local rsLog = nil
                                if mb.targetSpecies and targetSpecies >= mb.targetSpecies then
                                    rsLog = targetSpecies - mb.targetSpecies
                                end
                                promptStoneApplySuccess(
                                    emu,
                                    base,
                                    mb,
                                    infoAddr,
                                    row,
                                    targetSpecies,
                                    prev,
                                    promptText,
                                    rsLog
                                )
                            end
                        elseif pc and okHttp then
                            w8(emu, row + M.OFFSET_NPP_STATUS, M.NEW_POKEMON_REQ_FAILED)
                            if console and console.log then
                                console:log(
                                    "[ReservedSpeciesMailbox] pokegen: FAILED status="
                                        .. tostring(st)
                                        .. " result_species="
                                        .. tostring(species)
                                )
                            end
                        end
                    end
                elseif M.PROMPT_STONE_AUTO_STUB == true then
                    local count = mb.count
                    if count and count > 0 then
                        local rsSlot = nextPromptStoneReservedSlotIndex(count)
                        local targetSpecies = M.getReservedSpeciesIdForSlot(emu, base, rsSlot)
                        promptStoneApplySuccess(emu, base, mb, infoAddr, row, targetSpecies, prev, promptText, rsSlot)
                    else
                        w8(emu, row + M.OFFSET_NPP_STATUS, M.NEW_POKEMON_REQ_FAILED)
                        if console and console.log then
                            console:log("[ReservedSpeciesMailbox] Prompt Stone auto: mailbox count=0 -> FAILED")
                        end
                    end
                end
            end
            _prevNppStatus[slot] = st
        end
    end)
end

--- Narrow scan first (upper EWRAM), then full EWRAM. Logs once and removes the frame callback.
function M.attach()
    _dbg("attach() called")
    if _attachState.base ~= nil then
        if console and console.log then
            console:log(string.format("[ReservedSpeciesMailbox] already found base=0x%08X", _attachState.base))
        end
        M.startPromptStonePendingPoll()
        return _attachState.base
    end
    if _attachState.cbid ~= nil then
        return nil
    end
    local function tryFind()
        local base = M.findMailbox(emu, 0x0203C000, 0x02040000)
        if not base then
            base = M.findMailbox(emu, 0x02000000, 0x02040000)
        end
        return base
    end
    local frames = 0
    _dbg("attach() registering frame callback")
    _attachState.cbid = callbacks:add("frame", function()
        frames = frames + 1
        local base = tryFind()
        if base then
            _attachState.base = base
            -- mGBA console may run in a different VM than this script; mirror for REPL users.
            rawset(_G, "ReservedSpeciesMailboxLastBase", base)
            callbacks:remove(_attachState.cbid)
            _attachState.cbid = nil
            local mb = M.readMailbox(emu, base)
            if console and console.log then
                console:log(string.format("[ReservedSpeciesMailbox] base=0x%08X", base))
                console:log(string.format("  speciesInfo=0x%08X sizeof=%u", mb.speciesInfo, mb.sizeofSpeciesInfo))
                console:log(string.format("  targetSpecies=%u rowPtr=0x%08X", mb.targetSpecies, mb.speciesInfoRowPtr))
                console:log(string.format("  learnsetEntryAddr=0x%08X", mb.levelUpLearnsetEntryAddr))
                console:log(string.format("  rowPtrMatchesComputed=%s", tostring(M.rowPtrMatchesComputed(emu, base))))
                local lz = M.getRuntimeLzScratchLayout(mb)
                if lz then
                    console:log(
                        string.format(
                            "  runtimeLz scratch=0x%08X..0x%08X maxLZ front=%u back=%u pal=%u shiny=%u",
                            lz.scratchBase,
                            lz.scratchEndExclusive,
                            lz.maxFrontLz,
                            lz.maxBackLz,
                            lz.maxPalLz,
                            lz.maxShinyPalLz
                        )
                    )
                end
            end
            M.startPromptStonePendingPoll()
        elseif frames > 720 then
            callbacks:remove(_attachState.cbid)
            _attachState.cbid = nil
            if console and console.warn then
                console:warn("[ReservedSpeciesMailbox] not found in EWRAM after ~12s")
            end
        end
    end)
    return nil
end

function M.getAttachedBase()
    return _attachState.base or rawget(_G, "ReservedSpeciesMailboxLastBase")
end

do
    local info = debug.getinfo(1, "S")
    if info and info.source and info.source:sub(1, 1) == "@" then
        local p = info.source:sub(2)
        local dir = (p:gsub("[/\\][^/\\]*$", ""))
        M._REPO_ROOT = dir .. "/.."
    end
end

ReservedSpeciesMailbox = M
if rawget(_G, "emu") and rawget(_G, "callbacks") and type(callbacks.add) == "function" then
    _dbg("auto-attach on load")
    M.attach()
else
    _dbg("auto-attach skipped (no emu/callbacks)")
end
return M
