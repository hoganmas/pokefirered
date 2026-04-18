-- Integration test for ReservedSpeciesMailbox.applyRuntimePngPair.
-- Runs host PNG->LZ conversion and validates memory writes + table patching logic.
--
-- Run from repo root: make test-mailbox-runtime

local function fail(msg)
    io.stderr:write("FAIL: ", msg, "\n")
    os.exit(1)
end

local function assertEq(a, b, msg)
    if a ~= b then
        fail(string.format("%s expected %s got %s", msg or "assertEq", tostring(b), tostring(a)))
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
    return dirname(info.source:sub(2))
end

local argv = rawget(_G, "arg") or {}
local root = (argv[1] and #argv[1] > 0) and argv[1] or "."
local thisDir = scriptDir()

local candidates = {}
if thisDir then
    candidates[#candidates + 1] = thisDir .. "/reserved_species_mailbox.lua"
end
candidates[#candidates + 1] = root .. "/tools/mgba_scripts/reserved_species_mailbox.lua"

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

chunk()
local M = assert(ReservedSpeciesMailbox)

-- Minimal emu shim: sparse memory words + byte writes.
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
    mem[base + M.OFFSET_MON_FRONT_PIC] = fields.monFrontPicTable
    mem[base + M.OFFSET_MON_BACK_PIC] = fields.monBackPicTable
    mem[base + M.OFFSET_MON_PALETTE] = fields.monPaletteTable
    mem[base + M.OFFSET_SPECIES_NAMES] = fields.speciesNames
    mem[base + M.OFFSET_SIZEOF_SPECIES_INFO] = fields.sizeofSpeciesInfo
    mem[base + M.OFFSET_TARGET_SPECIES] = fields.targetSpecies
    mem[base + M.OFFSET_SPECIES_INFO_ROW_PTR] = fields.speciesInfoRowPtr
    mem[base + M.OFFSET_LEVEL_UP_LEARNSET_ENTRY_ADDR] = fields.levelUpLearnsetEntryAddr
    mem[base + M.OFFSET_RUNTIME_FRONT_LZ] = fields.runtimeFrontLzAddr
    mem[base + M.OFFSET_RUNTIME_BACK_LZ] = fields.runtimeBackLzAddr
    mem[base + M.OFFSET_RUNTIME_PAL_LZ] = fields.runtimePalLzAddr
    mem[base + M.OFFSET_RUNTIME_SHINY_PAL_LZ] = fields.runtimeShinyPalLzAddr
    mem[base + M.OFFSET_MON_SHINY_PALETTE] = fields.monShinyPaletteTable
    mem[base + M.OFFSET_RUNTIME_SCRATCH_END] = fields.runtimeRomScratchEndExclusive
    mem[base + M.OFFSET_TRAIL_MAGIC] = M.TRAIL
end

local function lzUncompressedSize(mem8, addr)
    local b0 = mem8[addr + 0] or 0
    local b1 = mem8[addr + 1] or 0
    local b2 = mem8[addr + 2] or 0
    local b3 = mem8[addr + 3] or 0
    if b0 ~= 0x10 then
        fail(string.format("bad LZ header at 0x%08X: 0x%02X", addr, b0))
    end
    return b1 + b2 * 0x100 + b3 * 0x10000
end

do
    if not loadedPath then
        fail("module path resolution failed")
    end

    local testWork = root .. "/build/mgba_runtime_png_test_" .. tostring(os.time())
    local genCmd = string.format(
        "mkdir -p %q && cd %q && python3 %q --outdir %q",
        testWork,
        root,
        root .. "/tools/mgba_scripts/tests/gen_runtime_test_pngs.py",
        testWork
    )
    local genStatus = os.execute(genCmd)
    if genStatus == false or (type(genStatus) == "number" and genStatus ~= 0) then
        fail("failed to generate runtime test PNGs")
    end

    local mem32, mem8 = {}, {}
    local emu = makeEmu(mem32, mem8)

    local base = 0x02002000
    local speciesId = 412
    local monFrontPicTable = 0x08110000
    local monBackPicTable = 0x08120000
    local monPaletteTable = 0x08130000
    local monShinyPaletteTable = 0x08140000

    local runtimeFront = 0x08EB2000
    local runtimeBack = runtimeFront + 0x3000
    local runtimePal = runtimeBack + 0x3000
    local runtimeShiny = runtimePal + 0x200
    local runtimeEnd = runtimeShiny + 0x200

    placeMailbox(mem32, base, {
        version = M.VERSION,
        count = 16,
        speciesInfo = 0x08000000,
        levelUpLearnsets = 0x08010000,
        monFrontPicTable = monFrontPicTable,
        monBackPicTable = monBackPicTable,
        monPaletteTable = monPaletteTable,
        speciesNames = 0x08030000,
        sizeofSpeciesInfo = 28,
        targetSpecies = speciesId,
        speciesInfoRowPtr = 0x08000000 + speciesId * 28,
        levelUpLearnsetEntryAddr = 0x08020000 + speciesId * 4,
        runtimeFrontLzAddr = runtimeFront,
        runtimeBackLzAddr = runtimeBack,
        runtimePalLzAddr = runtimePal,
        runtimeShinyPalLzAddr = runtimeShiny,
        monShinyPaletteTable = monShinyPaletteTable,
        runtimeRomScratchEndExclusive = runtimeEnd,
    })

    local frontPng = testWork .. "/front.png"
    local backPng = testWork .. "/back.png"
    M.applyRuntimePngPair(emu, base, speciesId, frontPng, backPng, root)

    local frontUncomp = lzUncompressedSize(mem8, runtimeFront)
    local backUncomp = lzUncompressedSize(mem8, runtimeBack)
    local palUncomp = lzUncompressedSize(mem8, runtimePal)
    local shinyUncomp = lzUncompressedSize(mem8, runtimeShiny)

    assertEq(frontUncomp, 2048, "front uncompressed size")
    assertEq(backUncomp, 2048, "back uncompressed size")
    assertEq(palUncomp, 32, "palette uncompressed size")
    assertEq(shinyUncomp, 32, "shiny palette uncompressed size")

    local frontEntry = monFrontPicTable + speciesId * M.SPRITE_SHEET_ENTRY_SIZE
    local backEntry = monBackPicTable + speciesId * M.SPRITE_SHEET_ENTRY_SIZE
    local normalPalEntry = monPaletteTable + speciesId * M.PALETTE_ENTRY_SIZE
    local shinyPalEntry = monShinyPaletteTable + speciesId * M.PALETTE_ENTRY_SIZE

    assertEq(mem32[frontEntry + 0], runtimeFront, "front ptr")
    assertEq(mem32[frontEntry + 4], frontUncomp + speciesId * 65536, "front packed size+tag")
    assertEq(mem32[backEntry + 0], runtimeBack, "back ptr")
    assertEq(mem32[backEntry + 4], backUncomp + speciesId * 65536, "back packed size+tag")
    assertEq(mem32[normalPalEntry + 0], runtimePal, "normal pal ptr")
    assertEq(mem32[normalPalEntry + 4], speciesId, "normal pal tag")
    assertEq(mem32[shinyPalEntry + 0], runtimeShiny, "shiny pal ptr")
    assertEq(mem32[shinyPalEntry + 4], speciesId + M.SPECIES_SHINY_TAG, "shiny pal tag")
end

print("OK: runtime_png_integration_test.lua (all assertions passed)")
