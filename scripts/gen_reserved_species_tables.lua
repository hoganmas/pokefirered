#!/usr/bin/env lua
--[[
Emit per-species placeholder data for NUM_RESERVED_CUSTOM_SPECIES slots.
Run from repo root: lua scripts/gen_reserved_species_tables.lua <count>
See Makefile GEN_RESERVED_SENTINEL / NUM_RESERVED_CUSTOM_SPECIES.
--]]

local OUT_DIR = "include/constants/generated"
local DEFAULT_FIXTURE_PATH = "scripts/tests/reserved_species_fixture.lua"

local function shellSucceeded(a, b, c)
    if a == true then
        return true
    end
    if type(a) == "number" then
        return a == 0
    end
    return false
end

local function run_cmd(cmd)
    local a, b, c = os.execute(cmd)
    if not shellSucceeded(a, b, c) then
        io.stderr:write("gen_reserved_species_tables: command failed:\n  " .. cmd .. "\n")
        os.exit(1)
    end
end

local function write_if_changed(path, text)
    local cur = nil
    local f = io.open(path, "r")
    if f then
        cur = f:read("*a")
        f:close()
    end
    if cur == text then
        return
    end
    f = assert(io.open(path, "w"))
    f:write(text)
    f:close()
end

local function species_id(i)
    return string.format("(SPECIES_CHIMECHO + 1 + %d)", i)
end

local function default_species_info_fields()
    return {
        baseHP = "40",
        baseAttack = "45",
        baseDefense = "40",
        baseSpeed = "50",
        baseSpAttack = "40",
        baseSpDefense = "40",
        types0 = "TYPE_NORMAL",
        types1 = "TYPE_NORMAL",
        catchRate = "255",
        expYield = "62",
        evYield_HP = "0",
        evYield_Attack = "0",
        evYield_Defense = "0",
        evYield_Speed = "0",
        evYield_SpAttack = "0",
        evYield_SpDefense = "0",
        itemCommon = "ITEM_NONE",
        itemRare = "ITEM_NONE",
        genderRatio = "PERCENT_FEMALE(50)",
        eggCycles = "20",
        friendship = "70",
        growthRate = "GROWTH_MEDIUM_FAST",
        eggGroup0 = "EGG_GROUP_FIELD",
        eggGroup1 = "EGG_GROUP_FIELD",
        ability0 = "ABILITY_NONE",
        ability1 = "ABILITY_NONE",
        safariZoneFleeRate = "0",
        bodyColor = "BODY_COLOR_GRAY",
        noFlip = "FALSE",
    }
end

local function file_exists(path)
    local f = io.open(path, "r")
    if f then
        f:close()
        return true
    end
    return false
end

local function normalize_fixture(n)
    local path = os.getenv("RESERVED_SPECIES_TEST_FIXTURE") or DEFAULT_FIXTURE_PATH
    if not file_exists(path) then
        return nil
    end
    local chunk, err = loadfile(path)
    if not chunk then
        error("fixture load failed: " .. tostring(err))
    end
    local raw = chunk()
    if type(raw) ~= "table" then
        error(path .. ": fixture must return a table")
    end
    if raw.enabled == false then
        return nil
    end
    if n <= 0 then
        error("fixture requires NUM_RESERVED_CUSTOM_SPECIES >= 1")
    end

    local name = string.sub(tostring(raw.name or "TSTMON"), 1, 10)
    local asset_symbol = tostring(raw.assetSymbol or "Bulbasaur")
    local learnset_symbol = tostring(raw.learnsetSymbol or "sBulbasaurLevelUpLearnset")
    local cry_id = tostring(raw.cryId or "CRY_CHIMECHO")
    local icon_palette_index = tonumber(raw.iconPaletteIndex) or 0
    if icon_palette_index < 0 or icon_palette_index > 2 then
        error("iconPaletteIndex must be in [0, 2]")
    end

    local png_paths = raw.pngPaths
    if type(png_paths) ~= "table" then
        error("pngPaths must be a table")
    end
    for _, key in ipairs({ "front", "back" }) do
        local p = png_paths[key]
        if not p then
            error("missing pngPaths." .. key)
        end
        if not file_exists(string.format("%s", p)) then
            error("missing fixture png: " .. tostring(p))
        end
    end
    local icon_png = png_paths.icon
    if icon_png and not file_exists(tostring(icon_png)) then
        error("missing fixture png: " .. tostring(icon_png))
    end

    local stats = default_species_info_fields()
    local overrides = raw.speciesInfo
    if type(overrides) == "table" then
        for k, v in pairs(overrides) do
            if stats[k] then
                stats[k] = tostring(v)
            end
        end
    end

    return {
        name = name,
        assetSymbol = asset_symbol,
        learnsetSymbol = learnset_symbol,
        cryId = cry_id,
        iconPaletteIndex = icon_palette_index,
        speciesInfo = stats,
        nationalDex = tostring(raw.nationalDex or "NATIONAL_DEX_RESERVED_CUSTOM_FIRST"),
        hoennDex = tostring(raw.hoennDex or "HOENN_DEX_NONE"),
        pngPaths = {
            front = tostring(png_paths.front),
            back = tostring(png_paths.back),
            icon = icon_png and tostring(icon_png) or nil,
        },
    }
end

local function make_debug_slot0_fixture()
    local st = default_species_info_fields()
    st.baseHP = "45"
    st.baseAttack = "49"
    st.baseDefense = "49"
    st.baseSpeed = "45"
    st.baseSpAttack = "65"
    st.baseSpDefense = "65"
    st.types0 = "TYPE_GRASS"
    st.types1 = "TYPE_POISON"
    st.growthRate = "GROWTH_MEDIUM_SLOW"
    st.ability0 = "ABILITY_OVERGROW"
    return {
        name = "RSVDBG0",
        assetSymbol = "Bulbasaur",
        learnsetSymbol = "sBulbasaurLevelUpLearnset",
        cryId = "CRY_CHIMECHO",
        iconPaletteIndex = 1,
        speciesInfo = st,
        nationalDex = "NATIONAL_DEX_RESERVED_CUSTOM_FIRST",
        hoennDex = "HOENN_DEX_NONE",
    }
end

local function species_info_entry(i, fixture)
    local sid = species_id(i)
    local fields
    if fixture and i == 0 then
        fields = fixture.speciesInfo
    else
        fields = default_species_info_fields()
    end
    return string.format(
        [[    [%s] =
    {
        .baseHP = %s,
        .baseAttack = %s,
        .baseDefense = %s,
        .baseSpeed = %s,
        .baseSpAttack = %s,
        .baseSpDefense = %s,
        .types = {%s, %s},
        .catchRate = %s,
        .expYield = %s,
        .evYield_HP = %s,
        .evYield_Attack = %s,
        .evYield_Defense = %s,
        .evYield_Speed = %s,
        .evYield_SpAttack = %s,
        .evYield_SpDefense = %s,
        .itemCommon = %s,
        .itemRare = %s,
        .genderRatio = %s,
        .eggCycles = %s,
        .friendship = %s,
        .growthRate = %s,
        .eggGroups = {%s, %s},
        .abilities = {%s, %s},
        .safariZoneFleeRate = %s,
        .bodyColor = %s,
        .noFlip = %s,
    },]],
        sid,
        fields.baseHP,
        fields.baseAttack,
        fields.baseDefense,
        fields.baseSpeed,
        fields.baseSpAttack,
        fields.baseSpDefense,
        fields.types0,
        fields.types1,
        fields.catchRate,
        fields.expYield,
        fields.evYield_HP,
        fields.evYield_Attack,
        fields.evYield_Defense,
        fields.evYield_Speed,
        fields.evYield_SpAttack,
        fields.evYield_SpDefense,
        fields.itemCommon,
        fields.itemRare,
        fields.genderRatio,
        fields.eggCycles,
        fields.friendship,
        fields.growthRate,
        fields.eggGroup0,
        fields.eggGroup1,
        fields.ability0,
        fields.ability1,
        fields.safariZoneFleeRate,
        fields.bodyColor,
        fields.noFlip
    )
end

local function copy_file(src, dst)
    local inf = assert(io.open(src, "rb"))
    local data = inf:read("*a")
    inf:close()
    local outf = assert(io.open(dst, "wb"))
    outf:write(data)
    outf:close()
end

local function write_reserved_custom_graphics_inc(banner, enable_slot0_custom)
    local path = OUT_DIR .. "/reserved_custom_graphics.inc"
    if not enable_slot0_custom then
        write_if_changed(path, banner)
        return
    end
    local body = banner
        .. 'const u32 gMonFrontPic_ReservedSlot0[] = INCBIN_U32("graphics/pokemon/reserved_slot0/front.4bpp.lz");\n'
        .. 'const u32 gMonBackPic_ReservedSlot0[] = INCBIN_U32("graphics/pokemon/reserved_slot0/back.4bpp.lz");\n'
        .. 'const u32 gMonPalette_ReservedSlot0[] = INCBIN_U32("graphics/pokemon/reserved_slot0/normal.gbapal.lz");\n'
        .. 'const u32 gMonShinyPalette_ReservedSlot0[] = INCBIN_U32("graphics/pokemon/reserved_slot0/shiny.gbapal.lz");\n'
    write_if_changed(path, body)
end

local function materialize_slot0_fixture_assets(fixture)
    if fixture == nil then
        return nil
    end
    local png_paths = fixture.pngPaths
    if type(png_paths) ~= "table" then
        return fixture
    end

    local out_dir = "graphics/pokemon/reserved_slot0"
    run_cmd(string.format("mkdir -p %q", out_dir))

    local front_png = out_dir .. "/front.png"
    local back_png = out_dir .. "/back.png"
    copy_file(png_paths.front, front_png)
    copy_file(png_paths.back, back_png)

    local gfx = "tools/gbagfx/gbagfx"
    run_cmd(string.format("%q %q %q %s", gfx, front_png, out_dir .. "/front.4bpp", "-num_tiles 64"))
    run_cmd(string.format("%q %q %q", gfx, out_dir .. "/front.4bpp", out_dir .. "/front.4bpp.lz"))
    run_cmd(string.format("%q %q %q %s", gfx, back_png, out_dir .. "/back.4bpp", "-num_tiles 64"))
    run_cmd(string.format("%q %q %q", gfx, out_dir .. "/back.4bpp", out_dir .. "/back.4bpp.lz"))
    run_cmd(string.format("%q %q %q", gfx, front_png, out_dir .. "/normal.gbapal"))
    run_cmd(string.format("%q %q %q", gfx, out_dir .. "/normal.gbapal", out_dir .. "/normal.gbapal.lz"))
    copy_file(out_dir .. "/normal.gbapal", out_dir .. "/shiny.gbapal")
    copy_file(out_dir .. "/normal.gbapal.lz", out_dir .. "/shiny.gbapal.lz")

    fixture.assetSymbol = "ReservedSlot0"
    fixture.iconAssetSymbol = "QuestionMark"
    fixture.footprintAssetSymbol = "Bulbasaur"
    fixture.iconPaletteIndex = 0
    fixture.useCustomGeneratedSlot0Graphics = true
    return fixture
end

local function write_reserved_pokedex_aux(n, banner)
    if n <= 0 then
        return
    end
    local comma_ndex = {}
    for i = 0, n - 1 do
        comma_ndex[#comma_ndex + 1] = string.format("    (NATIONAL_DEX_RESERVED_CUSTOM_FIRST + %d)", i)
    end
    comma_ndex = table.concat(comma_ndex, ",\n") .. ",\n"

    local entries = {}
    for i = 0, n - 1 do
        local height, weight
        if i == 0 then
            height, weight = 7, 69
        else
            height, weight = 1, 1
        end
        entries[#entries + 1] = string.format(
            [[    [(NATIONAL_DEX_RESERVED_CUSTOM_FIRST + %d)] =
    {
        .categoryName = _("CUSTOM"),
        .height = %d,
        .weight = %d,
        .description = gDummyPokedexText,
        .unusedDescription = gDummyPokedexTextUnused,
        .pokemonScale = 256,
        .pokemonOffset = 0,
        .trainerScale = 256,
        .trainerOffset = 0,
    },
]],
            i,
            height,
            weight
        )
    end
    write_if_changed(OUT_DIR .. "/reserved_pokedex_entries.inc", banner .. table.concat(entries))

    local type_lines = {}
    for i = 0, n - 1 do
        type_lines[#type_lines + 1] = string.format("    (SPECIES_CHIMECHO + 1 + %d)", i)
    end
    type_lines = table.concat(type_lines, ",\n") .. ",\n"

    write_if_changed(OUT_DIR .. "/reserved_pokedex_order_weight_append.inc", comma_ndex)
    write_if_changed(OUT_DIR .. "/reserved_pokedex_order_height_append.inc", comma_ndex)
    write_if_changed(OUT_DIR .. "/reserved_pokedex_order_alphabetical_append.inc", comma_ndex)
    write_if_changed(OUT_DIR .. "/reserved_pokedex_order_type_append.inc", type_lines)
end

local function main()
    local n = tonumber(arg[1]) or tonumber(os.getenv("NUM_RESERVED_CUSTOM_SPECIES") or "16") or 16
    if n < 0 or n > 64 then
        io.stderr:write("count must be 0..64\n")
        os.exit(1)
    end

    local fixture = normalize_fixture(n)
    if fixture == nil and os.getenv("RESERVED_SPECIES_DEBUG_SLOT0") == "1" and n > 0 then
        fixture = make_debug_slot0_fixture()
    end
    fixture = materialize_slot0_fixture_assets(fixture)

    run_cmd(string.format("mkdir -p %q", OUT_DIR))

    local banner = string.format(
        "/* Auto-generated by scripts/gen_reserved_species_tables.lua — do not edit. */\n/* NUM_RESERVED_CUSTOM_SPECIES = %d */\n\n",
        n
    )

    write_reserved_custom_graphics_inc(banner, fixture and fixture.useCustomGeneratedSlot0Graphics)

    local body = {}
    for i = 0, n - 1 do
        body[#body + 1] = species_info_entry(i, fixture) .. "\n"
    end
    write_if_changed(OUT_DIR .. "/reserved_species_info.inc", banner .. table.concat(body))

    local lines = {}
    for i = 0, n - 1 do
        local sid = species_id(i)
        if fixture and i == 0 then
            lines[#lines + 1] = string.format("    [%s] = %s,\n", sid, fixture.learnsetSymbol)
        else
            lines[#lines + 1] = string.format("    [%s] = sReservedSpeciesEmptyLearnset,\n", sid)
        end
    end
    write_if_changed(OUT_DIR .. "/reserved_learnset_ptrs.inc", banner .. table.concat(lines))

    lines = {}
    for i = 0, n - 1 do
        lines[#lines + 1] = string.format("    [%s]    = TMHM_LEARNSET(0),\n", species_id(i))
    end
    write_if_changed(OUT_DIR .. "/reserved_tmhm.inc", banner .. table.concat(lines))

    lines = {}
    for i = 0, n - 1 do
        lines[#lines + 1] = string.format("    [%s] = 0,\n", species_id(i))
    end
    write_if_changed(OUT_DIR .. "/reserved_tutor.inc", banner .. table.concat(lines))

    lines = {}
    for i = 0, n - 1 do
        local sid = species_id(i)
        local cry = fixture and i == 0 and fixture.cryId or "CRY_CHIMECHO"
        lines[#lines + 1] = string.format("    [%s - HOENN_MON_SPECIES_START] = %s,\n", sid, cry)
    end
    write_if_changed(OUT_DIR .. "/reserved_cry_ids.inc", banner .. table.concat(lines))

    local pic = {}
    for i = 0, n - 1 do
        local sid = species_id(i)
        local asset = fixture and i == 0 and fixture.assetSymbol or "CircledQuestionMark"
        pic[#pic + 1] = string.format("    [%s] = {gMonFrontPic_%s, 0x800, %s},\n", sid, asset, sid)
    end
    write_if_changed(OUT_DIR .. "/reserved_front_pic.inc", banner .. table.concat(pic))

    local picb = {}
    for i = 0, n - 1 do
        local sid = species_id(i)
        local asset = fixture and i == 0 and fixture.assetSymbol or "CircledQuestionMark"
        picb[#picb + 1] = string.format("    [%s] = {gMonBackPic_%s, 0x800, %s},\n", sid, asset, sid)
    end
    write_if_changed(OUT_DIR .. "/reserved_back_pic.inc", banner .. table.concat(picb))

    local pal = {}
    for i = 0, n - 1 do
        local sid = species_id(i)
        local asset = fixture and i == 0 and fixture.assetSymbol or "CircledQuestionMark"
        pal[#pal + 1] = string.format("    [%s] = {gMonPalette_%s, %s},\n", sid, asset, sid)
    end
    write_if_changed(OUT_DIR .. "/reserved_palette.inc", banner .. table.concat(pal))

    local sh = {}
    for i = 0, n - 1 do
        local sid = species_id(i)
        local asset = fixture and i == 0 and fixture.assetSymbol or "CircledQuestionMark"
        sh[#sh + 1] =
            string.format("    [%s] = {gMonShinyPalette_%s, %s + SPECIES_SHINY_TAG},\n", sid, asset, sid)
    end
    write_if_changed(OUT_DIR .. "/reserved_shiny_palette.inc", banner .. table.concat(sh))

    local fp = {}
    for i = 0, n - 1 do
        local sid = species_id(i)
        local asset
        if fixture and i == 0 then
            asset = fixture.footprintAssetSymbol or fixture.assetSymbol
        else
            asset = "Bulbasaur"
        end
        fp[#fp + 1] = string.format("    [%s] = gMonFootprint_%s,\n", sid, asset)
    end
    write_if_changed(OUT_DIR .. "/reserved_footprint.inc", banner .. table.concat(fp))

    local coord = [[        .size = MON_COORDS_SIZE(32, 32),
        .y_offset = 16,
]]
    local fc = {}
    for i = 0, n - 1 do
        local sid = species_id(i)
        fc[#fc + 1] = string.format("    [%s] =\n    {\n%s    },\n", sid, coord)
    end
    write_if_changed(OUT_DIR .. "/reserved_front_coords.inc", banner .. table.concat(fc))
    write_if_changed(OUT_DIR .. "/reserved_back_coords.inc", banner .. table.concat(fc))

    local nm = {}
    for i = 0, n - 1 do
        local sid = species_id(i)
        if fixture and i == 0 then
            nm[#nm + 1] = string.format('    [%s] = _("%s"),\n', sid, fixture.name)
        else
            nm[#nm + 1] = string.format('    [%s] = _("RSV%02d"),\n', sid, i)
        end
    end
    write_if_changed(OUT_DIR .. "/reserved_species_names.inc", banner .. table.concat(nm))

    local icon = {}
    local icon_pal = {}
    for i = 0, n - 1 do
        local sid = species_id(i)
        if fixture and i == 0 then
            local asset = fixture.iconAssetSymbol or fixture.assetSymbol
            icon[#icon + 1] = string.format("    [%s] = gMonIcon_%s,\n", sid, asset)
            icon_pal[#icon_pal + 1] =
                string.format("    [%s] = %d,\n", sid, tonumber(fixture.iconPaletteIndex) or 0)
        else
            icon[#icon + 1] = string.format("    [%s] = gMonIcon_QuestionMark,\n", sid)
            icon_pal[#icon_pal + 1] = "    [" .. sid .. "] = 0,\n"
        end
    end
    write_if_changed(OUT_DIR .. "/reserved_icon_table.inc", banner .. table.concat(icon))
    write_if_changed(OUT_DIR .. "/reserved_icon_palette_indices.inc", banner .. table.concat(icon_pal))

    local dex_h = {}
    local dex_n = {}
    for i = 0, n - 1 do
        local sid = species_id(i)
        if fixture and i == 0 then
            dex_h[#dex_h + 1] =
                string.format("    [%s - 1] = %s,\n", sid, fixture.hoennDex or "HOENN_DEX_NONE")
            dex_n[#dex_n + 1] =
                string.format("    [%s - 1] = %s,\n", sid, fixture.nationalDex or "NATIONAL_DEX_RESERVED_CUSTOM_FIRST")
        else
            dex_h[#dex_h + 1] = string.format("    [%s - 1] = HOENN_DEX_NONE,\n", sid)
            dex_n[#dex_n + 1] =
                string.format("    [%s - 1] = (NATIONAL_DEX_RESERVED_CUSTOM_FIRST + %d),\n", sid, i)
        end
    end
    write_if_changed(OUT_DIR .. "/reserved_pokedex_hoenn.inc", banner .. table.concat(dex_h))
    write_if_changed(OUT_DIR .. "/reserved_pokedex_national.inc", banner .. table.concat(dex_n))

    write_reserved_pokedex_aux(n, banner)
end

main()
