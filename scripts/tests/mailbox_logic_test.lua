-- (Note) mGBA Lua doesn't support shebang lines; keep this file pure Lua.
-- Unit tests for reserved_species_mailbox.lua (no mGBA; pure Lua 5.3+).
-- Run from repo root: make test-mailbox-lua (or: lua scripts/tests/mailbox_logic_test.lua "$(pwd)")
-- Optional arg[1] = repo root path if cwd is not the project root.

local function log(msg)
    if console and console.log then
        console:log(msg)
    else
        print(msg)
    end
end

local function dirname(path)
    return (path:gsub("[/\\][^/\\]*$", ""))
end

local function scriptDir()
    local info = debug.getinfo(1, "S")
    if not info or not info.source then
        return nil
    end
    if info.source:sub(1, 1) ~= "@" then
        return nil
    end
    local path = info.source:sub(2)
    return dirname(path)
end

local argv = rawget(_G, "arg") or {}
local root = (argv[1] and #argv[1] > 0) and argv[1] or "."
local thisDir = scriptDir()
log(string.format("DBG: loading mailbox_logic_test.lua (root=%s dir=%s)", tostring(root), tostring(thisDir)))

local candidates = {}
if thisDir then
    candidates[#candidates + 1] = thisDir .. "/../reserved_species_mailbox.lua"
end
candidates[#candidates + 1] = root .. "/scripts/reserved_species_mailbox.lua"

local chunk, err, loadedPath = nil, nil, nil
for _, path in ipairs(candidates) do
    chunk, err = loadfile(path)
    if chunk then
        loadedPath = path
        break
    end
end

if not chunk then
    io.stderr:write("Failed to load reserved_species_mailbox.lua. Tried:\n")
    for _, path in ipairs(candidates) do
        io.stderr:write("  - ", path, "\n")
    end
    io.stderr:write(err or "unknown loadfile error", "\n")
    os.exit(1)
end
log("DBG: loaded reserved_species_mailbox.lua from " .. tostring(loadedPath) .. "; running tests")
chunk()
local M = assert(ReservedSpeciesMailbox)

local function fail(msg)
    io.stderr:write("FAIL: ", msg, "\n")
    os.exit(1)
end

local function assertEq(a, b, msg)
    if a ~= b then
        fail(string.format("%s expected %s got %s", msg or "assertEq", tostring(b), tostring(a)))
    end
end

--- Minimal emu shim: word-aligned read32/read16 over sparse int table + optional byte writes.
local function makeEmu(mem32, mem8)
    mem8 = mem8 or {}
    return {
        read32 = function(_, a)
            assert(a % 4 == 0, "unaligned read32")
            return mem32[a] or 0
        end,
        read16 = function(_, a)
            assert(a % 2 == 0, "unaligned read16")
            local w = mem32[a - (a % 4)] or 0
            if a % 4 == 0 then
                return w % 65536
            end
            return math.floor(w / 65536) % 65536
        end,
        write8 = function(_, a, v)
            mem8[a] = v % 256
        end,
        write32 = function(_, a, v)
            assert(a % 4 == 0, "unaligned write32")
            mem32[a] = v
        end,
    }
end

local function placeMailbox(mem, base, fields)
    mem[base + M.OFFSET_MAGIC] = M.MAGIC
    mem[base + M.OFFSET_VERSION] = fields.version + (fields.count * 65536)
    mem[base + M.OFFSET_SPECIES_INFO] = fields.speciesInfo
    mem[base + M.OFFSET_LEVEL_UP_LEARNSETS] = fields.levelUpLearnsets
    mem[base + M.OFFSET_MON_FRONT_PIC] = fields.monFrontPicTable or 0
    mem[base + M.OFFSET_MON_BACK_PIC] = fields.monBackPicTable or 0
    mem[base + M.OFFSET_MON_PALETTE] = fields.monPaletteTable or 0
    mem[base + M.OFFSET_SPECIES_NAMES] = fields.speciesNames or 0
    mem[base + M.OFFSET_SIZEOF_SPECIES_INFO] = fields.sizeofSpeciesInfo
    mem[base + M.OFFSET_TARGET_SPECIES] = fields.targetSpecies + ((fields.padding16 or 0) * 65536)
    mem[base + M.OFFSET_SPECIES_INFO_ROW_PTR] = fields.speciesInfoRowPtr
    mem[base + M.OFFSET_LEVEL_UP_LEARNSET_ENTRY_ADDR] = fields.levelUpLearnsetEntryAddr
    mem[base + M.OFFSET_RUNTIME_FRONT_LZ] = fields.runtimeFrontLzAddr or 0
    mem[base + M.OFFSET_RUNTIME_BACK_LZ] = fields.runtimeBackLzAddr or 0
    mem[base + M.OFFSET_RUNTIME_PAL_LZ] = fields.runtimePalLzAddr or 0
    mem[base + M.OFFSET_RUNTIME_SHINY_PAL_LZ] = fields.runtimeShinyPalLzAddr or 0
    mem[base + M.OFFSET_MON_SHINY_PALETTE] = fields.monShinyPaletteTable or 0
    mem[base + M.OFFSET_RUNTIME_SCRATCH_END] = fields.runtimeRomScratchEndExclusive or 0
    mem[base + M.OFFSET_TRAIL_MAGIC] = M.TRAIL
end

-- --- tests ---
do
    local mem = {}
    local base = 0x2000
    local speciesInfo = 0x08000000
    local sizeofSi = 28
    local target = 412
    local rowPtr = speciesInfo + target * sizeofSi
    placeMailbox(mem, base, {
        version = M.VERSION,
        count = 16,
        speciesInfo = speciesInfo,
        levelUpLearnsets = 0x08010000,
        sizeofSpeciesInfo = sizeofSi,
        targetSpecies = target,
        speciesInfoRowPtr = rowPtr,
        levelUpLearnsetEntryAddr = 0x08020000 + target * 4,
    })
    local emu = makeEmu(mem)
    assertEq(M.findMailbox(emu, 0x1000, 0x3000), base, "findMailbox")
    local ok = M.validateMailbox(emu, base)
    if not ok then
        fail("validateMailbox")
    end
    local mb = M.readMailbox(emu, base)
    assertEq(mb.magic, M.MAGIC, "magic")
    assertEq(mb.trailMagic, M.TRAIL, "trail")
    assertEq(mb.version, M.VERSION, "version")
    assertEq(mb.count, 16, "count")
    assertEq(mb.targetSpecies, target, "targetSpecies")
    assertEq(mb.speciesInfoRowPtr, rowPtr, "rowPtr")
    if not M.rowPtrMatchesComputed(emu, base) then
        fail("rowPtrMatchesComputed")
    end
end

do
    local mem = {}
    placeMailbox(mem, 0x5000, {
        version = 99,
        count = 1,
        speciesInfo = 0,
        sizeofSpeciesInfo = 1,
        targetSpecies = 0,
        speciesInfoRowPtr = 0,
        levelUpLearnsetEntryAddr = 0,
    })
    local emu = makeEmu(mem)
    local ok = M.validateMailbox(emu, 0x5000)
    if ok then
        fail("validateMailbox should reject bad version")
    end
end

do
    assertEq(M.speciesInfoRowPtrFromBase(0x08000000, 5, 28), 0x08000000 + 5 * 28, "speciesInfoRowPtrFromBase")
end

do
    local mb = {
        runtimeFrontLzAddr = 0x08EB0000,
        runtimeBackLzAddr = 0x08EB1000,
        runtimePalLzAddr = 0x08EB2000,
        runtimeShinyPalLzAddr = 0x08EB2100,
        runtimeRomScratchEndExclusive = 0x08EB2300,
    }
    local lz, err = M.getRuntimeLzScratchLayout(mb)
    if not lz then
        fail(err or "getRuntimeLzScratchLayout")
    end
    assertEq(lz.maxFrontLz, 0x1000, "maxFrontLz")
    assertEq(lz.maxBackLz, 0x1000, "maxBackLz")
    assertEq(lz.maxPalLz, 0x100, "maxPalLz")
    assertEq(lz.maxShinyPalLz, 0x200, "maxShinyPalLz")
end

do
    local mem = {}
    local mem8 = {}
    local base = 0x6000
    local speciesNames = 0x08030000
    local target = 412
    placeMailbox(mem, base, {
        version = M.VERSION,
        count = 4,
        speciesInfo = 0x08000000,
        levelUpLearnsets = 0x08010000,
        speciesNames = speciesNames,
        sizeofSpeciesInfo = 28,
        targetSpecies = target,
        speciesInfoRowPtr = 0x08000000 + target * 28,
        levelUpLearnsetEntryAddr = 0x08020000 + target * 4,
    })
    local emu = makeEmu(mem, mem8)
    local name = "LUAUNQ42"
    local writeAddr = M.writeReservedSpeciesName(emu, base, 0, name)
    local expectedAddr = speciesNames + target * M.SPECIES_NAME_STRIDE
    assertEq(writeAddr, expectedAddr, "writeReservedSpeciesName addr")
    local expected = { 0xC6, 0xCF, 0xBB, 0xCF, 0xC8, 0xCB, 0xA5, 0xA3 }
    for i = 1, #expected do
        assertEq(mem8[writeAddr + (i - 1)], expected[i], "encoded name byte " .. i)
    end
    for i = #expected + 1, M.POKEMON_NAME_LENGTH + 1 do
        assertEq(mem8[writeAddr + (i - 1)], 0xFF, "EOS fill byte " .. i)
    end
end

print("OK: mailbox_logic_test (all assertions passed)")
