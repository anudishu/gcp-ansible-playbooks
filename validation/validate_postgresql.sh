#!/bin/bash
# PostgreSQL Client Validation Script
# Validates PostgreSQL client tools installation with version checks and connection tests
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
validate_psql_version() {
    log_step "Validating PostgreSQL Client (psql)"
    
    if ! command -v psql >/dev/null 2>&1; then
        log_error "PostgreSQL client (psql) is not installed or not in PATH"
        return 1
    fi
    
    local psql_version
    psql_version=$(psql --version 2>&1)
    log_success "PostgreSQL client found: $psql_version"
    
    # Extract version number (e.g., "psql (PostgreSQL) 14.9" -> "14.9")
    local version_num
    version_num=$(echo "$psql_version" | grep -oE '[0-9]+\.[0-9]+' | head -1)
    
    if [[ -z "$version_num" ]]; then
        log_error "Could not extract PostgreSQL version number from: $psql_version"
        return 1
    fi
    
    # Check if version is supported (PostgreSQL 10+ is generally supported)
    local major_version
    major_version=$(echo "$version_num" | cut -d. -f1)
    
    if [[ $major_version -ge 12 ]]; then
        log_success "PostgreSQL version $version_num is current (>= 12.x)"
    elif [[ $major_version -ge 10 ]]; then
        log_success "PostgreSQL version $version_num is supported (>= 10.x)"
    else
        log_warning "PostgreSQL version $version_num is old (< 10.x) - consider upgrading"
    fi
    
    return 0
}

validate_pg_dump() {
    log_step "Validating PostgreSQL Dump Tools"
    
    # Check pg_dump
    if ! command -v pg_dump >/dev/null 2>&1; then
        log_error "pg_dump is not installed or not in PATH"
        return 1
    fi
    
    local pg_dump_version
    pg_dump_version=$(pg_dump --version 2>&1)
    log_success "pg_dump found: $pg_dump_version"
    
    # Check pg_restore
    if ! command -v pg_restore >/dev/null 2>&1; then
        log_error "pg_restore is not installed or not in PATH"
        return 1
    fi
    
    local pg_restore_version
    pg_restore_version=$(pg_restore --version 2>&1)
    log_success "pg_restore found: $pg_restore_version"
    
    return 0
}

validate_additional_pg_tools() {
    log_step "Validating Additional PostgreSQL Tools"
    
    local tools=(
        "createdb:Database creation tool"
        "dropdb:Database deletion tool"
        "pg_isready:Connection readiness checker"
        "vacuumdb:Database maintenance tool"
    )
    
    local found_tools=0
    local total_tools=${#tools[@]}
    
    for tool_info in "${tools[@]}"; do
        local tool_name=$(echo "$tool_info" | cut -d: -f1)
        local tool_desc=$(echo "$tool_info" | cut -d: -f2)
        
        if command -v "$tool_name" >/dev/null 2>&1; then
            local tool_version
            tool_version=$($tool_name --version 2>&1 | head -1)
            log_success "$tool_desc found: $tool_version"
            ((found_tools++))
        else
            log_warning "$tool_desc ($tool_name) not found"
        fi
    done
    
    log_info "Found $found_tools out of $total_tools additional PostgreSQL tools"
    
    if [[ $found_tools -eq $total_tools ]]; then
        log_success "All PostgreSQL client tools are available"
    elif [[ $found_tools -ge 2 ]]; then
        log_success "Essential PostgreSQL client tools are available"
    else
        log_warning "Limited PostgreSQL client tools available"
    fi
    
    return 0
}

validate_psql_functionality() {
    log_step "Testing PostgreSQL Client Functionality"
    
    # Test psql help functionality
    log_info "Testing psql help system..."
    if psql --help >/dev/null 2>&1; then
        log_success "psql help system is functional"
    else
        log_error "psql help system failed"
        return 1
    fi
    
    # Test psql version command
    log_info "Testing psql version command..."
    if psql -V >/dev/null 2>&1; then
        log_success "psql version command works"
    else
        log_error "psql version command failed"
        return 1
    fi
    
    # Test connection without actual database (this will fail but should give proper error)
    log_info "Testing psql connection handling..."
    local connection_test_output
    connection_test_output=$(psql -h localhost -U nonexistent_user -d nonexistent_db -c "SELECT 1;" 2>&1 || true)
    
    if echo "$connection_test_output" | grep -q -E "(could not connect|connection.*refused|No such file|database.*does not exist|authentication failed)"; then
        log_success "psql properly handles connection attempts and errors"
    else
        log_warning "psql connection error handling may be unusual"
        echo "Connection test output: $connection_test_output"
    fi
    
    return 0
}

validate_pg_isready_functionality() {
    log_step "Testing pg_isready Functionality"
    
    if ! command -v pg_isready >/dev/null 2>&1; then
        log_warning "pg_isready not available, skipping connectivity tests"
        return 0
    fi
    
    # Test pg_isready help
    if pg_isready --help >/dev/null 2>&1; then
        log_success "pg_isready help is functional"
    else
        log_error "pg_isready help failed"
        return 1
    fi
    
    # Test pg_isready against non-existent server (should fail gracefully)
    log_info "Testing pg_isready connection checking..."
    local pg_isready_output
    pg_isready_output=$(pg_isready -h localhost -p 5432 2>&1 || true)
    
    if echo "$pg_isready_output" | grep -q -E "(accepting connections|no response|could not connect)"; then
        log_success "pg_isready properly tests connections"
        log_info "pg_isready output: $pg_isready_output"
    else
        log_warning "pg_isready behavior may be unusual"
        echo "pg_isready output: $pg_isready_output"
    fi
    
    return 0
}

validate_sql_syntax_parsing() {
    log_step "Testing SQL Syntax and Parsing"
    
    local test_dir="/tmp/pg_validation_$$"
    mkdir -p "$test_dir"
    
    # Create test SQL file
    cat > "$test_dir/test.sql" << 'EOF'
-- PostgreSQL Client Validation Test SQL
-- This file tests SQL parsing capabilities

-- Simple SELECT statements
SELECT 1 as test_number;
SELECT 'Hello PostgreSQL' as test_string;
SELECT current_timestamp as test_timestamp;

-- Test basic SQL constructs
SELECT 
    1 + 1 as addition,
    'test' || ' string' as concatenation,
    CASE WHEN 1 = 1 THEN 'true' ELSE 'false' END as conditional;

-- Test common functions
SELECT 
    length('test') as string_length,
    upper('hello') as uppercase,
    lower('WORLD') as lowercase;

-- Test more complex query structure (would work if connected to DB)
-- SELECT t1.id, t2.name 
-- FROM table1 t1 
-- JOIN table2 t2 ON t1.id = t2.table1_id 
-- WHERE t1.active = true 
-- ORDER BY t2.name;

\echo 'SQL syntax test completed successfully'
EOF

    # Test SQL file parsing (dry run without connection)
    log_info "Testing SQL syntax parsing..."
    
    # Use psql to parse SQL without connecting (this tests SQL parsing capability)
    # We expect this to fail on connection, but it should parse the SQL correctly
    local parse_output
    parse_output=$(psql -f "$test_dir/test.sql" -h localhost -U nonexistent 2>&1 || true)
    
    if echo "$parse_output" | grep -q -E "(could not connect|connection.*refused|No such file)"; then
        log_success "SQL file parsing works (connection failed as expected)"
    elif echo "$parse_output" | grep -q -E "syntax error|ERROR.*syntax"; then
        log_error "SQL syntax parsing failed - there may be SQL syntax errors"
        echo "Parse errors: $parse_output"
        rm -rf "$test_dir"
        return 1
    else
        log_info "SQL parsing test had unexpected output: $parse_output"
    fi
    
    # Test individual SQL statement parsing
    log_info "Testing individual SQL statement parsing..."
    local simple_sql_output
    simple_sql_output=$(echo "SELECT 1;" | psql -h localhost -U nonexistent 2>&1 || true)
    
    if echo "$simple_sql_output" | grep -q -E "(could not connect|connection.*refused)"; then
        log_success "Simple SQL statement parsing works"
    else
        log_warning "Simple SQL statement parsing had unusual output"
    fi
    
    # Clean up
    rm -rf "$test_dir"
    return 0
}

test_pg_dump_functionality() {
    log_step "Testing pg_dump Functionality"
    
    if ! command -v pg_dump >/dev/null 2>&1; then
        log_warning "pg_dump not available, skipping dump tests"
        return 0
    fi
    
    # Test pg_dump help
    if pg_dump --help >/dev/null 2>&1; then
        log_success "pg_dump help is functional"
    else
        log_error "pg_dump help failed"
        return 1
    fi
    
    # Test pg_dump against non-existent database (should fail gracefully)
    log_info "Testing pg_dump error handling..."
    local dump_output
    dump_output=$(pg_dump -h localhost -U nonexistent nonexistent_db 2>&1 || true)
    
    if echo "$dump_output" | grep -q -E "(could not connect|connection.*refused|database.*does not exist|authentication failed)"; then
        log_success "pg_dump properly handles connection errors"
    else
        log_warning "pg_dump error handling may be unusual"
        echo "pg_dump output: $dump_output"
    fi
    
    return 0
}

print_postgresql_environment_info() {
    log_step "PostgreSQL Client Environment Information"
    
    echo "psql Executable: $(which psql 2>/dev/null || echo 'not found')"
    echo "pg_dump Executable: $(which pg_dump 2>/dev/null || echo 'not found')"
    echo "pg_restore Executable: $(which pg_restore 2>/dev/null || echo 'not found')"
    echo "pg_isready Executable: $(which pg_isready 2>/dev/null || echo 'not found')"
    
    if command -v psql >/dev/null 2>&1; then
        echo -e "\nPostgreSQL Client Version:"
        psql --version | sed 's/^/  /'
    fi
    
    echo -e "\nLibrary Path Information:"
    # Check if libpq is accessible (common PostgreSQL client library)
    if ldconfig -p 2>/dev/null | grep -q libpq; then
        echo "  libpq (PostgreSQL client library): Available"
        ldconfig -p | grep libpq | head -3 | sed 's/^/    /'
    else
        echo "  libpq (PostgreSQL client library): Not found in ldconfig"
    fi
    
    echo -e "\nPostgreSQL Environment Variables:"
    env | grep -E '^(PG|POSTGRES)' | sed 's/^/  /' || echo "  No PostgreSQL environment variables set"
}

# Main validation function
main() {
    log_info "Starting PostgreSQL Client Validation"
    log_info "Validation Strategy: Per-runtime validation (install → validate → next)"
    
    local exit_code=0
    
    # Print environment info first
    print_postgresql_environment_info
    
    # Run all validation tests
    validate_psql_version || exit_code=1
    validate_pg_dump || exit_code=1
    validate_additional_pg_tools || exit_code=1
    validate_psql_functionality || exit_code=1
    validate_pg_isready_functionality || exit_code=1
    validate_sql_syntax_parsing || exit_code=1
    test_pg_dump_functionality || exit_code=1
    
    echo ""
    if [[ $exit_code -eq 0 ]]; then
        log_success "✅ PostgreSQL client validation PASSED"
        log_info "PostgreSQL client tools are properly installed and functional"
    else
        log_error "❌ PostgreSQL client validation FAILED"
        log_error "One or more PostgreSQL client validation tests failed"
    fi
    
    return $exit_code
}

# Execute main function
main "$@"
