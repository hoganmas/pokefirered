#ifndef GUARD_RESERVED_SPECIES_CONFIG_H
#define GUARD_RESERVED_SPECIES_CONFIG_H

// Number of placeholder species IDs inserted after CHIMECHO and before EGG.
// Override at compile time: make NUM_RESERVED_CUSTOM_SPECIES=24
// Must match the value passed to tools/gen_reserved_species_tables.py (see Makefile).
#ifndef NUM_RESERVED_CUSTOM_SPECIES
#define NUM_RESERVED_CUSTOM_SPECIES 16
#endif

#if NUM_RESERVED_CUSTOM_SPECIES < 0 || NUM_RESERVED_CUSTOM_SPECIES > 64
#error "NUM_RESERVED_CUSTOM_SPECIES must be in [0, 64]"
#endif

#endif // GUARD_RESERVED_SPECIES_CONFIG_H
