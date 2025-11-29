# Runtime Validation System

A comprehensive validation system for testing runtime installations in golden images using **per-runtime validation strategy** for immediate failure detection and root cause isolation.

## 🎯 Overview

This validation system implements a **per-runtime validation strategy** that validates each runtime package individually after installation:

```
Install Python → Validate Python → Install Java → Validate Java → Install Node.js → Validate Node.js → Install PostgreSQL → Validate PostgreSQL
```

### Strategy Benefits

✅ **Immediate Failure Detection** - Catches which package breaks things immediately  
✅ **Faster Root Cause Analysis** - Identifies problematic packages quickly  
✅ **Isolated Testing** - Each runtime validated independently  
✅ **Clear Error Attribution** - No cascading failure confusion  

### Strategy Trade-offs

⚠️ **Slightly Longer Playbook Logic** - More validation steps  
⚠️ **Multiple Validation Points** - More complex than global validation  

---

## 📁 Directory Structure

```
validation/
├── 📄 README.md              # This documentation
├── 🐍 validate_python.sh     # Python runtime validation
├── ☕ validate_java.sh       # Java SDK validation
├── 🟢 validate_node.sh       # Node.js runtime validation
├── 🐘 validate_postgresql.sh # PostgreSQL client validation
├── 📋 validate.yml           # Ansible validation playbook
└── 🚀 validate_all.sh        # Master validation runner
```

---

## 🚀 Quick Start

### 1. Run All Validations (Recommended)

```bash
# Run complete validation suite
cd validation/
./validate_all.sh

# Run with verbose output
./validate_all.sh --verbose

# Continue validation even after failures
./validate_all.sh --continue
```

### 2. Run Individual Runtime Validations

```bash
# Validate specific runtime only
./validate_all.sh --runtime python
./validate_all.sh --runtime java
./validate_all.sh --runtime node
./validate_all.sh --runtime postgresql

# Run individual scripts directly
./validate_python.sh
./validate_java.sh
./validate_node.sh
./validate_postgresql.sh
```

### 3. Run Ansible Validation Playbook

```bash
# From the main ansible directory
ansible-playbook -i hosts.runtime.yml validation/validate.yml

# With specific tags
ansible-playbook -i hosts.runtime.yml validation/validate.yml --tags python,java

# With extra variables
ansible-playbook -i hosts.runtime.yml validation/validate.yml -e cleanup_validation_temp=false
```

---

## 🔧 Validation Details

### 🐍 Python Runtime Validation

**Script:** `validate_python.sh`

**Tests Performed:**
- ✅ Python3 version check (`python3 --version`)
- ✅ pip3 version check (`pip3 --version`)
- ✅ Standard library import test
- ✅ Simple script execution
- ✅ Package installation capability
- ✅ Environment path verification

**Requirements:**
- Python 3.6+ (RHEL 8/9 compatible)
- pip3 functional
- Standard library accessible

**Example Output:**
```
[INFO] Starting Python Runtime Validation
=== Validating Python3 Installation ===
[SUCCESS] Python3 found: Python 3.9.16
[SUCCESS] Python version 3.9.16 meets minimum requirements (>= 3.6)
=== Testing Python Standard Library ===
[SUCCESS] Python standard library smoke test passed
✅ Python runtime validation PASSED
```

### ☕ Java SDK Validation

**Script:** `validate_java.sh`

**Tests Performed:**
- ✅ Java runtime version check (`java -version`)
- ✅ Java compiler check (`javac -version`)
- ✅ JAVA_HOME validation
- ✅ HelloWorld.java compilation test
- ✅ Java program execution test
- ✅ Core library accessibility test

**Requirements:**
- Java JDK (not just JRE)
- JAVA_HOME properly set
- javac compiler available

**Example Output:**
```
[INFO] Starting Java SDK Validation
=== Validating Java Runtime (JRE) ===
[SUCCESS] Java runtime found: openjdk version "11.0.19"
=== Testing Java Compilation and Execution ===
[SUCCESS] Java compilation successful
[SUCCESS] Java program execution successful
✅ Java SDK validation PASSED
```

### 🟢 Node.js Runtime Validation

**Script:** `validate_node.sh`

**Tests Performed:**
- ✅ Node.js version check (`node --version`)
- ✅ npm version check (`npm --version`)
- ✅ JavaScript execution test
- ✅ Built-in modules test (os, fs, path, etc.)
- ✅ npm project creation test
- ✅ Package installation test

**Requirements:**
- Node.js 14+ (16+ recommended)
- npm functional
- Module resolution working

**Example Output:**
```
[INFO] Starting Node.js Runtime Validation
=== Validating Node.js Installation ===
[SUCCESS] Node.js found: v18.17.0
[SUCCESS] Node.js version 18.17.0 meets recommended requirements (>= 16.x)
=== Testing Node.js JavaScript Execution ===
[SUCCESS] Node.js script execution successful
✅ Node.js runtime validation PASSED
```

### 🐘 PostgreSQL Client Validation

**Script:** `validate_postgresql.sh`

**Tests Performed:**
- ✅ psql version check (`psql --version`)
- ✅ pg_dump availability check
- ✅ Additional tools check (pg_restore, createdb, etc.)
- ✅ Connection handling test
- ✅ SQL syntax parsing test
- ✅ Client functionality verification

**Requirements:**
- PostgreSQL client tools installed
- psql executable in PATH
- Basic SQL parsing capability

**Example Output:**
```
[INFO] Starting PostgreSQL Client Validation
=== Validating PostgreSQL Client (psql) ===
[SUCCESS] PostgreSQL client found: psql (PostgreSQL) 14.9
[SUCCESS] PostgreSQL version 14.9 is current (>= 12.x)
=== Testing SQL Syntax and Parsing ===
[SUCCESS] SQL file parsing works (connection failed as expected)
✅ PostgreSQL client validation PASSED
```

---

## 📋 Integration with Ansible Playbooks

### Golden Image Playbook Integration

Add validation to your golden image playbooks:

```yaml
# Example: golden-image-rhel8.yml
- name: Build golden runtime image (RHEL 8)
  hosts: targets
  become: true
  
  roles:
    - role: install-nodejs
      tags: [node]
    - role: install-database-client
      tags: [db]
    - role: install-java-sdk
      tags: [java]
      
  post_tasks:
    # Add validation after installation
    - name: Validate all runtime installations
      include: validation/validate.yml
```

### Standalone Validation Playbook

```bash
# Run validation playbook independently
ansible-playbook -i inventory validation/validate.yml

# With specific host groups
ansible-playbook -i inventory validation/validate.yml --limit golden_image_hosts

# With tags for specific runtimes
ansible-playbook -i inventory validation/validate.yml --tags python,java
```

---

## 🔄 CI/CD Pipeline Integration

### Cloud Build Integration

```yaml
# cloudbuild.yaml
steps:
  # ... existing steps ...
  
  - name: ${ANSIBLE_IMAGE}
    id: runtime-validation
    dir: ansible
    entrypoint: bash
    args:
      - -c
      - |
        # Run validation after golden image creation
        ansible-playbook -i hosts.runtime.yml validation/validate.yml
        
        # Save validation results
        gsutil cp artifacts/validation/ gs://${BUCKET}/validation-results/
```

### Bitbucket Pipelines Integration

```yaml
# bitbucket-pipelines.yml
pipelines:
  default:
    - step:
        name: Runtime Validation
        script:
          - cd ansible/validation
          - ./validate_all.sh --verbose
          - cp validation_results_*.log $BITBUCKET_DOWNLOADS/
```

### GitHub Actions Integration

```yaml
# .github/workflows/validation.yml
- name: Validate Runtimes
  run: |
    cd ansible/validation
    ./validate_all.sh --continue --verbose
    
- name: Upload Validation Results
  uses: actions/upload-artifact@v3
  with:
    name: validation-results
    path: ansible/validation/validation_results_*.log
```

---

## 🛠️ Advanced Usage

### Custom Validation Configuration

Create environment-specific validation configs:

```bash
# validation/configs/rhel8.conf
PYTHON_MIN_VERSION="3.8"
JAVA_VERSION="11"
NODE_MAJOR="18"
POSTGRES_MIN_VERSION="12"

# Source config in validation scripts
source "configs/rhel8.conf"
```

### Parallel Validation (Experimental)

```bash
# Run validations in parallel (faster but less clear error attribution)
./validate_all.sh --parallel
```

### Custom Validation Scripts

Add new runtime validations by following the template:

```bash
# Create new validation script
cp validate_python.sh validate_myruntime.sh

# Edit validate_all.sh to include new runtime
VALIDATION_SCRIPTS+=(
    "validate_myruntime.sh:My Runtime:🔧"
)
```

---

## 📊 Validation Strategy Comparison

| Aspect | Per-Runtime Strategy | Global Strategy |
|--------|---------------------|-----------------|
| **Failure Detection** | ⭐⭐⭐⭐⭐ Immediate | ⭐⭐⭐ Later |
| **Root Cause Analysis** | ⭐⭐⭐⭐⭐ Clear | ⭐⭐ Complex |
| **Execution Speed** | ⭐⭐⭐ Moderate | ⭐⭐⭐⭐⭐ Fast |
| **Complexity** | ⭐⭐⭐ Medium | ⭐⭐⭐⭐⭐ Simple |
| **Debugging** | ⭐⭐⭐⭐⭐ Easy | ⭐⭐ Difficult |
| **CI/CD Integration** | ⭐⭐⭐⭐ Good | ⭐⭐⭐⭐⭐ Excellent |

**Recommendation:** Start with **per-runtime strategy** during stabilization phase, then consider switching to **global strategy** once the golden image process is stable.

---

## 🧪 Testing and Development

### Local Testing

```bash
# Test on local VM
vagrant up rhel8-test
ansible-playbook -i test-inventory validation/validate.yml

# Test individual components
./validate_python.sh
./validate_java.sh
```

### Mock Testing

```bash
# Test validation logic without actual runtime installations
MOCK_MODE=true ./validate_all.sh
```

### Debugging Validation Issues

```bash
# Enable debug mode
DEBUG=true ./validate_python.sh

# Run with maximum verbosity
./validate_all.sh --verbose --continue

# Check specific validation logs
tail -f validation_results_*.log
```

---

## 🚨 Troubleshooting

### Common Issues

**Python Validation Fails:**
```bash
# Check Python installation
python3 --version
pip3 --version
which python3

# Verify PATH
echo $PATH | grep -o '[^:]*python[^:]*'
```

**Java Validation Fails:**
```bash
# Check Java installation
java -version
javac -version
echo $JAVA_HOME

# Verify JDK vs JRE
rpm -qa | grep -i openjdk
```

**Node.js Validation Fails:**
```bash
# Check Node.js installation
node --version
npm --version
which node

# Check npm configuration
npm config list
```

**PostgreSQL Validation Fails:**
```bash
# Check PostgreSQL client
psql --version
which psql

# Check package installation
rpm -qa | grep postgresql
```

### Log Analysis

```bash
# View validation summary
grep -E "(PASSED|FAILED)" validation_results_*.log

# Extract error details
grep -A 10 -B 5 "ERROR" validation_results_*.log

# Check timing information
grep "Duration:" validation_results_*.log
```

---

## 🔮 Future Enhancements

### Planned Features

- [ ] **Global Validation Strategy** - Implement install-all-then-validate approach
- [ ] **Parallel Execution** - Run validations in parallel for speed
- [ ] **Custom Test Suites** - Runtime-specific extended test suites
- [ ] **Performance Benchmarking** - Runtime performance validation
- [ ] **Security Scanning** - Runtime security vulnerability checks
- [ ] **Monitoring Integration** - Export metrics to monitoring systems

### Migration Path

```bash
# Phase 1: Current (Per-Runtime Strategy)
./validate_all.sh --strategy per-runtime

# Phase 2: Future (Global Strategy)
./validate_all.sh --strategy global

# Phase 3: Advanced (Performance + Security)
./validate_all.sh --strategy global --performance --security
```

---

## 📞 Support

### Getting Help

1. **Review logs**: Check `validation_results_*.log` files
2. **Run individual validations**: Use `--runtime <name>` flag
3. **Enable verbose mode**: Use `--verbose` flag
4. **Check documentation**: Review individual script headers

### Contributing

1. Fork the repository
2. Create feature branch: `git checkout -b feature/new-validation`
3. Add validation script following existing patterns
4. Update documentation
5. Submit pull request

---

## 📄 License

This validation system is part of the Ansible golden image automation project. See project LICENSE file for details.

---

**🎉 Happy Validating!** 

The per-runtime validation strategy gives you immediate feedback on which runtime installations succeed or fail, making debugging and stabilization much faster and more reliable.
