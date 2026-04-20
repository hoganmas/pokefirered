-- Low-level bus IO, shell/path helpers, and mailbox read helper.

return function(M)
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

    -- GBA ROM is read-only on the CPU bus; mGBA logs "Unimplemented memory Store" for emu:write* to 0x08…
    -- Use the cartridge MemoryDomain (cart0/cart1/cart2) so patches apply without spamming stdout.
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

    return {
        r32 = r32,
        r16 = r16,
        r8 = r8,
        w32 = w32,
        w16 = w16,
        w8 = w8,
        shellSucceeded = shellSucceeded,
        readFileMaybe = readFileMaybe,
        trimPath = trimPath,
    }
end
