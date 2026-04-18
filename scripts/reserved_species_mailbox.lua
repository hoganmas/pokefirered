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
M.OFFSET_NPP_STATUS = 0
M.OFFSET_NPP_REQUEST_ID = 4
M.POKEMON_NAME_LENGTH = 10
M.SPECIES_NAME_STRIDE = M.POKEMON_NAME_LENGTH + 1
M.SPRITE_SHEET_ENTRY_SIZE = 8 -- sizeof(struct CompressedSpriteSheet)
M.PALETTE_ENTRY_SIZE = 8

local function r32(emu, addr)
    return emu:read32(addr)
end

local function r16(emu, addr)
    return emu:read16(addr)
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
    }
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

function M.getFirstReservedSpeciesId(emu, base)
    -- targetSpecies is currently initialized to SPECIES_CHIMECHO + 1.
    _dbg(string.format("getFirstReservedSpeciesId(base=0x%08X)", base))
    return M.readMailbox(emu, base).targetSpecies
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
    local layout, lerr = M.getRuntimeLzScratchLayout(mb)
    if not layout then
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
    if flz > layout.maxFrontLz or blz > layout.maxBackLz or plz > layout.maxPalLz or slz > layout.maxShinyPalLz then
        error(
            string.format(
                "converted LZ larger than ROM scratch (max front=%u back=%u pal=%u shiny=%u); raise RESERVED_RUNTIME_*_CAP in reserved_species.h and rebuild",
                layout.maxFrontLz,
                layout.maxBackLz,
                layout.maxPalLz,
                layout.maxShinyPalLz
            )
        )
    end
    assert(writeFileBytesToEmu(emu, mb.runtimeFrontLzAddr, workdir .. "/front.4bpp.lz") == flz)
    assert(writeFileBytesToEmu(emu, mb.runtimeBackLzAddr, workdir .. "/back.4bpp.lz") == blz)
    assert(writeFileBytesToEmu(emu, mb.runtimePalLzAddr, workdir .. "/normal.gbapal.lz") == plz)
    assert(writeFileBytesToEmu(emu, mb.runtimeShinyPalLzAddr, workdir .. "/shiny.gbapal.lz") == slz)

    M.patchFrontPicEntry(emu, base, speciesId, mb.runtimeFrontLzAddr, man.FRONT_UNCOMP, speciesId)
    M.patchBackPicEntry(emu, base, speciesId, mb.runtimeBackLzAddr, man.BACK_UNCOMP, speciesId)
    M.patchPaletteEntry(emu, base, speciesId, mb.runtimePalLzAddr, speciesId)
    M.patchShinyPaletteEntry(emu, base, speciesId, mb.runtimeShinyPalLzAddr, speciesId + M.SPECIES_SHINY_TAG)
    _dbg(string.format("applyRuntimePngPair done species=%u front@0x%08X back@0x%08X", speciesId, mb.runtimeFrontLzAddr, mb.runtimeBackLzAddr))
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

local _attachState = { cbid = nil, base = nil }

--- Narrow scan first (upper EWRAM), then full EWRAM. Logs once and removes the frame callback.
function M.attach()
    _dbg("attach() called")
    if _attachState.base ~= nil then
        if console and console.log then
            console:log(string.format("[ReservedSpeciesMailbox] already found base=0x%08X", _attachState.base))
        end
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
