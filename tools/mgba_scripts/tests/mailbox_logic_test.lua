#!/usr/bin/env lua
-- Unit tests for reserved_species_mailbox.lua (no mGBA; pure Lua 5.3+).
-- Run from repo root: make test-mailbox-lua
-- Optional arg[1] = repo root path if cwd is not the project root.

local root = (arg[1] and #arg[1] > 0) and arg[1] or "."
local chunk, err = loadfile(root .. "/tools/mgba_scripts/reserved_species_mailbox.lua")
if not chunk then
    io.stderr:write(err, "\n")
    os.exit(1)
end
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

--- Minimal emu shim: word-aligned read32/read16 over a sparse int table.
local function makeEmu(mem32)
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

print("OK: mailbox_logic_test (all assertions passed)")
