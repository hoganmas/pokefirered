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

-- Shared attach / Prompt Stone state (must be declared before any local function that indexes _attachState).
local _attachState = { cbid = nil, base = nil, promptStoneSlotCursor = 0 }
local _promptStonePollId = nil
local _promptStoneLoggedReq = {}
local _bridgeReqSent = {}
--- Last seen status per pending slot (0..NEW_POKEMON_PENDING_MAX-1); used to reset Lua caches when a new PENDING is allocated.
local _prevNppStatus = {}
--- Per pending request key ("slot:reqId") -> reserved species id assigned for this request.
local _promptStoneAssignedSpecies = {}
--- Session set of reserved species ids already assigned (avoid reusing rows while window has free ids).
local _reservedSpeciesAllocated = {}

-- EWRAM bus range; memory.wram uses offsets from 0x02000000 (mGBA scripting docs).
local GBA_EWRAM_BASE = 0x02000000
local GBA_EWRAM_END = 0x03000000

local function tryEwramRead8(emu, addr)
    if addr < GBA_EWRAM_BASE or addr >= GBA_EWRAM_END then
        return nil
    end
    local w = emu.memory and emu.memory.wram
    if not w or type(w.read8) ~= "function" then
        return nil
    end
    local off = addr - GBA_EWRAM_BASE
    local sz = 0x40000
    if type(w.size) == "function" then
        sz = w:size()
    end
    if off < 0 or off >= sz then
        return nil
    end
    return w:read8(off)
end

local function r32(emu, addr)
    return emu:read32(addr)
end

local function r16(emu, addr)
    return emu:read16(addr)
end

local function r8(emu, addr)
    local ew = tryEwramRead8(emu, addr)
    if ew ~= nil then
        return ew
    end
    if emu.read8 then
        return emu:read8(addr)
    end
    return emu:read16(addr) % 256
end

-- Inverse of encodeGen3Text (rough ASCII view for console logs).
local function decodeGen3ByteToChar(b)
    if b == 0x00 then
        return " "
    end
    if b == 0xFF or b == 0xFE then
        return ""
    end
    if b >= 0xBB and b <= 0xD4 then
        return string.char(string.byte("A") + (b - 0xBB))
    end
    if b >= 0xD5 and b <= 0xEE then
        return string.char(string.byte("a") + (b - 0xD5))
    end
    if b >= 0xA1 and b <= 0xAA then
        return string.char(string.byte("0") + (b - 0xA1))
    end
    if b == 0xAE then
        return "-"
    end
    if b == 0xAD then
        return "."
    end
    if b == 0xAC then
        return "?"
    end
    return "?"
end

function M.readGen3StringFromEmu(emu, addr, maxChars)
    local parts = {}
    for i = 0, maxChars - 1 do
        local b = r8(emu, addr + i)
        if b == 0xFF or b == 0xFE then
            break
        end
        parts[#parts + 1] = decodeGen3ByteToChar(b)
    end
    return table.concat(parts)
end

function M.readSpeciesNameFromTable(emu, speciesNamesBase, speciesId)
    if speciesNamesBase == 0 then
        return ""
    end
    local addr = speciesNamesBase + speciesId * M.SPECIES_NAME_STRIDE
    return M.readGen3StringFromEmu(emu, addr, M.POKEMON_NAME_LENGTH)
end

-- GBA ROM is read-only on the CPU bus; mGBA logs "Unimplemented memory Store" for emu:write* to 0x08…
-- Use the cartridge MemoryDomain (cart0/cart1/cart2) so patches apply without spamming stdout.
-- See: mGBA scripting docs → Memory domains → cart0 (ROM @ 0x08000000).
local GBA_ROM_CART0_BASE = 0x08000000
local GBA_ROM_CART1_BASE = 0x0A000000
local GBA_ROM_CART2_BASE = 0x0C000000

local function romDomainAndOffset(addr)
    if addr >= GBA_ROM_CART0_BASE and addr < GBA_ROM_CART1_BASE then
        return "cart0", addr - GBA_ROM_CART0_BASE
    end
    if addr >= GBA_ROM_CART1_BASE and addr < GBA_ROM_CART2_BASE then
        return "cart1", addr - GBA_ROM_CART1_BASE
    end
    if addr >= GBA_ROM_CART2_BASE and addr < 0x0E000000 then
        return "cart2", addr - GBA_ROM_CART2_BASE
    end
    return nil
end

-- EWRAM writes: same as reads — use memory.wram so the CPU sees updates (see tryEwramRead8 above).
local function tryEwramWrite8(emu, addr, value)
    value = value % 256
    if addr < GBA_EWRAM_BASE or addr >= GBA_EWRAM_END then
        return false
    end
    local w = emu.memory and emu.memory.wram
    if not w or type(w.write8) ~= "function" then
        return false
    end
    local off = addr - GBA_EWRAM_BASE
    local sz = 0x40000
    if type(w.size) == "function" then
        sz = w:size()
    end
    if off < 0 or off >= sz then
        return false
    end
    w:write8(off, value)
    return true
end

local function tryEwramWrite16(emu, addr, value)
    value = value % 65536
    if addr < GBA_EWRAM_BASE or addr + 1 >= GBA_EWRAM_END then
        return false
    end
    local w = emu.memory and emu.memory.wram
    if not w then
        return false
    end
    local off = addr - GBA_EWRAM_BASE
    local sz = 0x40000
    if type(w.size) == "function" then
        sz = w:size()
    end
    if off < 0 or off + 1 >= sz then
        return false
    end
    if type(w.write16) == "function" then
        w:write16(off, value)
    else
        w:write8(off + 0, value % 256)
        w:write8(off + 1, math.floor(value / 256) % 256)
    end
    return true
end

local function w32(emu, addr, value)
    local domName, off = romDomainAndOffset(addr)
    if domName and emu.memory and emu.memory[domName] and type(emu.memory[domName].write32) == "function" then
        emu.memory[domName]:write32(off, value)
        return
    end
    if type(emu.write32) == "function" then
        emu:write32(addr, value)
        return
    end
    error("This mGBA Lua runtime does not expose emu:write32")
end

local function w8(emu, addr, value)
    if tryEwramWrite8(emu, addr, value) then
        return
    end
    local domName, off = romDomainAndOffset(addr)
    if domName and emu.memory and emu.memory[domName] and type(emu.memory[domName].write8) == "function" then
        emu.memory[domName]:write8(off, value)
        return
    end
    if type(emu.write8) == "function" then
        emu:write8(addr, value)
        return
    end
    error("This mGBA Lua runtime does not expose emu:write8")
end

local function w16(emu, addr, value)
    if tryEwramWrite16(emu, addr, value) then
        return
    end
    w8(emu, addr + 0, value % 256)
    w8(emu, addr + 1, math.floor(value / 256) % 256)
end

-- Lua 5.1: os.execute returns status number (0 = success).
-- Lua 5.2+: returns true on success, or nil/false, "exit", code on failure.
local function shellSucceeded(a, b, c)
    if a == true then
        return true
    end
    if type(a) == "number" then
        return a == 0
    end
    return false
end

local function readFileMaybe(path)
    local f = io.open(path, "r")
    if not f then
        return nil
    end
    local t = f:read("*a")
    f:close()
    return t
end

local function trimPath(s)
    if not s then
        return s
    end
    return (s:gsub("[/\\]+$", ""))
end

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

function M.readMailbox(emu, base)
    return {
        magic = r32(emu, base + M.OFFSET_MAGIC),
        version = r16(emu, base + M.OFFSET_VERSION),
        count = r16(emu, base + M.OFFSET_COUNT),
        speciesInfo = r32(emu, base + M.OFFSET_SPECIES_INFO),
        levelUpLearnsets = r32(emu, base + M.OFFSET_LEVEL_UP_LEARNSETS),
        monFrontPicTable = r32(emu, base + M.OFFSET_MON_FRONT_PIC),
        monBackPicTable = r32(emu, base + M.OFFSET_MON_BACK_PIC),
        monPaletteTable = r32(emu, base + M.OFFSET_MON_PALETTE),
        speciesNames = r32(emu, base + M.OFFSET_SPECIES_NAMES),
        sizeofSpeciesInfo = r32(emu, base + M.OFFSET_SIZEOF_SPECIES_INFO),
        targetSpecies = r16(emu, base + M.OFFSET_TARGET_SPECIES),
        speciesInfoRowPtr = r32(emu, base + M.OFFSET_SPECIES_INFO_ROW_PTR),
        levelUpLearnsetEntryAddr = r32(emu, base + M.OFFSET_LEVEL_UP_LEARNSET_ENTRY_ADDR),
        runtimeFrontLzAddr = r32(emu, base + M.OFFSET_RUNTIME_FRONT_LZ),
        runtimeBackLzAddr = r32(emu, base + M.OFFSET_RUNTIME_BACK_LZ),
        runtimePalLzAddr = r32(emu, base + M.OFFSET_RUNTIME_PAL_LZ),
        runtimeShinyPalLzAddr = r32(emu, base + M.OFFSET_RUNTIME_SHINY_PAL_LZ),
        monShinyPaletteTable = r32(emu, base + M.OFFSET_MON_SHINY_PALETTE),
        pokedexCategoryText = r32(emu, base + M.OFFSET_POKEDEX_CATEGORY_TEXT),
        pokedexDescriptionText = r32(emu, base + M.OFFSET_POKEDEX_DESCRIPTION_TEXT),
        pokedexCategoryStride = r16(emu, base + M.OFFSET_POKEDEX_CATEGORY_STRIDE),
        pokedexDescriptionStride = r16(emu, base + M.OFFSET_POKEDEX_DESCRIPTION_STRIDE),
        reservedLearnsetData = r32(emu, base + M.OFFSET_RESERVED_LEARNSET_DATA),
        reservedLearnsetStride = r16(emu, base + M.OFFSET_RESERVED_LEARNSET_STRIDE),
        reservedLearnsetMaxEntries = r16(emu, base + M.OFFSET_RESERVED_LEARNSET_MAX_ENTRIES),
        runtimeRomScratchEndExclusive = r32(emu, base + M.OFFSET_RUNTIME_SCRATCH_END),
        newPokemonInfo = r32(emu, base + M.OFFSET_NEW_POKEMON_INFO),
        newPokemonPendingSlots = r32(emu, base + M.OFFSET_NEW_POKEMON_PENDING),
        trailMagic = r32(emu, base + M.OFFSET_TRAIL_MAGIC),
    }
end

--- Derive per-slot max LZ sizes from C-filled pointers (no hardcoded ROM addresses or caps in Lua).
-- @param mb table from readMailbox
-- @return layout table, or nil, err
function M.getRuntimeLzScratchLayout(mb)
    if not mb then
        return nil, "nil mailbox"
    end
    local a = mb.runtimeFrontLzAddr
    local b = mb.runtimeBackLzAddr
    local c = mb.runtimePalLzAddr
    local d = mb.runtimeShinyPalLzAddr
    local e = mb.runtimeRomScratchEndExclusive
    if a == 0 or b == 0 or c == 0 or d == 0 then
        return nil, "mailbox missing runtime LZ slot addresses (rebuild ROM / ReservedSpecies_InitScriptMailbox)"
    end
    if e == 0 then
        return nil, "mailbox missing runtimeRomScratchEndExclusive (need mailbox version >= 3)"
    end
    if not (a < b and b < c and c < d and d < e) then
        return nil, "runtime LZ addresses must be strictly ascending (front < back < pal < shiny < end)"
    end
    local perSpeciesStride = (b - a) + (c - b) + (d - c) + (d - c)
    local total = e - a
    local speciesSlots = 1
    if perSpeciesStride > 0 and total >= perSpeciesStride then
        speciesSlots = math.floor(total / perSpeciesStride)
        if speciesSlots < 1 then
            speciesSlots = 1
        end
    end
    return {
        scratchBase = a,
        scratchEndExclusive = e,
        frontAddr = a,
        backAddr = b,
        palAddr = c,
        shinyPalAddr = d,
        maxFrontLz = b - a,
        maxBackLz = c - b,
        maxPalLz = d - c,
        maxShinyPalLz = e - d,
        perSpeciesStride = perSpeciesStride,
        speciesSlots = speciesSlots,
    }
end

local function runtimeLzAddressesForSpecies(mb, speciesId)
    local layout, err = M.getRuntimeLzScratchLayout(mb)
    if not layout then
        return nil, err
    end
    local slot = speciesId - mb.targetSpecies
    if slot < 0 or slot >= mb.count then
        return nil, string.format("speciesId %u not in reserved window [%u..%u]", speciesId, mb.targetSpecies, mb.targetSpecies + mb.count - 1)
    end
    if slot >= layout.speciesSlots then
        return nil, string.format("runtime scratch has %u per-species slots, but species slot=%u requested", layout.speciesSlots, slot)
    end
    local base = mb.runtimeFrontLzAddr + slot * layout.perSpeciesStride
    local front = base
    local back = base + layout.maxFrontLz
    local pal = back + layout.maxBackLz
    local shiny = pal + layout.maxPalLz
    return {
        front = front,
        back = back,
        pal = pal,
        shiny = shiny,
        maxFrontLz = layout.maxFrontLz,
        maxBackLz = layout.maxBackLz,
        maxPalLz = layout.maxPalLz,
        maxShinyPalLz = layout.maxPalLz,
    }, nil
end

local function encodeGen3TextByte(ch)
    local b = string.byte(ch)
    if b >= string.byte("A") and b <= string.byte("Z") then
        return 0xBB + (b - string.byte("A"))
    elseif b >= string.byte("a") and b <= string.byte("z") then
        return 0xD5 + (b - string.byte("a"))
    elseif b >= string.byte("0") and b <= string.byte("9") then
        return 0xA1 + (b - string.byte("0"))
    elseif ch == " " then
        return 0x00
    elseif ch == "-" then
        return 0xAE
    elseif ch == "." then
        return 0xAD
    elseif ch == "?" then
        return 0xAC
    end
    return 0xAC -- '?'
end

local function encodeGen3Text(name, maxChars)
    local out = {}
    local n = math.min(#name, maxChars)
    for i = 1, n do
        out[#out + 1] = encodeGen3TextByte(name:sub(i, i))
    end
    return out
end

function M.getReservedSpeciesIdForSlot(emu, base, slot)
    _dbg(string.format("getReservedSpeciesIdForSlot(base=0x%08X, slot=%d)", base, slot))
    local mb = M.readMailbox(emu, base)
    if slot < 0 or slot >= mb.count then
        error(string.format("slot out of range: %d (count=%d)", slot, mb.count))
    end
    return mb.targetSpecies + slot
end

function M.getSpeciesNameAddr(emu, base, speciesId)
    _dbg(string.format("getSpeciesNameAddr(base=0x%08X, speciesId=%d)", base, speciesId))
    local mb = M.readMailbox(emu, base)
    return mb.speciesNames + speciesId * M.SPECIES_NAME_STRIDE
end

function M.writeSpeciesNameById(emu, base, speciesId, asciiName)
    _dbg(string.format("writeSpeciesNameById(base=0x%08X, speciesId=%d, name=%s)", base, speciesId, tostring(asciiName)))
    local addr = M.getSpeciesNameAddr(emu, base, speciesId)
    local enc = encodeGen3Text(asciiName or "", M.POKEMON_NAME_LENGTH)
    for i = 0, M.POKEMON_NAME_LENGTH do
        w8(emu, addr + i, 0xFF) -- EOS fill
    end
    for i = 1, #enc do
        w8(emu, addr + (i - 1), enc[i])
    end
    return addr
end

function M.writeReservedSpeciesName(emu, base, slot, asciiName)
    _dbg(string.format("writeReservedSpeciesName(base=0x%08X, slot=%d, name=%s)", base, slot, tostring(asciiName)))
    local speciesId = M.getReservedSpeciesIdForSlot(emu, base, slot)
    local addr = M.writeSpeciesNameById(emu, base, speciesId, asciiName)
    if console and console.log then
        console:log(string.format("[ReservedSpeciesMailbox] wrote name slot=%d species=%d addr=0x%08X", slot, speciesId, addr))
    end
    return addr
end

local function copyBusBytes(emu, dstAddr, srcAddr, len)
    if dstAddr == srcAddr then
        return
    end
    for i = 0, len - 1 do
        w8(emu, dstAddr + i, r8(emu, srcAddr + i))
    end
end

--- Clone Gen III ROM species definition from srcSpeciesId onto dstSpeciesId using mailbox pointers (stats, learnset ptr, battle gfx).
-- Does not patch icon/cry tables (not exposed in the mailbox); cry for reserved IDs comes from the ROM table emitted at build time.
function M.copyPokemonSpeciesTablesFromSource(emu, base, dstSpeciesId, srcSpeciesId)
    if not srcSpeciesId or srcSpeciesId == 0 then
        return false
    end
    if not dstSpeciesId or dstSpeciesId == 0 then
        return false
    end
    local mb = M.readMailbox(emu, base)
    local si = mb.sizeofSpeciesInfo
    if not si or si == 0 or si > 512 then
        return false
    end
    local sRow = mb.speciesInfo + srcSpeciesId * si
    local dRow = mb.speciesInfo + dstSpeciesId * si
    copyBusBytes(emu, dRow, sRow, si)

    local lsrc = mb.levelUpLearnsets + srcSpeciesId * 4
    local ldst = mb.levelUpLearnsets + dstSpeciesId * 4
    w32(emu, ldst, r32(emu, lsrc))

    copyBusBytes(
        emu,
        mb.monFrontPicTable + dstSpeciesId * M.SPRITE_SHEET_ENTRY_SIZE,
        mb.monFrontPicTable + srcSpeciesId * M.SPRITE_SHEET_ENTRY_SIZE,
        M.SPRITE_SHEET_ENTRY_SIZE
    )
    copyBusBytes(
        emu,
        mb.monBackPicTable + dstSpeciesId * M.SPRITE_SHEET_ENTRY_SIZE,
        mb.monBackPicTable + srcSpeciesId * M.SPRITE_SHEET_ENTRY_SIZE,
        M.SPRITE_SHEET_ENTRY_SIZE
    )
    copyBusBytes(
        emu,
        mb.monPaletteTable + dstSpeciesId * M.PALETTE_ENTRY_SIZE,
        mb.monPaletteTable + srcSpeciesId * M.PALETTE_ENTRY_SIZE,
        M.PALETTE_ENTRY_SIZE
    )
    copyBusBytes(
        emu,
        mb.monShinyPaletteTable + dstSpeciesId * M.PALETTE_ENTRY_SIZE,
        mb.monShinyPaletteTable + srcSpeciesId * M.PALETTE_ENTRY_SIZE,
        M.PALETTE_ENTRY_SIZE
    )
    return true
end

local function hostFileExists(path)
    local f = io.open(path, "rb")
    if f then
        f:close()
        return true
    end
    return false
end

--- Paths to PokeAPI-style Gen III Ruby/Sapphire sprites (relative to pokefirered root: ../sprites/...).
function M.getGen3RsSpritePngPaths(repoRoot, dexNum)
    local r = trimPath(repoRoot or M._REPO_ROOT or ".")
    local baseDir = r .. "/../sprites/sprites/pokemon/versions/generation-iii/ruby-sapphire"
    local candidates = {
        { baseDir .. "/" .. dexNum .. ".png", baseDir .. "/back/" .. dexNum .. ".png" },
        {
            baseDir .. "/" .. string.format("%03d", dexNum) .. ".png",
            baseDir .. "/back/" .. string.format("%03d", dexNum) .. ".png",
        },
    }
    for i = 1, #candidates do
        local pair = candidates[i]
        if hostFileExists(pair[1]) and hostFileExists(pair[2]) then
            return pair[1], pair[2]
        end
    end
    return nil, nil
end

local _promptStoneRngSeeded = false
local function ensurePromptStoneRandomSeed()
    if _promptStoneRngSeeded then
        return
    end
    _promptStoneRngSeeded = true
    local t = os.time() or 0
    local c = 0
    if os.clock then
        c = math.floor(os.clock() * 1000000) % 100000
    end
    math.randomseed(t + c)
end

local function pickRandomRsDexWithSprites(repoRoot)
    ensurePromptStoneRandomSeed()
    local lo = M.PROMPT_STONE_RS_SPRITE_DEX_MIN or 1
    local hi = M.PROMPT_STONE_RS_SPRITE_DEX_MAX or 386
    local tries = M.PROMPT_STONE_RS_SPRITE_PICK_TRIES or 48
    if hi < lo then
        lo, hi = hi, lo
    end
    for _ = 1, tries do
        local dex = math.random(lo, hi)
        local a, b = M.getGen3RsSpritePngPaths(repoRoot, dex)
        if a and b then
            return dex, a, b
        end
    end
    return nil, nil, nil
end

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

--- Reserve a target reserved species id for this request.
--- Prefer rows not yet assigned this session, and avoid selecting prevSpecies when possible.
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

--- When pokegen returns result_species == party species, the evolution scene will not run and ROM patches
--- would stomp the same `gSpeciesInfo` row. Return the next species id inside the reserved mailbox window
--- [targetSpecies, targetSpecies+count-1], wrapping to targetSpecies+skip when at the end (matches stub chaining).
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

local function jsonEscapeForBridge(s)
    s = tostring(s or "")
    s = s:gsub("\\", "\\\\")
    s = s:gsub('"', '\\"')
    s = s:gsub("\n", "\\n")
    s = s:gsub("\r", "\\r")
    return s
end

local function parsePokegenJsonResponse(s)
    if not s or s == "" then
        return nil, 0
    end
    local st = s:match('"status"%s*:%s*"(%a+)"')
    local rs = s:match('"result_species"%s*:%s*(%d+)')
    return st, tonumber(rs or 0)
end

local function shellSingleQuote(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

--- POST JSON to pokegen-server via host `curl` (blocking). Requires curl on PATH.
--- mGBA may define io.popen but throw "'popen' not supported" — use pcall and fall back to os.execute.
local function pokegenHttpPostCurl(url, jsonBody)
    local maxSec = M.POKEGEN_HTTP_MAX_TIME_SEC or 30
    local tmp = os.tmpname()
    if not tmp then
        tmp = "build/pokegen_http_body.json"
    end
    local wf = io.open(tmp, "w")
    if not wf then
        return false, nil, nil, "cannot write temp JSON body"
    end
    wf:write(jsonBody)
    wf:close()
    -- -d @file avoids shell-escaping the JSON body; quote URL and path for sh.
    local qtmp = shellSingleQuote(tmp)
    local qurl = shellSingleQuote(url)
    local cmd = string.format(
        "curl -sS --max-time %d -X POST -H %s -d @%s %s",
        maxSec,
        shellSingleQuote("Content-Type: application/json"),
        qtmp,
        qurl
    )
    local resp = nil
    local err = nil
    local gotViaPopen = false
    if io and io.popen then
        local okPopen, hOrErr = pcall(io.popen, cmd)
        if okPopen and hOrErr then
            gotViaPopen = true
            local okRead, dataOrErr = pcall(function()
                local s = hOrErr:read("*a")
                hOrErr:close()
                return s
            end)
            if okRead then
                resp = dataOrErr
            else
                err = tostring(dataOrErr)
                gotViaPopen = false
            end
        elseif not okPopen then
            err = tostring(hOrErr)
        end
    end
    if not gotViaPopen and os and os.execute then
        local outPath = tmp .. ".out"
        local redir = cmd .. " > " .. shellSingleQuote(outPath) .. " 2>&1"
        local okEx, codeOrErr = pcall(os.execute, redir)
        if not okEx then
            err = err or tostring(codeOrErr)
        end
        local rf = io.open(outPath, "r")
        if rf then
            resp = rf:read("*a")
            rf:close()
        end
        pcall(os.remove, outPath)
    end
    pcall(os.remove, tmp)
    if not resp or resp == "" then
        return false,
            nil,
            nil,
            err
                or "empty response (install curl; check POKEGEN_HTTP_URL). If mGBA blocks subprocesses, use a build that allows os.execute."
    end
    local st, rs = parsePokegenJsonResponse(resp)
    return true, st, rs, nil
end

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

local function parseManifestText(txt)
    local out = {}
    for line in string.gmatch(txt, "[^\r\n]+") do
        local k, v = line:match("^([A-Z_]+)=(%d+)$")
        if k and v then
            out[k] = tonumber(v)
        end
    end
    return out
end

local function writeFileBytesToEmu(emu, addr, path)
    local f = assert(io.open(path, "rb"))
    local data = f:read("*a")
    f:close()
    for i = 1, #data do
        w8(emu, addr + i - 1, string.byte(data, i))
    end
    return #data
end

local function hostCopyBinary(src, dst)
    local inf = assert(io.open(src, "rb"))
    local data = inf:read("*a")
    inf:close()
    local outf = assert(io.open(dst, "wb"))
    outf:write(data)
    outf:close()
end

local function hostLzUncompressedSize(path)
    local f = assert(io.open(path, "rb"))
    local b0 = f:read(1)
    local b1 = f:read(1)
    local b2 = f:read(1)
    local b3 = f:read(1)
    f:close()
    if not b0 or string.byte(b0) ~= 0x10 then
        error("bad LZ header in " .. path)
    end
    return string.byte(b1) + string.byte(b2) * 256 + string.byte(b3) * 65536
end

local function hostFileSize(path)
    local f = assert(io.open(path, "rb"))
    local n = #f:read("*a")
    f:close()
    return n
end

--- Host: PNG → 4bpp.lz / palette.lz via tools/gbagfx only (no Python). Writes manifest.txt in workdir.
local function hostPngPairToLzWorkdir(repoRoot, frontPng, backPng, workdir, errLog)
    local gfx = repoRoot .. "/tools/gbagfx/gbagfx"
    if package.config:sub(1, 1) == "\\" then
        gfx = gfx .. ".exe"
    end
    local gf = io.open(gfx, "r")
    if not gf then
        error("missing gbagfx (run `make` in pokefirered): " .. gfx)
    end
    gf:close()

    local function run(fmt, ...)
        local cmd = string.format(fmt, ...) .. " 2>>" .. string.format("%q", errLog)
        local a, b, c = os.execute(cmd)
        if not shellSucceeded(a, b, c) then
            local err = readFileMaybe(errLog)
            error(
                string.format(
                    "gbagfx step failed. cmd=%s err=%s",
                    string.format(fmt, ...),
                    err or "(see " .. errLog .. ")"
                )
            )
        end
    end

    local a0, b0, c0 = os.execute(string.format("mkdir -p %q", workdir))
    if not shellSucceeded(a0, b0, c0) then
        error("mkdir failed: " .. workdir)
    end
    hostCopyBinary(frontPng, workdir .. "/front.png")
    hostCopyBinary(backPng, workdir .. "/back.png")

    local wf, wb = workdir .. "/front.png", workdir .. "/back.png"
    local f4, b4 = workdir .. "/front.4bpp", workdir .. "/back.4bpp"
    local flz, blz = workdir .. "/front.4bpp.lz", workdir .. "/back.4bpp.lz"
    local ngb = workdir .. "/normal.gbapal"
    local nlz, slz = workdir .. "/normal.gbapal.lz", workdir .. "/shiny.gbapal.lz"

    run("%q %q %q %s", gfx, wf, f4, "-num_tiles 64")
    run("%q %q %q", gfx, f4, flz)
    run("%q %q %q %s", gfx, wb, b4, "-num_tiles 64")
    run("%q %q %q", gfx, b4, blz)
    run("%q %q %q", gfx, wf, ngb)
    run("%q %q %q", gfx, ngb, nlz)
    hostCopyBinary(nlz, slz)

    local fu = hostLzUncompressedSize(flz)
    local bu = hostLzUncompressedSize(blz)
    local plz = hostFileSize(nlz)
    local slzsz = hostFileSize(slz)
    local flen = hostFileSize(flz)
    local blen = hostFileSize(blz)

    local mf = assert(io.open(workdir .. "/manifest.txt", "w"))
    mf:write(
        string.format(
            "FRONT_UNCOMP=%d\nBACK_UNCOMP=%d\nFRONT_LZ=%d\nBACK_LZ=%d\nPAL_LZ=%d\nSHINY_LZ=%d\n",
            fu,
            bu,
            flen,
            blen,
            plz,
            slzsz
        )
    )
    mf:close()
end

--- Host-side PNG→LZ77 (tools/gbagfx only), then patch ROM table rows to use ROM scratch LZ blobs (mailbox addresses).
-- frontPng/backPng: host paths that mGBA can open (absolute paths are safest for the mGBA console).
-- repoRoot: pokefirered root (must contain tools/gbagfx/gbagfx). Default: inferred from script path.
function M.applyRuntimePngPair(emu, base, speciesId, frontPng, backPng, repoRoot)
    local mb = M.readMailbox(emu, base)
    if mb.version ~= M.VERSION then
        error(string.format("mailbox version mismatch: got %d need %d", mb.version, M.VERSION))
    end
    local addrs, lerr = runtimeLzAddressesForSpecies(mb, speciesId)
    if not addrs then
        error(lerr or "bad runtime LZ layout")
    end
    repoRoot = trimPath(repoRoot or M._REPO_ROOT)
    if not repoRoot or #repoRoot == 0 then
        error("repoRoot unset: pass applyRuntimePngPair(..., lastArg=repoRoot as absolute path to pokefirered)")
    end
    local testGfx = repoRoot .. "/tools/gbagfx/gbagfx"
    if package.config:sub(1, 1) == "\\" then
        testGfx = testGfx .. ".exe"
    end
    if not io.open(testGfx, "r") then
        error(
            "repoRoot is wrong (missing "
                .. testGfx
                .. "). Pass the absolute path to the pokefirered project root."
        )
    end
    for label, p in pairs({ front = frontPng, back = backPng }) do
        local pfd = io.open(p, "r")
        if not pfd then
            error("cannot read " .. label .. " PNG (open as host file failed): " .. tostring(p))
        end
        pfd:close()
    end

    local workdir = repoRoot .. "/build/mgba_runtime_rsv_" .. tostring(os.time())
    local errLog = workdir .. "/convert_stderr.txt"
    _dbg(
        string.format(
            "applyRuntimePngPair: hostPngPairToLzWorkdir repo=%s work=%s",
            repoRoot,
            workdir
        )
    )
    hostPngPairToLzWorkdir(repoRoot, frontPng, backPng, workdir, errLog)
    local manPath = workdir .. "/manifest.txt"
    local mf = io.open(manPath, "r")
    if not mf then
        error("no manifest at " .. manPath)
    end
    local man = parseManifestText(mf:read("*a") or "")
    mf:close()
    local flz = man.FRONT_LZ
    local blz = man.BACK_LZ
    local plz = man.PAL_LZ
    local slz = man.SHINY_LZ
    if not flz or not blz or not plz or not slz then
        error("bad manifest.txt after host PNG conversion")
    end
    if flz > addrs.maxFrontLz or blz > addrs.maxBackLz or plz > addrs.maxPalLz or slz > addrs.maxShinyPalLz then
        error(
            string.format(
                "converted LZ larger than ROM scratch (max front=%u back=%u pal=%u shiny=%u); raise RESERVED_RUNTIME_*_CAP in reserved_species.h and rebuild",
                addrs.maxFrontLz,
                addrs.maxBackLz,
                addrs.maxPalLz,
                addrs.maxShinyPalLz
            )
        )
    end
    assert(writeFileBytesToEmu(emu, addrs.front, workdir .. "/front.4bpp.lz") == flz)
    assert(writeFileBytesToEmu(emu, addrs.back, workdir .. "/back.4bpp.lz") == blz)
    assert(writeFileBytesToEmu(emu, addrs.pal, workdir .. "/normal.gbapal.lz") == plz)
    assert(writeFileBytesToEmu(emu, addrs.shiny, workdir .. "/shiny.gbapal.lz") == slz)

    M.patchFrontPicEntry(emu, base, speciesId, addrs.front, man.FRONT_UNCOMP, speciesId)
    M.patchBackPicEntry(emu, base, speciesId, addrs.back, man.BACK_UNCOMP, speciesId)
    M.patchPaletteEntry(emu, base, speciesId, addrs.pal, speciesId)
    M.patchShinyPaletteEntry(emu, base, speciesId, addrs.shiny, speciesId + M.SPECIES_SHINY_TAG)
    _dbg(string.format("applyRuntimePngPair done species=%u front@0x%08X back@0x%08X", speciesId, addrs.front, addrs.back))
end

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
