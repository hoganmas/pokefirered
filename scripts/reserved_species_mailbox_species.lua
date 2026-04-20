-- Species/text helper functions (loaded by reserved_species_mailbox.lua).

return function(deps)
    local M = deps.M
    local _dbg = deps._dbg
    local r8 = deps.r8
    local r32 = deps.r32
    local w8 = deps.w8
    local w32 = deps.w32

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

    -- Clone Gen III ROM species definition from srcSpeciesId onto dstSpeciesId using mailbox pointers.
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

    return {
        encodeGen3Text = encodeGen3Text,
    }
end
