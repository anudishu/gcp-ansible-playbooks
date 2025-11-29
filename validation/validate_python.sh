#!/bin/bash
# Python Runtime Validation Script
# Validates Python3 installation with version checks and smoke tests
# Exit Codes: 0 = Success, 1 = Failure

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "\n${BLUE}=== $1 ===${NC}"
}

# Validation functions
validate_python3_version() {
    log_step "Validating Python3 Installation"
    
    if ! command -v python3 >/dev/null 2>&1; then
        log_error "Python3 is not installed or not in PATH"
        return 1
    fi
    
    local python_version
    python_version=$(python3 --version 2>&1)
    log_success "Python3 found: $python_version"
    
    # Extract version number (e.g., "Python 3.8.10" -> "3.8.10")
    local version_num
    version_num=$(echo "$python_version" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    
    if [[ -z "$version_num" ]]; then
        log_error "Could not extract Python version number"
        return 1
    fi
    
    # Check if version is 3.6 or higher (minimum for RHEL 8/9)
    if python3 -c "import sys; exit(0 if sys.version_info >= (3, 6) else 1)"; then
        log_success "Python version $version_num meets minimum requirements (>= 3.6)"
    else
        log_error "Python version $version_num is too old (requires >= 3.6)"
        return 1
    fi
    
    return 0
}

validate_pip3_version() {
    log_step "Validating pip3 Installation"
    
    if ! command -v pip3 >/dev/null 2>&1; then
        log_error "pip3 is not installed or not in PATH"
        return 1
    fi
    
    local pip_version
    pip_version=$(pip3 --version 2>&1)
    log_success "pip3 found: $pip_version"
    
    # Test pip3 functionality
    if pip3 list >/dev/null 2>&1; then
        log_success "pip3 is functional and can list packages"
    else
        log_error "pip3 is installed but not functional"
        return 1
    fi
    
    return 0
}

validate_python_stdlib() {
    log_step "Testing Python Standard Library"
    
    local temp_script="/tmp/python_stdlib_test.py"
    
    # Create test script
    cat > "$temp_script" << 'EOF'
#!/usr/bin/env python3
"""
Python Standard Library Smoke Test
Tests core functionality that should be available in any Python installation
"""

import sys
import os
import json
import datetime
import subprocess
import tempfile

def test_basic_modules():
    """Test that essential standard library modules can be imported and used"""
    
    # Test sys module
    print(f"Python version: {sys.version}")
    print(f"Python executable: {sys.executable}")
    
    # Test os module
    print(f"Current working directory: {os.getcwd()}")
    print(f"Environment PATH exists: {'PATH' in os.environ}")
    
    # Test json module
    test_data = {"test": "data", "number": 42, "list": [1, 2, 3]}
    json_string = json.dumps(test_data)
    parsed_data = json.loads(json_string)
    assert parsed_data == test_data, "JSON serialization/deserialization failed"
    print("JSON module: Working")
    
    # Test datetime module
    now = datetime.datetime.now()
    iso_time = now.isoformat()
    print(f"Current datetime: {iso_time}")
    
    # Test tempfile module
    with tempfile.NamedTemporaryFile(mode='w', delete=False) as tmp:
        tmp.write("test content")
        tmp_path = tmp.name
    
    # Verify file was created and has content
    with open(tmp_path, 'r') as f:
        content = f.read()
        assert content == "test content", "Tempfile module failed"
    
    # Clean up
    os.unlink(tmp_path)
    print("Tempfile module: Working")
    
    print("All standard library tests passed!")
    return True

if __name__ == "__main__":
    try:
        test_basic_modules()
        print("SUCCESS: Python standard library validation completed")
        sys.exit(0)
    except Exception as e:
        print(f"ERROR: Python standard library test failed: {e}")
        sys.exit(1)
EOF

    # Make script executable
    chmod +x "$temp_script"
    
    # Run the test script
    if python3 "$temp_script"; then
        log_success "Python standard library smoke test passed"
        rm -f "$temp_script"
        return 0
    else
        log_error "Python standard library smoke test failed"
        rm -f "$temp_script"
        return 1
    fi
}

validate_python_package_install() {
    log_step "Testing Python Package Installation"
    
    # Test if we can install a simple package (using --user to avoid permission issues)
    log_info "Testing pip install functionality with 'requests' package"
    
    # Check if requests is already installed
    if pip3 show requests >/dev/null 2>&1; then
        log_info "requests package already installed, testing import"
        if python3 -c "import requests; print(f'requests version: {requests.__version__}')"; then
            log_success "requests package import test passed"
            return 0
        else
            log_error "requests package import test failed"
            return 1
        fi
    else
        # Try to install requests package
        log_info "Installing requests package for validation"
        if pip3 install --user requests >/dev/null 2>&1; then
            log_success "Successfully installed requests package"
            
            # Test import
            if python3 -c "import requests; print(f'requests version: {requests.__version__}')"; then
                log_success "requests package import test passed"
                return 0
            else
                log_error "requests package import test failed after installation"
                return 1
            fi
        else
            log_warning "Could not install requests package (this may be expected in restricted environments)"
            log_info "Skipping package installation test"
            return 0
        fi
    fi
}

print_python_environment_info() {
    log_step "Python Environment Information"
    
    echo "Python Executable: $(which python3)"
    echo "Python Version: $(python3 --version)"
    echo "pip3 Executable: $(which pip3 2>/dev/null || echo 'not found')"
    echo "pip3 Version: $(pip3 --version 2>/dev/null || echo 'not available')"
    
    echo -e "\nPython sys.path:"
    python3 -c "import sys; [print(f'  {p}') for p in sys.path if p]"
    
    echo -e "\nInstalled pip packages (first 10):"
    pip3 list 2>/dev/null | head -10 || echo "Could not list packages"
}

# Main validation function
main() {
    log_info "Starting Python Runtime Validation"
    log_info "Validation Strategy: Per-runtime validation (install → validate → next)"
    
    local exit_code=0
    
    # Print environment info first
    print_python_environment_info
    
    # Run all validation tests
    validate_python3_version || exit_code=1
    validate_pip3_version || exit_code=1
    validate_python_stdlib || exit_code=1
    validate_python_package_install || exit_code=1
    
    echo ""
    if [[ $exit_code -eq 0 ]]; then
        log_success "✅ Python runtime validation PASSED"
        log_info "Python is properly installed and functional"
    else
        log_error "❌ Python runtime validation FAILED"
        log_error "One or more Python validation tests failed"
    fi
    
    return $exit_code
}

# Execute main function
main "$@"
