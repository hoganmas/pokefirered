-- Optional fixture for scripts/gen_reserved_species_tables.lua (slot 0 customization).
-- Return false from a file to disable: use enabled = false, or rename/remove this file.
return {
    enabled = true,
    name = "NEXOMON",
    learnsetSymbol = "sDeoxysLevelUpLearnset",
    cryId = "CRY_CHIMECHO",
    iconPaletteIndex = 0,
    pngPaths = {
        front = "../sprites/sprites/pokemon/versions/generation-iii/ruby-sapphire/381.png",
        back = "../sprites/sprites/pokemon/versions/generation-iii/ruby-sapphire/back/381.png",
        icon = "graphics/pokemon/smeargle/icon.png",
        footprint = "graphics/pokemon/kabutops/footprint.png",
    },
    -- Optional custom slot-0 Pokedex entry fields.
    pokedexEntry = {
        categoryName = "FOSSIL",
        height = 7,
        weight = 69,
        descriptionText = "A synthetic MON from fossil data.\\nIt adapts to shifting climates\\nand nests near ancient craters.",
        unusedDescriptionText = "",
        pokemonScale = 256,
        pokemonOffset = 0,
        trainerScale = 256,
        trainerOffset = 0,
    },
    speciesInfo = {
        baseHP = "50",
        baseAttack = "150",
        baseDefense = "50",
        baseSpeed = "150",
        baseSpAttack = "150",
        baseSpDefense = "50",
        types0 = "TYPE_PSYCHIC",
        types1 = "TYPE_STEEL",
        growthRate = "GROWTH_SLOW",
    },
    levelUpMoves = {
        { level = 1, move = "MOVE_TACKLE" },
        { level = 7, move = "MOVE_WATER_GUN" },
        { level = 14, move = "MOVE_BITE" },
        { level = 21, move = "MOVE_ANCIENT_POWER" },
    },
}
