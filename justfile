# Set variables
project_name := "pokefirered"
version      := "0.1.0"

# Set the shell (optional, default is zsh)
set shell := ["zsh", "-c"]

# List available commands by default
default:
    @just --list

print_pokemon_dumps:
    @grep -rnIli "Grimer" --include=\*.{h,c,s,inc,txt}
