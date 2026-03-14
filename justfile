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

# Run make and retry specifically on PNG signature errors
build-fix:
    @echo "Starting build with auto-retry for PNG errors..."
    @git restore graphics data
    @while ! make; do \
        echo "Restoring corrupted folders..."; \
        git restore graphics data; \
        if make 2>&1 | grep -q "Failed to read PNG signature"; then \
            echo "Detected PNG signature error. Retrying..."; \
            continue; \
        elif make 2>&1 | grep -q "Failed to open"; then \
            echo "Detected PNG open error. Retrying..."; \
            continue; \
        else \
            echo "Build failed with a different error. Stopping."; \
            exit 1; \
        fi; \
    done
    @echo "Build successful!"

install-dependencies:
    @sh install_dependencies.sh
