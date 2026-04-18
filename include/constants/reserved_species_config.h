#ifndef GUARD_RESERVED_SPECIES_CONFIG_H
#define GUARD_RESERVED_SPECIES_CONFIG_H

// Number of placeholder species IDs inserted after CHIMECHO and before EGG.
// Override at compile time: make NUM_RESERVED_CUSTOM_SPECIES=24
// Must match the value passed to scripts/gen_reserved_species_tables.lua (see Makefile).
#ifndef NUM_RESERVED_CUSTOM_SPECIES
#define NUM_RESERVED_CUSTOM_SPECIES 16
#endif

#if NUM_RESERVED_CUSTOM_SPECIES < 0 || NUM_RESERVED_CUSTOM_SPECIES > 64
#error "NUM_RESERVED_CUSTOM_SPECIES must be in [0, 64]"
#endif

// In-game test: build with -DDEBUG_GIVE_RESERVED_SPECIES_NEWGAME (see Makefile).
// After Oak’s intro, the first reserved species (SPECIES_CHIMECHO + 1) is added to the party.
// The scripting mailbox is filled at boot — mGBA Lua can run ReservedSpeciesMailbox.attach() from the
// title screen without clearing intro.
//
// When DEBUG_GIVE_RESERVED_SPECIES_NEWGAME=1, `make` also regenerates reserved tables so slot 0
// mirrors Bulbasaur graphics/learnset and uses its own national dex number (NATIONAL_DEX_RESERVED_CUSTOM_FIRST,
// after Old Unown placeholders). See scripts/gen_reserved_species_tables.lua and include/constants/pokedex.h.

#endif // GUARD_RESERVED_SPECIES_CONFIG_H
