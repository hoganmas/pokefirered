-- Reserved species / scripting mailbox helpers for mGBA Lua.
-- Byte layout must match struct ReservedSpeciesScriptMailbox (include/reserved_species.h), 52 bytes.
--
-- mGBA: Tools → Scripting → Load this file, then: ReservedSpeciesMailbox.attach()
-- Tests: make test-mailbox-lua

local M = {}

M.MAGIC = 0x31505352
M.TRAIL = 0x544C4252
M.VERSION = 1

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
M.OFFSET_TRAIL_MAGIC = 48

M.MAILBOX_SIZE = 52

local function r32(emu, addr)
    return emu:read32(addr)
end

local function r16(emu, addr)
    return emu:read16(addr)
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
        trailMagic = r32(emu, base + M.OFFSET_TRAIL_MAGIC),
    }
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
    _attachState.cbid = callbacks:add("frame", function()
        frames = frames + 1
        local base = tryFind()
        if base then
            _attachState.base = base
            callbacks:remove(_attachState.cbid)
            _attachState.cbid = nil
            local mb = M.readMailbox(emu, base)
            if console and console.log then
                console:log(string.format("[ReservedSpeciesMailbox] base=0x%08X", base))
                console:log(string.format("  speciesInfo=0x%08X sizeof=%u", mb.speciesInfo, mb.sizeofSpeciesInfo))
                console:log(string.format("  targetSpecies=%u rowPtr=0x%08X", mb.targetSpecies, mb.speciesInfoRowPtr))
                console:log(string.format("  learnsetEntryAddr=0x%08X", mb.levelUpLearnsetEntryAddr))
                console:log(string.format("  rowPtrMatchesComputed=%s", tostring(M.rowPtrMatchesComputed(emu, base))))
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
    return _attachState.base
end

ReservedSpeciesMailbox = M
return M
