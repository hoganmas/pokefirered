-- Optional fixture for scripts/gen_reserved_species_tables.lua (slot 0 customization).
-- Return false from a file to disable: use enabled = false, or rename/remove this file.
return {
    enabled = true,
    name = "RSV386",
    learnsetSymbol = "sDeoxysLevelUpLearnset",
    cryId = "CRY_CHIMECHO",
    iconPaletteIndex = 0,
    pngPaths = {
        front = "../sprites/sprites/pokemon/versions/generation-iii/ruby-sapphire/381.png",
        back = "../sprites/sprites/pokemon/versions/generation-iii/ruby-sapphire/back/381.png",
    },
    speciesInfo = {
        baseHP = "50",
        baseAttack = "150",
        baseDefense = "50",
        baseSpeed = "150",
        baseSpAttack = "150",
        baseSpDefense = "50",
        types0 = "TYPE_PSYCHIC",
        types1 = "TYPE_PSYCHIC",
        growthRate = "GROWTH_SLOW",
    },
}
