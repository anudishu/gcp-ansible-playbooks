#!/bin/bash
# Node.js Runtime Validation Script
# Validates Node.js installation with version checks, npm functionality, and execution tests
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
validate_node_version() {
    log_step "Validating Node.js Installation"
    
    if ! command -v node >/dev/null 2>&1; then
        log_error "Node.js is not installed or not in PATH"
        return 1
    fi
    
    local node_version
    node_version=$(node --version 2>&1)
    log_success "Node.js found: $node_version"
    
    # Extract version number (e.g., "v18.17.0" -> "18.17.0")
    local version_num
    version_num=$(echo "$node_version" | sed 's/^v//' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
    
    if [[ -z "$version_num" ]]; then
        log_error "Could not extract Node.js version number from: $node_version"
        return 1
    fi
    
    # Check if version is 16 or higher (modern Node.js)
    local major_version
    major_version=$(echo "$version_num" | cut -d. -f1)
    
    if [[ $major_version -ge 16 ]]; then
        log_success "Node.js version $version_num meets recommended requirements (>= 16.x)"
    elif [[ $major_version -ge 14 ]]; then
        log_warning "Node.js version $version_num meets minimum requirements (>= 14.x) but upgrade recommended"
    else
        log_error "Node.js version $version_num is too old (requires >= 14.x, recommended >= 16.x)"
        return 1
    fi
    
    return 0
}

validate_npm_version() {
    log_step "Validating npm Installation"
    
    if ! command -v npm >/dev/null 2>&1; then
        log_error "npm is not installed or not in PATH"
        return 1
    fi
    
    local npm_version
    npm_version=$(npm --version 2>&1)
    log_success "npm found: v$npm_version"
    
    # Test npm functionality
    log_info "Testing npm configuration..."
    if npm config get registry >/dev/null 2>&1; then
        local registry
        registry=$(npm config get registry)
        log_success "npm is functional, registry: $registry"
    else
        log_error "npm is installed but configuration test failed"
        return 1
    fi
    
    # Test npm list functionality
    if npm list --depth=0 >/dev/null 2>&1; then
        log_success "npm can list packages"
    else
        log_warning "npm list command had issues (this may be normal in fresh installations)"
    fi
    
    return 0
}

validate_node_execution() {
    log_step "Testing Node.js JavaScript Execution"
    
    local test_dir="/tmp/node_validation_$$"
    mkdir -p "$test_dir"
    
    # Create test JavaScript file
    cat > "$test_dir/test.js" << 'EOF'
// Node.js Validation Test Script
console.log('Node.js validation test starting...');

// Test basic JavaScript features
console.log('Testing basic JavaScript features:');

// Variables and data types
const message = 'Hello from Node.js!';
const number = 42;
const array = [1, 2, 3, 4, 5];
const object = { name: 'test', value: 123 };

console.log('- String:', message);
console.log('- Number:', number);
console.log('- Array length:', array.length);
console.log('- Object property:', object.name);

// Test array methods
const sum = array.reduce((acc, val) => acc + val, 0);
console.log('- Array sum:', sum);

// Test modern JavaScript features (ES6+)
const doubled = array.map(x => x * 2);
console.log('- Doubled array:', doubled.join(', '));

// Test Promise support
const testPromise = new Promise((resolve) => {
    setTimeout(() => resolve('Promise resolved!'), 10);
});

testPromise.then(result => {
    console.log('- Promise test:', result);
    
    // Test Node.js built-in modules
    console.log('\nTesting Node.js built-in modules:');
    
    // Test os module
    const os = require('os');
    console.log('- OS platform:', os.platform());
    console.log('- OS architecture:', os.arch());
    console.log('- Total memory:', Math.round(os.totalmem() / 1024 / 1024 / 1024) + ' GB');
    
    // Test path module
    const path = require('path');
    const testPath = path.join('/tmp', 'test', 'file.txt');
    console.log('- Path join test:', testPath);
    console.log('- Path basename:', path.basename(testPath));
    
    // Test fs module (sync operations)
    const fs = require('fs');
    try {
        const tempFile = path.join(__dirname, 'temp_test.txt');
        fs.writeFileSync(tempFile, 'Test content');
        const content = fs.readFileSync(tempFile, 'utf8');
        fs.unlinkSync(tempFile);
        console.log('- File system test: PASSED (content length:', content.length + ')');
    } catch (error) {
        console.log('- File system test: FAILED -', error.message);
        process.exit(1);
    }
    
    // Test process module
    console.log('- Node.js version:', process.version);
    console.log('- Process PID:', process.pid);
    console.log('- Current working directory:', process.cwd());
    
    // Test Buffer
    const buffer = Buffer.from('Hello Buffer!', 'utf8');
    console.log('- Buffer test:', buffer.toString());
    
    console.log('\n✅ All Node.js validation tests PASSED!');
    console.log('Node.js runtime is working correctly.');
}).catch(error => {
    console.error('❌ Promise test failed:', error);
    process.exit(1);
});
EOF

    # Execute the test script
    log_info "Executing Node.js test script..."
    if node "$test_dir/test.js" > "$test_dir/output.txt" 2>&1; then
        log_success "Node.js script execution successful"
        
        # Verify output contains expected content
        if grep -q "All Node.js validation tests PASSED" "$test_dir/output.txt"; then
            log_success "Node.js execution validation passed"
            
            # Show key output for verification
            echo -e "\n${BLUE}Test Output (last 10 lines):${NC}"
            tail -10 "$test_dir/output.txt"
        else
            log_error "Node.js execution validation failed - expected output not found"
            echo -e "\n${RED}Actual Output:${NC}"
            cat "$test_dir/output.txt"
            rm -rf "$test_dir"
            return 1
        fi
    else
        log_error "Node.js script execution failed"
        echo -e "\n${RED}Error Output:${NC}"
        cat "$test_dir/output.txt"
        rm -rf "$test_dir"
        return 1
    fi
    
    # Clean up
    rm -rf "$test_dir"
    return 0
}

validate_npm_project_creation() {
    log_step "Testing npm Project Creation and Package Management"
    
    local test_dir="/tmp/npm_validation_$$"
    mkdir -p "$test_dir"
    cd "$test_dir"
    
    # Initialize npm project
    log_info "Creating test npm project..."
    if npm init -y >/dev/null 2>&1; then
        log_success "npm init successful"
        
        # Verify package.json was created
        if [[ -f "package.json" ]]; then
            log_success "package.json created"
            
            # Show package.json content
            log_info "Generated package.json:"
            cat package.json | head -15
        else
            log_error "package.json was not created"
            cd - >/dev/null
            rm -rf "$test_dir"
            return 1
        fi
    else
        log_error "npm init failed"
        cd - >/dev/null
        rm -rf "$test_dir"
        return 1
    fi
    
    # Test package installation (use a simple, commonly available package)
    log_info "Testing package installation with 'lodash'..."
    if npm install lodash --silent >/dev/null 2>&1; then
        log_success "npm install successful"
        
        # Verify node_modules was created
        if [[ -d "node_modules" && -d "node_modules/lodash" ]]; then
            log_success "node_modules and package files created"
        else
            log_error "node_modules directory structure is invalid"
            cd - >/dev/null
            rm -rf "$test_dir"
            return 1
        fi
        
        # Test requiring the installed package
        if node -e "const _ = require('lodash'); console.log('Lodash version:', _.VERSION || 'unknown'); console.log('Lodash test:', _.isArray([1,2,3]));" 2>/dev/null; then
            log_success "Installed package can be required and used"
        else
            log_error "Installed package cannot be required"
            cd - >/dev/null
            rm -rf "$test_dir"
            return 1
        fi
    else
        log_warning "npm install test failed (this may be expected in restricted networks)"
        log_info "Skipping package installation test"
    fi
    
    # Clean up
    cd - >/dev/null
    rm -rf "$test_dir"
    return 0
}

validate_node_modules_path() {
    log_step "Testing Node.js Module Resolution"
    
    # Test that Node.js can find built-in modules
    local builtin_modules=(
        "os"
        "path"
        "fs"
        "http"
        "url"
        "crypto"
        "util"
    )
    
    log_info "Testing built-in module resolution..."
    
    for module in "${builtin_modules[@]}"; do
        if node -e "require('$module'); console.log('✓ $module');" 2>/dev/null; then
            log_success "Built-in module accessible: $module"
        else
            log_error "Built-in module not accessible: $module"
            return 1
        fi
    done
    
    # Test module.paths
    log_info "Node.js module search paths:"
    node -e "console.log(module.paths.join('\n'));" | sed 's/^/  /'
    
    return 0
}

print_node_environment_info() {
    log_step "Node.js Environment Information"
    
    echo "Node.js Executable: $(which node 2>/dev/null || echo 'not found')"
    echo "npm Executable: $(which npm 2>/dev/null || echo 'not found')"
    
    if command -v node >/dev/null 2>&1; then
        echo "Node.js Version: $(node --version)"
        echo "Node.js Architecture: $(node -e 'console.log(process.arch)')"
        echo "Node.js Platform: $(node -e 'console.log(process.platform)')"
    fi
    
    if command -v npm >/dev/null 2>&1; then
        echo "npm Version: $(npm --version)"
        echo "npm Registry: $(npm config get registry 2>/dev/null || echo 'unknown')"
        echo "npm Global Path: $(npm config get prefix 2>/dev/null || echo 'unknown')"
    fi
    
    echo -e "\nNode.js Process Information:"
    node -e "
        console.log('  V8 Version:', process.versions.v8);
        console.log('  OpenSSL Version:', process.versions.openssl);
        console.log('  UV Version:', process.versions.uv);
        console.log('  Zlib Version:', process.versions.zlib);
    " 2>/dev/null || echo "  Could not retrieve process versions"
}

# Main validation function
main() {
    log_info "Starting Node.js Runtime Validation"
    log_info "Validation Strategy: Per-runtime validation (install → validate → next)"
    
    local exit_code=0
    
    # Print environment info first
    print_node_environment_info
    
    # Run all validation tests
    validate_node_version || exit_code=1
    validate_npm_version || exit_code=1
    validate_node_execution || exit_code=1
    validate_npm_project_creation || exit_code=1
    validate_node_modules_path || exit_code=1
    
    echo ""
    if [[ $exit_code -eq 0 ]]; then
        log_success "✅ Node.js runtime validation PASSED"
        log_info "Node.js and npm are properly installed and functional"
    else
        log_error "❌ Node.js runtime validation FAILED"
        log_error "One or more Node.js validation tests failed"
    fi
    
    return $exit_code
}

# Execute main function
main "$@"
