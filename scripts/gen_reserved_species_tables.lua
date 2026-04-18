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

local function c_string_escape(s)
    s = tostring(s or "")
    s = s:gsub("\\", "\\\\")
    s = s:gsub('"', '\\"')
    s = s:gsub("\r", "")
    s = s:gsub("\n", "\\n")
    return s
end

local function validate_pokedex_description_text(s)
    -- Accept either real newlines or literal "\n" delimiters from fixture text.
    local text = tostring(s or ""):gsub("\\n", "\n")
    local lines = {}
    local start = 1
    while true do
        local nl = text:find("\n", start, true)
        if not nl then
            lines[#lines + 1] = text:sub(start)
            break
        end
        lines[#lines + 1] = text:sub(start, nl - 1)
        start = nl + 1
    end

    if #lines > 3 then
        error("pokedexEntry.descriptionText supports at most 3 lines (use \\n delimiters)")
    end
    for i, line in ipairs(lines) do
        if #line > 43 then
            error(string.format("pokedexEntry.descriptionText line %d exceeds 43 characters", i))
        end
    end
    return text
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
    local footprint_png = png_paths.footprint
    if icon_png and not file_exists(tostring(icon_png)) then
        error("missing fixture png: " .. tostring(icon_png))
    end
    if footprint_png and not file_exists(tostring(footprint_png)) then
        error("missing fixture png: " .. tostring(footprint_png))
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

    local pokedex_entry = raw.pokedexEntry
    if pokedex_entry ~= nil and type(pokedex_entry) ~= "table" then
        error("pokedexEntry must be a table when provided")
    end
    pokedex_entry = pokedex_entry or {}

    local description_symbol = tostring(pokedex_entry.descriptionSymbol or "gDummyPokedexText")
    local unused_description_symbol = tostring(pokedex_entry.unusedDescriptionSymbol or "gDummyPokedexTextUnused")
    local description_text = pokedex_entry.descriptionText
    local unused_description_text = pokedex_entry.unusedDescriptionText
    if description_text ~= nil then
        description_text = validate_pokedex_description_text(description_text)
        description_symbol = "gReservedSlot0PokedexText"
        unused_description_symbol = "gReservedSlot0PokedexTextUnused"
        if unused_description_text == nil then
            unused_description_text = ""
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
            footprint = footprint_png and tostring(footprint_png) or nil,
        },
        pokedexEntry = {
            categoryName = string.sub(tostring(pokedex_entry.categoryName or "CUSTOM"), 1, 11),
            height = tonumber(pokedex_entry.height) or 7,
            weight = tonumber(pokedex_entry.weight) or 69,
            descriptionSymbol = description_symbol,
            unusedDescriptionSymbol = unused_description_symbol,
            descriptionText = description_text and tostring(description_text) or nil,
            unusedDescriptionText = unused_description_text and tostring(unused_description_text) or nil,
            pokemonScale = tonumber(pokedex_entry.pokemonScale) or 256,
            pokemonOffset = tonumber(pokedex_entry.pokemonOffset) or 0,
            trainerScale = tonumber(pokedex_entry.trainerScale) or 256,
            trainerOffset = tonumber(pokedex_entry.trainerOffset) or 0,
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
        pokedexEntry = {
            categoryName = "CUSTOM",
            height = 7,
            weight = 69,
            descriptionSymbol = "gDummyPokedexText",
            unusedDescriptionSymbol = "gDummyPokedexTextUnused",
            pokemonScale = 256,
            pokemonOffset = 0,
            trainerScale = 256,
            trainerOffset = 0,
        },
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

local function write_reserved_custom_graphics_inc(banner, enable_slot0_custom, enable_slot0_footprint_custom)
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
        .. 'const u8 gMonIcon_ReservedSlot0[] = INCBIN_U8("graphics/pokemon/reserved_slot0/icon.4bpp");\n'
    if enable_slot0_footprint_custom then
        body = body .. 'const u8 gMonFootprint_ReservedSlot0[] = INCBIN_U8("graphics/pokemon/reserved_slot0/footprint.1bpp");\n'
    end
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

    -- Party menu icon: 2-frame 32x32 icon sheet (32 tiles total). From optional pngPaths.icon,
    -- else top-left 32x32 of front.png (frame 0; frame 1 becomes blank/padded by gbagfx).
    local icon_src = front_png
    local icon_png = png_paths.icon
    if type(icon_png) == "string" and file_exists(icon_png) then
        copy_file(icon_png, out_dir .. "/icon.png")
        icon_src = out_dir .. "/icon.png"
    end
    run_cmd(string.format("%q %q %q %s", gfx, icon_src, out_dir .. "/icon.4bpp", "-num_tiles 32"))

    -- Footprint: optional pngPaths.footprint (16x16 recommended), converted to 1bpp footprint tiles.
    local footprint_png = png_paths.footprint
    if type(footprint_png) == "string" and file_exists(footprint_png) then
        copy_file(footprint_png, out_dir .. "/footprint.png")
        run_cmd(string.format("%q %q %q %s", gfx, out_dir .. "/footprint.png", out_dir .. "/footprint.1bpp", "-num_tiles 4"))
        fixture.footprintAssetSymbol = "ReservedSlot0"
        fixture.useCustomGeneratedSlot0Footprint = true
    else
        fixture.footprintAssetSymbol = "Bulbasaur"
        fixture.useCustomGeneratedSlot0Footprint = false
    end

    fixture.assetSymbol = "ReservedSlot0"
    fixture.iconAssetSymbol = "ReservedSlot0"
    fixture.iconPaletteIndex = 0
    fixture.useCustomGeneratedSlot0Graphics = true
    return fixture
end

local function write_reserved_pokedex_aux(n, banner, fixture)
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
        local category_name = "CUSTOM"
        local height, weight = 1, 1
        local description_symbol = "gDummyPokedexText"
        local unused_description_symbol = "gDummyPokedexTextUnused"
        local pokemon_scale = 256
        local pokemon_offset = 0
        local trainer_scale = 256
        local trainer_offset = 0
        if i == 0 then
            height, weight = 7, 69
            if fixture and fixture.pokedexEntry then
                local pe = fixture.pokedexEntry
                category_name = string.gsub(tostring(pe.categoryName or category_name), '"', "")
                height = tonumber(pe.height) or height
                weight = tonumber(pe.weight) or weight
                description_symbol = tostring(pe.descriptionSymbol or description_symbol)
                unused_description_symbol = tostring(pe.unusedDescriptionSymbol or unused_description_symbol)
                pokemon_scale = tonumber(pe.pokemonScale) or pokemon_scale
                pokemon_offset = tonumber(pe.pokemonOffset) or pokemon_offset
                trainer_scale = tonumber(pe.trainerScale) or trainer_scale
                trainer_offset = tonumber(pe.trainerOffset) or trainer_offset
            end
        end
        entries[#entries + 1] = string.format(
            [[    [(NATIONAL_DEX_RESERVED_CUSTOM_FIRST + %d)] =
    {
        .categoryName = _("%s"),
        .height = %d,
        .weight = %d,
        .description = %s,
        .unusedDescription = %s,
        .pokemonScale = %d,
        .pokemonOffset = %d,
        .trainerScale = %d,
        .trainerOffset = %d,
    },
]],
            i,
            category_name,
            height,
            weight,
            description_symbol,
            unused_description_symbol,
            pokemon_scale,
            pokemon_offset,
            trainer_scale,
            trainer_offset
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

local function write_reserved_pokedex_text_inc(banner, fixture)
    local path = OUT_DIR .. "/reserved_pokedex_text.inc"
    if not fixture or not fixture.pokedexEntry then
        write_if_changed(path, banner)
        return
    end

    local pe = fixture.pokedexEntry
    if pe.descriptionText == nil and pe.unusedDescriptionText == nil then
        write_if_changed(path, banner)
        return
    end

    local desc = c_string_escape(pe.descriptionText or "")
    local unused = c_string_escape(pe.unusedDescriptionText or "")
    local body = banner
        .. string.format('const u8 gReservedSlot0PokedexText[] = _("%s");\n\n', desc)
        .. string.format('const u8 gReservedSlot0PokedexTextUnused[] = _("%s");\n', unused)
    write_if_changed(path, body)
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

    write_reserved_custom_graphics_inc(
        banner,
        fixture and fixture.useCustomGeneratedSlot0Graphics,
        fixture and fixture.useCustomGeneratedSlot0Footprint
    )

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

    write_reserved_pokedex_aux(n, banner, fixture)
    write_reserved_pokedex_text_inc(banner, fixture)
end

main()
