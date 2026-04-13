#!/usr/bin/env python3
"""Emit per-species placeholder data for NUM_RESERVED_CUSTOM_SPECIES slots.

Run from repo root (see Makefile). Count must match include/constants/species.h layout:
  SPECIES_EGG == SPECIES_CHIMECHO + 1 + NUM_RESERVED_CUSTOM_SPECIES
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys

OUT_DIR = os.path.join("include", "constants", "generated")
DEFAULT_FIXTURE_PATH = os.path.join("tools", "mgba_scripts", "tests", "reserved_species_fixture.json")


def write_if_changed(path: str, text: str) -> None:
    try:
        with open(path, encoding="utf-8") as f:
            if f.read() == text:
                return
    except OSError:
        pass
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)


def species_id(i: int) -> str:
    return f"(SPECIES_CHIMECHO + 1 + {i})"


def default_species_info_fields() -> dict[str, str]:
    return {
        "baseHP": "40",
        "baseAttack": "45",
        "baseDefense": "40",
        "baseSpeed": "50",
        "baseSpAttack": "40",
        "baseSpDefense": "40",
        "types0": "TYPE_NORMAL",
        "types1": "TYPE_NORMAL",
        "catchRate": "255",
        "expYield": "62",
        "evYield_HP": "0",
        "evYield_Attack": "0",
        "evYield_Defense": "0",
        "evYield_Speed": "0",
        "evYield_SpAttack": "0",
        "evYield_SpDefense": "0",
        "itemCommon": "ITEM_NONE",
        "itemRare": "ITEM_NONE",
        "genderRatio": "PERCENT_FEMALE(50)",
        "eggCycles": "20",
        "friendship": "70",
        "growthRate": "GROWTH_MEDIUM_FAST",
        "eggGroup0": "EGG_GROUP_FIELD",
        "eggGroup1": "EGG_GROUP_FIELD",
        "ability0": "ABILITY_NONE",
        "ability1": "ABILITY_NONE",
        "safariZoneFleeRate": "0",
        "bodyColor": "BODY_COLOR_GRAY",
        "noFlip": "FALSE",
    }


def normalize_fixture(n: int) -> dict | None:
    path = os.environ.get("RESERVED_SPECIES_TEST_FIXTURE_JSON", DEFAULT_FIXTURE_PATH)
    if not os.path.exists(path):
        return None
    with open(path, encoding="utf-8") as f:
        raw = json.load(f)
    if not isinstance(raw, dict):
        raise ValueError(f"{path}: root must be an object")
    if raw.get("enabled", True) is False:
        return None
    if n <= 0:
        raise ValueError("fixture requires NUM_RESERVED_CUSTOM_SPECIES >= 1")

    name = str(raw.get("name", "TSTMON"))[:10]
    asset_symbol = str(raw.get("assetSymbol", "Bulbasaur"))
    learnset_symbol = str(raw.get("learnsetSymbol", "sBulbasaurLevelUpLearnset"))
    cry_id = str(raw.get("cryId", "CRY_CHIMECHO"))
    icon_palette_index = int(raw.get("iconPaletteIndex", 0))
    if icon_palette_index < 0 or icon_palette_index > 2:
        raise ValueError("iconPaletteIndex must be in [0, 2]")

    png_paths = raw.get("pngPaths", {})
    if not isinstance(png_paths, dict):
        raise ValueError("pngPaths must be an object")
    for key in ("front", "back"):
        p = png_paths.get(key)
        if not p:
            raise ValueError(f"missing pngPaths.{key}")
        if not os.path.exists(str(p)):
            raise ValueError(f"missing fixture png: {p}")
    icon_png = png_paths.get("icon")
    if icon_png and not os.path.exists(str(icon_png)):
        raise ValueError(f"missing fixture png: {icon_png}")

    stats = default_species_info_fields()
    overrides = raw.get("speciesInfo", {})
    if not isinstance(overrides, dict):
        raise ValueError("speciesInfo must be an object")
    for k, v in overrides.items():
        if k in stats:
            stats[k] = str(v)

    return {
        "name": name,
        "assetSymbol": asset_symbol,
        "learnsetSymbol": learnset_symbol,
        "cryId": cry_id,
        "iconPaletteIndex": icon_palette_index,
        "speciesInfo": stats,
        "nationalDex": str(raw.get("nationalDex", "NATIONAL_DEX_RESERVED_CUSTOM_FIRST")),
        "hoennDex": str(raw.get("hoennDex", "HOENN_DEX_NONE")),
        "pngPaths": {
            "front": str(png_paths["front"]),
            "back": str(png_paths["back"]),
            "icon": str(icon_png) if icon_png else None,
        },
    }


def make_debug_slot0_fixture() -> dict:
    """When RESERVED_SPECIES_DEBUG_SLOT0=1: slot 0 mirrors Bulbasaur dex + graphics (no JSON fixture)."""
    st = default_species_info_fields()
    st.update(
        {
            "baseHP": "45",
            "baseAttack": "49",
            "baseDefense": "49",
            "baseSpeed": "45",
            "baseSpAttack": "65",
            "baseSpDefense": "65",
            "types0": "TYPE_GRASS",
            "types1": "TYPE_POISON",
            "growthRate": "GROWTH_MEDIUM_SLOW",
            "ability0": "ABILITY_OVERGROW",
        }
    )
    return {
        "name": "RSVDBG0",
        "assetSymbol": "Bulbasaur",
        "learnsetSymbol": "sBulbasaurLevelUpLearnset",
        "cryId": "CRY_CHIMECHO",
        # Match gMonIconPaletteIndices[S Bulbasaur] (see pokemon_icon.c).
        "iconPaletteIndex": 1,
        "speciesInfo": st,
        "nationalDex": "NATIONAL_DEX_RESERVED_CUSTOM_FIRST",
        "hoennDex": "HOENN_DEX_NONE",
    }


def species_info_entry(i: int, fixture: dict | None) -> str:
    sid = species_id(i)
    fields = fixture["speciesInfo"] if fixture and i == 0 else default_species_info_fields()
    return f"""    [{sid}] =
    {{
        .baseHP = {fields["baseHP"]},
        .baseAttack = {fields["baseAttack"]},
        .baseDefense = {fields["baseDefense"]},
        .baseSpeed = {fields["baseSpeed"]},
        .baseSpAttack = {fields["baseSpAttack"]},
        .baseSpDefense = {fields["baseSpDefense"]},
        .types = {{{fields["types0"]}, {fields["types1"]}}},
        .catchRate = {fields["catchRate"]},
        .expYield = {fields["expYield"]},
        .evYield_HP = {fields["evYield_HP"]},
        .evYield_Attack = {fields["evYield_Attack"]},
        .evYield_Defense = {fields["evYield_Defense"]},
        .evYield_Speed = {fields["evYield_Speed"]},
        .evYield_SpAttack = {fields["evYield_SpAttack"]},
        .evYield_SpDefense = {fields["evYield_SpDefense"]},
        .itemCommon = {fields["itemCommon"]},
        .itemRare = {fields["itemRare"]},
        .genderRatio = {fields["genderRatio"]},
        .eggCycles = {fields["eggCycles"]},
        .friendship = {fields["friendship"]},
        .growthRate = {fields["growthRate"]},
        .eggGroups = {{{fields["eggGroup0"]}, {fields["eggGroup1"]}}},
        .abilities = {{{fields["ability0"]}, {fields["ability1"]}}},
        .safariZoneFleeRate = {fields["safariZoneFleeRate"]},
        .bodyColor = {fields["bodyColor"]},
        .noFlip = {fields["noFlip"]},
    }},"""


def run_cmd(cmd: list[str]) -> None:
    subprocess.run(cmd, check=True)


def write_reserved_custom_graphics_inc(banner: str, enable_slot0_custom: bool) -> None:
    path = os.path.join(OUT_DIR, "reserved_custom_graphics.inc")
    if not enable_slot0_custom:
        write_if_changed(path, banner)
        return

    body = [
        banner,
        "const u32 gMonFrontPic_ReservedSlot0[] = INCBIN_U32(\"graphics/pokemon/reserved_slot0/front.4bpp.lz\");\n",
        "const u32 gMonBackPic_ReservedSlot0[] = INCBIN_U32(\"graphics/pokemon/reserved_slot0/back.4bpp.lz\");\n",
        "const u32 gMonPalette_ReservedSlot0[] = INCBIN_U32(\"graphics/pokemon/reserved_slot0/normal.gbapal.lz\");\n",
        "const u32 gMonShinyPalette_ReservedSlot0[] = INCBIN_U32(\"graphics/pokemon/reserved_slot0/shiny.gbapal.lz\");\n",
    ]
    write_if_changed(path, "".join(body))


def materialize_slot0_fixture_assets(fixture: dict | None) -> dict | None:
    if fixture is None:
        return None
    png_paths = fixture.get("pngPaths")
    if not isinstance(png_paths, dict):
        return fixture

    out_dir = os.path.join("graphics", "pokemon", "reserved_slot0")
    os.makedirs(out_dir, exist_ok=True)

    front_png = os.path.join(out_dir, "front.png")
    back_png = os.path.join(out_dir, "back.png")
    shutil.copyfile(os.path.abspath(png_paths["front"]), front_png)
    shutil.copyfile(os.path.abspath(png_paths["back"]), back_png)

    gfx = os.path.join("tools", "gbagfx", "gbagfx")
    run_cmd([gfx, front_png, os.path.join(out_dir, "front.4bpp"), "-num_tiles", "64"])
    run_cmd([gfx, os.path.join(out_dir, "front.4bpp"), os.path.join(out_dir, "front.4bpp.lz")])
    run_cmd([gfx, back_png, os.path.join(out_dir, "back.4bpp"), "-num_tiles", "64"])
    run_cmd([gfx, os.path.join(out_dir, "back.4bpp"), os.path.join(out_dir, "back.4bpp.lz")])

    # Use the front sprite's palette for both normal/shiny in this test path.
    run_cmd([gfx, front_png, os.path.join(out_dir, "normal.gbapal")])
    run_cmd([gfx, os.path.join(out_dir, "normal.gbapal"), os.path.join(out_dir, "normal.gbapal.lz")])
    shutil.copyfile(os.path.join(out_dir, "normal.gbapal"), os.path.join(out_dir, "shiny.gbapal"))
    shutil.copyfile(os.path.join(out_dir, "normal.gbapal.lz"), os.path.join(out_dir, "shiny.gbapal.lz"))

    fixture["assetSymbol"] = "ReservedSlot0"
    fixture["iconAssetSymbol"] = "QuestionMark"
    fixture["footprintAssetSymbol"] = "Bulbasaur"
    fixture["iconPaletteIndex"] = 0
    fixture["useCustomGeneratedSlot0Graphics"] = True
    return fixture


def write_reserved_pokedex_aux(n: int, banner: str) -> None:
    """Extra national dex pages + order-table tails so reserved species map to their own dex numbers."""
    if n <= 0:
        return

    comma_ndex = ",\n".join([f"    (NATIONAL_DEX_RESERVED_CUSTOM_FIRST + {i})" for i in range(n)])
    comma_ndex += ",\n"

    entries = []
    for i in range(n):
        height, weight = (7, 69) if i == 0 else (1, 1)
        entries.append(
            f"""    [(NATIONAL_DEX_RESERVED_CUSTOM_FIRST + {i})] =
    {{
        .categoryName = _("CUSTOM"),
        .height = {height},
        .weight = {weight},
        .description = gDummyPokedexText,
        .unusedDescription = gDummyPokedexTextUnused,
        .pokemonScale = 256,
        .pokemonOffset = 0,
        .trainerScale = 256,
        .trainerOffset = 0,
    }},
"""
        )
    write_if_changed(os.path.join(OUT_DIR, "reserved_pokedex_entries.inc"), banner + "".join(entries))

    type_lines = ",\n".join([f"    (SPECIES_CHIMECHO + 1 + {i})" for i in range(n)])
    type_lines += ",\n"

    write_if_changed(os.path.join(OUT_DIR, "reserved_pokedex_order_weight_append.inc"), comma_ndex)
    write_if_changed(os.path.join(OUT_DIR, "reserved_pokedex_order_height_append.inc"), comma_ndex)
    write_if_changed(os.path.join(OUT_DIR, "reserved_pokedex_order_alphabetical_append.inc"), comma_ndex)
    write_if_changed(os.path.join(OUT_DIR, "reserved_pokedex_order_type_append.inc"), type_lines)


def main() -> None:
    n = int(sys.argv[1]) if len(sys.argv) > 1 else int(os.environ.get("NUM_RESERVED_CUSTOM_SPECIES", "16"))
    if n < 0 or n > 64:
        print("count must be 0..64", file=sys.stderr)
        sys.exit(1)
    fixture = normalize_fixture(n)
    if fixture is None and os.environ.get("RESERVED_SPECIES_DEBUG_SLOT0") == "1" and n > 0:
        fixture = make_debug_slot0_fixture()
    fixture = materialize_slot0_fixture_assets(fixture)

    os.makedirs(OUT_DIR, exist_ok=True)

    banner = (
        "/* Auto-generated by tools/gen_reserved_species_tables.py — do not edit. */\n"
        f"/* NUM_RESERVED_CUSTOM_SPECIES = {n} */\n\n"
    )
    write_reserved_custom_graphics_inc(banner, bool(fixture and fixture.get("useCustomGeneratedSlot0Graphics")))

    # species_info.h
    body = "".join(species_info_entry(i, fixture) + "\n" for i in range(n))
    write_if_changed(os.path.join(OUT_DIR, "reserved_species_info.inc"), banner + body)

    # level_up_learnset_pointers.h
    lines = []
    for i in range(n):
        sid = species_id(i)
        if fixture and i == 0:
            lines.append(f"    [{sid}] = {fixture['learnsetSymbol']},\n")
        else:
            lines.append(f"    [{sid}] = sReservedSpeciesEmptyLearnset,\n")
    write_if_changed(os.path.join(OUT_DIR, "reserved_learnset_ptrs.inc"), banner + "".join(lines))

    # tmhm
    lines = [f"    [{species_id(i)}]    = TMHM_LEARNSET(0),\n" for i in range(n)]
    write_if_changed(os.path.join(OUT_DIR, "reserved_tmhm.inc"), banner + "".join(lines))

    # tutor
    lines = [f"    [{species_id(i)}] = 0,\n" for i in range(n)]
    write_if_changed(os.path.join(OUT_DIR, "reserved_tutor.inc"), banner + "".join(lines))

    # cry_ids.h — index is species - HOENN_MON_SPECIES_START (277)
    lines = []
    for i in range(n):
        sid = species_id(i)
        cry = fixture["cryId"] if fixture and i == 0 else "CRY_CHIMECHO"
        lines.append(f"    [{sid} - HOENN_MON_SPECIES_START] = {cry},\n")
    write_if_changed(os.path.join(OUT_DIR, "reserved_cry_ids.inc"), banner + "".join(lines))

    # graphics (manual designated initializers; not SPECIES_SPRITE macro)
    pic = []
    for i in range(n):
        sid = species_id(i)
        asset = fixture["assetSymbol"] if fixture and i == 0 else "CircledQuestionMark"
        pic.append(
            f"    [{sid}] = {{gMonFrontPic_{asset}, 0x800, {sid}}},\n"
        )
    write_if_changed(os.path.join(OUT_DIR, "reserved_front_pic.inc"), banner + "".join(pic))

    picb = []
    for i in range(n):
        sid = species_id(i)
        asset = fixture["assetSymbol"] if fixture and i == 0 else "CircledQuestionMark"
        picb.append(
            f"    [{sid}] = {{gMonBackPic_{asset}, 0x800, {sid}}},\n"
        )
    write_if_changed(os.path.join(OUT_DIR, "reserved_back_pic.inc"), banner + "".join(picb))

    pal = []
    for i in range(n):
        sid = species_id(i)
        asset = fixture["assetSymbol"] if fixture and i == 0 else "CircledQuestionMark"
        pal.append(f"    [{sid}] = {{gMonPalette_{asset}, {sid}}},\n")
    write_if_changed(os.path.join(OUT_DIR, "reserved_palette.inc"), banner + "".join(pal))

    sh = []
    for i in range(n):
        sid = species_id(i)
        asset = fixture["assetSymbol"] if fixture and i == 0 else "CircledQuestionMark"
        sh.append(
            f"    [{sid}] = {{gMonShinyPalette_{asset}, {sid} + SPECIES_SHINY_TAG}},\n"
        )
    write_if_changed(os.path.join(OUT_DIR, "reserved_shiny_palette.inc"), banner + "".join(sh))

    fp = []
    for i in range(n):
        sid = species_id(i)
        if fixture and i == 0:
            asset = fixture.get("footprintAssetSymbol", fixture["assetSymbol"])
        else:
            asset = "Bulbasaur"
        fp.append(f"    [{sid}] = gMonFootprint_{asset},\n")
    write_if_changed(os.path.join(OUT_DIR, "reserved_footprint.inc"), banner + "".join(fp))

    coord = """        .size = MON_COORDS_SIZE(32, 32),
        .y_offset = 16,
"""
    fc = []
    for i in range(n):
        sid = species_id(i)
        fc.append(f"    [{sid}] =\n    {{\n{coord}    }},\n")
    write_if_changed(os.path.join(OUT_DIR, "reserved_front_coords.inc"), banner + "".join(fc))

    write_if_changed(os.path.join(OUT_DIR, "reserved_back_coords.inc"), banner + "".join(fc))

    # species names — short distinct labels for debugging
    nm = []
    for i in range(n):
        sid = species_id(i)
        if fixture and i == 0:
            nm.append(f'    [{sid}] = _("{fixture["name"]}"),\n')
        else:
            nm.append(f'    [{sid}] = _("RSV{i:02d}"),\n')
    write_if_changed(os.path.join(OUT_DIR, "reserved_species_names.inc"), banner + "".join(nm))

    # icon table / icon palette index table
    icon = []
    icon_pal = []
    for i in range(n):
        sid = species_id(i)
        if fixture and i == 0:
            asset = fixture.get("iconAssetSymbol", fixture["assetSymbol"])
            icon.append(f"    [{sid}] = gMonIcon_{asset},\n")
            icon_pal.append(f"    [{sid}] = {fixture['iconPaletteIndex']},\n")
        else:
            icon.append(f"    [{sid}] = gMonIcon_QuestionMark,\n")
            icon_pal.append(f"    [{sid}] = 0,\n")
    write_if_changed(os.path.join(OUT_DIR, "reserved_icon_table.inc"), banner + "".join(icon))
    write_if_changed(os.path.join(OUT_DIR, "reserved_icon_palette_indices.inc"), banner + "".join(icon_pal))

    # pokemon.c dex tables (species-1 index)
    dex_h = []
    dex_n = []
    for i in range(n):
        sid = species_id(i)
        if fixture and i == 0:
            hd = fixture.get("hoennDex", "HOENN_DEX_NONE")
            nd = fixture.get("nationalDex", "NATIONAL_DEX_RESERVED_CUSTOM_FIRST")
        else:
            hd = "HOENN_DEX_NONE"
            nd = f"(NATIONAL_DEX_RESERVED_CUSTOM_FIRST + {i})"
        dex_h.append(f"    [{sid} - 1] = {hd},\n")
        dex_n.append(f"    [{sid} - 1] = {nd},\n")
    write_if_changed(os.path.join(OUT_DIR, "reserved_pokedex_hoenn.inc"), banner + "".join(dex_h))
    write_if_changed(os.path.join(OUT_DIR, "reserved_pokedex_national.inc"), banner + "".join(dex_n))

    write_reserved_pokedex_aux(n, banner)


if __name__ == "__main__":
    main()
