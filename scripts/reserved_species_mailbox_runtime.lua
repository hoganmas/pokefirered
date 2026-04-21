-- Runtime sprite conversion/patching helpers (loaded by reserved_species_mailbox.lua).

return function(deps)
    local M = deps.M
    local _dbg = deps._dbg
    local trimPath = deps.trimPath
    local shellSucceeded = deps.shellSucceeded
    local readFileMaybe = deps.readFileMaybe
    local w8 = deps.w8

    local function hostFileExists(path)
        local f = io.open(path, "rb")
        if f then
            f:close()
            return true
        end
        return false
    end

    -- Paths to PokeAPI-style Gen III Ruby/Sapphire sprites (relative to pokefirered root: ../sprites/...).
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

    -- Derive per-slot max LZ sizes from C-filled pointers (no hardcoded ROM addresses or caps in Lua).
    function M.getRuntimeLzScratchLayout(mb)
        if not mb then
            return nil, "nil mailbox"
        end
        local a = mb.runtimeFrontLzAddr
        local b = mb.runtimeBackLzAddr
        local c = mb.runtimePalLzAddr
        local d = mb.runtimeShinyPalLzAddr
        local e = mb.runtimeIconDataAddr or 0
        local f = mb.runtimeFootprintDataAddr or 0
        local g = mb.runtimeRomScratchEndExclusive
        if a == 0 or b == 0 or c == 0 or d == 0 or g == 0 then
            return nil, "mailbox missing runtime LZ slot addresses (rebuild ROM / ReservedSpecies_InitScriptMailbox)"
        end
        local hasIconFootprint = (e > d) and (f > e) and (g > f)
        if not hasIconFootprint then
            -- Backward compatibility with mailbox v6 layout (no icon/footprint scratch pointers).
            e = d + (d - c)
            f = e
        end
        if hasIconFootprint and not (a < b and b < c and c < d and d < e and e < f and f < g) then
            return nil, "runtime scratch addresses must be strictly ascending (front < back < pal < shiny < icon < footprint < end)"
        end
        if (not hasIconFootprint) and not (a < b and b < c and c < d and d < g) then
            return nil, "runtime scratch addresses must be strictly ascending (front < back < pal < shiny < end)"
        end
        local maxIconData = hasIconFootprint and (f - e) or 0
        local maxFootprintData = hasIconFootprint and (g - f) or 0
        local maxShinyPalLz = hasIconFootprint and (e - d) or (g - d)
        local perSpeciesStride = (b - a) + (c - b) + (d - c) + (e - d) + maxIconData + maxFootprintData
        local total = g - a
        local speciesSlots = 1
        if perSpeciesStride > 0 and total >= perSpeciesStride then
            speciesSlots = math.floor(total / perSpeciesStride)
            if speciesSlots < 1 then
                speciesSlots = 1
            end
        end
        return {
            scratchBase = a,
            scratchEndExclusive = g,
            frontAddr = a,
            backAddr = b,
            palAddr = c,
            shinyPalAddr = d,
            iconAddr = hasIconFootprint and e or 0,
            footprintAddr = hasIconFootprint and f or 0,
            maxFrontLz = b - a,
            maxBackLz = c - b,
            maxPalLz = d - c,
            maxShinyPalLz = maxShinyPalLz,
            maxIconData = maxIconData,
            maxFootprintData = maxFootprintData,
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
        local icon = 0
        local footprint = 0
        if layout.maxIconData > 0 then
            icon = shiny + layout.maxShinyPalLz
            footprint = icon + layout.maxIconData
        end
        return {
            front = front,
            back = back,
            pal = pal,
            shiny = shiny,
            icon = icon,
            footprint = footprint,
            maxFrontLz = layout.maxFrontLz,
            maxBackLz = layout.maxBackLz,
            maxPalLz = layout.maxPalLz,
            maxShinyPalLz = layout.maxShinyPalLz,
            maxIconData = layout.maxIconData,
            maxFootprintData = layout.maxFootprintData,
        }, nil
    end

    function M.getRuntimeScratchAddressesForSpecies(mb, speciesId)
        return runtimeLzAddressesForSpecies(mb, speciesId)
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

    -- Host: PNG -> 4bpp.lz / palette.lz via tools/gbagfx only (no Python). Writes manifest.txt in workdir.
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
                    "command failed: "
                        .. cmd
                        .. "\n"
                        .. (err or "(see " .. errLog .. ")")
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

    -- Host-side PNG->LZ77 (tools/gbagfx only), then patch ROM table rows to use ROM scratch LZ blobs.
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

    return {
        pickRandomRsDexWithSprites = pickRandomRsDexWithSprites,
    }
end
