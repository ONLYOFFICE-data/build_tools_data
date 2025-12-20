#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARCHIVE="$SCRIPT_DIR/python3.tar.gz"
PYTHON_DIR="$SCRIPT_DIR/python3"
BIN_DIR="$PYTHON_DIR/bin"

echo "=== Setting up portable Python3 ==="

# Check if archive exists
if [ ! -f "$ARCHIVE" ]; then
    echo "ERROR: Archive not found: $ARCHIVE"
    exit 1
fi

# Remove existing directory
if [ -d "$PYTHON_DIR" ]; then
    echo "Removing existing $PYTHON_DIR..."
    rm -rf "$PYTHON_DIR"
fi

# Extract archive
echo "Extracting $ARCHIVE..."
tar -xzf "$ARCHIVE" -C "$SCRIPT_DIR"

# Check if bin directory exists
if [ ! -d "$BIN_DIR" ]; then
    echo "ERROR: bin directory not found: $BIN_DIR"
    exit 1
fi

# Fix shebangs in all files
echo "Fixing shebangs..."
FIXED_COUNT=0

for file in "$BIN_DIR"/*; do
    # Skip if not a file
    if [ ! -f "$file" ]; then
        continue
    fi
    
    # Check if file starts with #!/work/out/bin/python
    if head -n 1 "$file" 2>/dev/null | grep -q '^#!/work/out/bin/python'; then
        # Replace shebang
        FIRST_LINE=$(head -n 1 "$file")
        PYTHON_VERSION=$(echo "$FIRST_LINE" | sed 's|#!/work/out/bin/||')
        NEW_SHEBANG="#!$BIN_DIR/$PYTHON_VERSION"
        
        # Create temp file with new shebang
        echo "$NEW_SHEBANG" > "$file.tmp"
        tail -n +2 "$file" >> "$file.tmp"
        
        # Replace original file (force, no questions)
        mv -f "$file.tmp" "$file"
        chmod +x "$file"
        
        echo "  Fixed: $(basename $file)"
        FIXED_COUNT=$((FIXED_COUNT + 1))
    fi
done

echo "Fixed $FIXED_COUNT files"
echo ""
echo "=== Setup complete! ==="
echo "Python directory: $PYTHON_DIR"
echo "Python binary: $BIN_DIR/python3"
echo ""
echo "To use:"
echo "  export PATH=\"$BIN_DIR:\$PATH\""
echo "  python3 --version"
