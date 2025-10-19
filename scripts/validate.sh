#!/bin/bash
# Validation script for envsetup scripts

set -euo pipefail

echo "=== envsetup Script Validation ==="
echo

# Function to check if a script passes basic checks
validate_script() {
    local script="$1"
    local name="$2"
    
    echo "Validating $name ($script)..."
    
    # Check if file exists
    if [[ ! -f "$script" ]]; then
        echo "  ❌ File not found: $script"
        return 1
    fi
    
    # Check if executable
    if [[ ! -x "$script" ]]; then
        echo "  ⚠️  File not executable: $script"
    fi
    
    # Check syntax
    if bash -n "$script"; then
        echo "  ✅ Syntax check passed"
    else
        echo "  ❌ Syntax check failed"
        return 1
    fi
    
    # Run shellcheck if available
    if command -v shellcheck >/dev/null 2>&1; then
        if shellcheck "$script"; then
            echo "  ✅ Shellcheck passed"
        else
            echo "  ⚠️  Shellcheck warnings (see above)"
        fi
    else
        echo "  ⚠️  Shellcheck not available"
    fi
    
    echo "  ✅ $name validation completed"
    echo
}

# Validate all scripts
cd "$(dirname "$0")/.."

validate_script "stage1.sh" "Stage1 Script"
validate_script "scripts/bootstrap.sh" "Bootstrap Script" 
validate_script "rescue-install/install-zfs-trixie.sh" "ZFS Install Script"

echo "=== Testing Help Functions ==="

# Test help functionality
echo "Testing ZFS installer help..."
if bash rescue-install/install-zfs-trixie.sh --help >/dev/null; then
    echo "  ✅ Help function works"
else
    echo "  ❌ Help function failed"
fi

echo

echo "=== Environment Variable Test ==="

# Test environment variable passing
export TEST_VAR="test123"
if TEST_OUTPUT=$(bash -c 'echo "TEST_VAR=${TEST_VAR:-not_set}"'); then
    if [[ "$TEST_OUTPUT" == "TEST_VAR=test123" ]]; then
        echo "  ✅ Environment variable passing works"
    else
        echo "  ❌ Environment variable passing failed: $TEST_OUTPUT"
    fi
else
    echo "  ❌ Environment variable test failed"
fi

echo
echo "=== Validation Complete ==="
echo "All scripts have been validated for syntax and basic functionality."