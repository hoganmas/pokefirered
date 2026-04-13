-- Reserved species / scripting mailbox helpers for mGBA Lua.
-- Byte layout must match struct ReservedSpeciesScriptMailbox (include/reserved_species.h), 72 bytes.
--
-- mGBA: Tools → Scripting → Load this file, then: ReservedSpeciesMailbox.attach()
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
M.VERSION = 2
M.SPECIES_SHINY_TAG = 500
M.RUNTIME_FRONT_LZ_CAP = 0x3000
M.RUNTIME_BACK_LZ_CAP = 0x3000
M.RUNTIME_PAL_LZ_CAP = 0x200

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
M.OFFSET_TRAIL_MAGIC = 68

M.MAILBOX_SIZE = 72
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

local function w32(emu, addr, value)
    if type(emu.write32) == "function" then
        emu:write32(addr, value)
        return
    end
    error("This mGBA Lua runtime does not expose emu:write32")
end

local function w8(emu, addr, value)
    if type(emu.write8) == "function" then
        emu:write8(addr, value)
        return
    end
    error("This mGBA Lua runtime does not expose emu:write8")
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
        trailMagic = r32(emu, base + M.OFFSET_TRAIL_MAGIC),
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

--- Host-side PNG→LZ77 (python3 + tools/gbagfx), then patch ROM table rows to use ROM scratch LZ blobs (mailbox addresses).
-- frontPng/backPng: absolute or cwd-relative paths readable by python.
-- repoRoot: pokefirered root (contains tools/). Default: inferred from this script location.
function M.applyRuntimePngPair(emu, base, speciesId, frontPng, backPng, repoRoot)
    local mb = M.readMailbox(emu, base)
    if mb.version ~= M.VERSION then
        error(string.format("mailbox version mismatch: got %d need %d", mb.version, M.VERSION))
    end
    if mb.runtimeFrontLzAddr == 0 or mb.runtimeBackLzAddr == 0 then
        error("mailbox missing runtime LZ staging addresses (rebuild ROM)")
    end
    repoRoot = repoRoot or M._REPO_ROOT
    if not repoRoot or #repoRoot == 0 then
        error("repoRoot unset: pass applyRuntimePngPair(..., repoRoot) or ensure mailbox script path is known")
    end
    local workdir = repoRoot .. "/build/mgba_runtime_rsv_" .. tostring(os.time())
    local py = repoRoot .. "/tools/runtime_reserved_png_to_lz.py"
    local cmd = string.format(
        "mkdir -p %q && cd %q && python3 %q --front %q --back %q --workdir %q",
        workdir,
        repoRoot,
        py,
        frontPng,
        backPng,
        workdir
    )
    _dbg("applyRuntimePngPair: " .. cmd)
    local st = os.execute(cmd)
    if st == false or (type(st) == "number" and st ~= 0) then
        error("runtime PNG conversion failed (python3 / gbagfx). status=" .. tostring(st))
    end
    local mf = assert(io.open(workdir .. "/manifest.txt", "r"))
    local man = parseManifestText(mf:read("*a"))
    mf:close()
    local flz = man.FRONT_LZ
    local blz = man.BACK_LZ
    local plz = man.PAL_LZ
    local slz = man.SHINY_LZ
    if not flz or not blz or not plz or not slz then
        error("bad manifest.txt from runtime_reserved_png_to_lz.py")
    end
    if flz > M.RUNTIME_FRONT_LZ_CAP or blz > M.RUNTIME_BACK_LZ_CAP or plz > M.RUNTIME_PAL_LZ_CAP or slz > M.RUNTIME_PAL_LZ_CAP then
        error("converted LZ larger than ROM scratch caps; raise RESERVED_RUNTIME_*_CAP in reserved_species.h and rebuild")
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

do
    local info = debug.getinfo(1, "S")
    if info and info.source and info.source:sub(1, 1) == "@" then
        local p = info.source:sub(2)
        local dir = (p:gsub("[/\\][^/\\]*$", ""))
        M._REPO_ROOT = dir .. "/../.."
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
