#!/bin/bash
# Java SDK Validation Script
# Validates Java JDK installation with version checks, compilation, and execution tests
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
validate_java_runtime() {
    log_step "Validating Java Runtime (JRE)"
    
    if ! command -v java >/dev/null 2>&1; then
        log_error "Java runtime (java) is not installed or not in PATH"
        return 1
    fi
    
    local java_version
    java_version=$(java -version 2>&1 | head -1)
    log_success "Java runtime found: $java_version"
    
    # Extract version number (handle different output formats)
    local version_num
    if echo "$java_version" | grep -q "openjdk version"; then
        version_num=$(echo "$java_version" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+(_[0-9]+)?' | head -1)
    else
        version_num=$(echo "$java_version" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+(_[0-9]+)?' | head -1)
    fi
    
    if [[ -z "$version_num" ]]; then
        # Try alternative format (Java 11+)
        version_num=$(echo "$java_version" | grep -oE '"[0-9]+(\.0\..*?)"' | tr -d '"' | head -1)
        if [[ -z "$version_num" ]]; then
            log_warning "Could not extract Java version number from: $java_version"
        fi
    fi
    
    log_success "Java runtime version: $version_num"
    return 0
}

validate_java_compiler() {
    log_step "Validating Java Compiler (JDK)"
    
    if ! command -v javac >/dev/null 2>&1; then
        log_error "Java compiler (javac) is not installed or not in PATH"
        log_error "This indicates JDK is not installed (only JRE may be present)"
        return 1
    fi
    
    local javac_version
    javac_version=$(javac -version 2>&1)
    log_success "Java compiler found: $javac_version"
    
    # Check that java and javac versions match
    local java_ver javac_ver
    java_ver=$(java -version 2>&1 | head -1 | grep -oE '[0-9]+(\.[0-9]+)*' | head -1)
    javac_ver=$(javac -version 2>&1 | grep -oE '[0-9]+(\.[0-9]+)*' | head -1)
    
    if [[ "$java_ver" == "$javac_ver" ]]; then
        log_success "Java runtime and compiler versions match: $java_ver"
    else
        log_warning "Java runtime ($java_ver) and compiler ($javac_ver) versions differ"
    fi
    
    return 0
}

validate_java_home() {
    log_step "Validating JAVA_HOME Environment"
    
    if [[ -z "${JAVA_HOME:-}" ]]; then
        log_warning "JAVA_HOME environment variable is not set"
        
        # Try to detect JAVA_HOME
        local java_path
        java_path=$(which java)
        
        if [[ -L "$java_path" ]]; then
            java_path=$(readlink -f "$java_path")
        fi
        
        # Remove /bin/java to get potential JAVA_HOME
        local potential_java_home
        potential_java_home=$(dirname "$(dirname "$java_path")")
        
        if [[ -d "$potential_java_home" && -d "$potential_java_home/lib" ]]; then
            log_info "Detected potential JAVA_HOME: $potential_java_home"
            export JAVA_HOME="$potential_java_home"
            log_warning "Temporarily set JAVA_HOME for validation"
        else
            log_error "Could not determine JAVA_HOME automatically"
            return 1
        fi
    else
        log_success "JAVA_HOME is set: $JAVA_HOME"
        
        # Validate JAVA_HOME path exists
        if [[ ! -d "$JAVA_HOME" ]]; then
            log_error "JAVA_HOME directory does not exist: $JAVA_HOME"
            return 1
        fi
        
        # Check for expected JDK structure
        if [[ -d "$JAVA_HOME/bin" && -d "$JAVA_HOME/lib" ]]; then
            log_success "JAVA_HOME directory structure is valid"
        else
            log_error "JAVA_HOME directory structure is invalid (missing bin/ or lib/)"
            return 1
        fi
    fi
    
    # Test that JAVA_HOME/bin/java works
    if [[ -x "$JAVA_HOME/bin/java" ]]; then
        local java_home_version
        java_home_version=$("$JAVA_HOME/bin/java" -version 2>&1 | head -1)
        log_success "JAVA_HOME/bin/java is executable: $java_home_version"
    else
        log_error "JAVA_HOME/bin/java is not executable or missing"
        return 1
    fi
    
    return 0
}

validate_java_compilation() {
    log_step "Testing Java Compilation and Execution"
    
    local test_dir="/tmp/java_validation_$$"
    mkdir -p "$test_dir"
    
    # Create HelloWorld.java
    cat > "$test_dir/HelloWorld.java" << 'EOF'
public class HelloWorld {
    public static void main(String[] args) {
        System.out.println("Hello, World!");
        System.out.println("Java validation test successful!");
        
        // Test basic Java features
        String message = "Java SDK is working correctly";
        System.out.println("Message: " + message);
        
        // Test basic data structures
        java.util.List<String> list = new java.util.ArrayList<>();
        list.add("Item1");
        list.add("Item2");
        System.out.println("List size: " + list.size());
        
        // Test basic math
        int result = 5 + 3;
        System.out.println("5 + 3 = " + result);
        
        // Test system properties
        System.out.println("Java version: " + System.getProperty("java.version"));
        System.out.println("Java vendor: " + System.getProperty("java.vendor"));
        System.out.println("OS name: " + System.getProperty("os.name"));
    }
}
EOF

    # Compile the Java file
    log_info "Compiling HelloWorld.java..."
    if javac -d "$test_dir" "$test_dir/HelloWorld.java" 2>/dev/null; then
        log_success "Java compilation successful"
    else
        log_error "Java compilation failed"
        rm -rf "$test_dir"
        return 1
    fi
    
    # Check that .class file was created
    if [[ -f "$test_dir/HelloWorld.class" ]]; then
        log_success "HelloWorld.class file generated"
    else
        log_error "HelloWorld.class file not found after compilation"
        rm -rf "$test_dir"
        return 1
    fi
    
    # Execute the compiled Java program
    log_info "Executing compiled Java program..."
    if java -cp "$test_dir" HelloWorld > "$test_dir/output.txt" 2>&1; then
        log_success "Java program execution successful"
        
        # Verify output contains expected content
        if grep -q "Hello, World!" "$test_dir/output.txt" && 
           grep -q "Java validation test successful!" "$test_dir/output.txt"; then
            log_success "Java program output validation passed"
            
            # Show some output for verification
            echo -e "\n${BLUE}Program Output:${NC}"
            cat "$test_dir/output.txt" | head -10
        else
            log_error "Java program output validation failed"
            echo -e "\n${RED}Actual Output:${NC}"
            cat "$test_dir/output.txt"
            rm -rf "$test_dir"
            return 1
        fi
    else
        log_error "Java program execution failed"
        echo -e "\n${RED}Error Output:${NC}"
        cat "$test_dir/output.txt"
        rm -rf "$test_dir"
        return 1
    fi
    
    # Clean up
    rm -rf "$test_dir"
    return 0
}

validate_java_classpath() {
    log_step "Testing Java Classpath and Core Libraries"
    
    # Test that core Java libraries are accessible
    log_info "Testing core Java library access..."
    
    local test_classes=(
        "java.lang.String"
        "java.util.ArrayList"
        "java.util.HashMap"
        "java.io.File"
        "java.net.URL"
    )
    
    for class_name in "${test_classes[@]}"; do
        if java -cp /dev/null -XX:+UnlockDiagnosticVMOptions -XX:+LogVMOutput \
               -XX:+TraceClassLoading "$class_name" 2>/dev/null >/dev/null; then
            log_success "Core class accessible: $class_name"
        else
            # Alternative test - create simple program that uses the class
            if java -c "Class.forName(\"$class_name\"); System.out.println(\"$class_name loaded\")" 2>/dev/null; then
                log_success "Core class accessible: $class_name"
            else
                log_warning "Could not verify core class: $class_name"
            fi
        fi
    done
    
    return 0
}

print_java_environment_info() {
    log_step "Java Environment Information"
    
    echo "Java Executable: $(which java 2>/dev/null || echo 'not found')"
    echo "Java Compiler: $(which javac 2>/dev/null || echo 'not found')"
    echo "JAVA_HOME: ${JAVA_HOME:-'not set'}"
    
    if command -v java >/dev/null 2>&1; then
        echo -e "\nJava Version Details:"
        java -version 2>&1 | sed 's/^/  /'
    fi
    
    if command -v javac >/dev/null 2>&1; then
        echo -e "\nJava Compiler Version:"
        javac -version 2>&1 | sed 's/^/  /'
    fi
    
    echo -e "\nJava System Properties (key ones):"
    java -XshowSettings:properties -version 2>&1 | grep -E "(java\.version|java\.vendor|java\.home|os\.name|os\.arch)" | sed 's/^/  /' || echo "  Could not retrieve system properties"
}

# Main validation function
main() {
    log_info "Starting Java SDK Validation"
    log_info "Validation Strategy: Per-runtime validation (install → validate → next)"
    
    local exit_code=0
    
    # Print environment info first
    print_java_environment_info
    
    # Run all validation tests
    validate_java_runtime || exit_code=1
    validate_java_compiler || exit_code=1
    validate_java_home || exit_code=1
    validate_java_compilation || exit_code=1
    validate_java_classpath || exit_code=1
    
    echo ""
    if [[ $exit_code -eq 0 ]]; then
        log_success "✅ Java SDK validation PASSED"
        log_info "Java JDK is properly installed and functional"
    else
        log_error "❌ Java SDK validation FAILED"
        log_error "One or more Java validation tests failed"
    fi
    
    return $exit_code
}

# Execute main function
main "$@"
