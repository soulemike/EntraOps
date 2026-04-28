#!/bin/bash
# Automated test runner - no interactive login required

set -e

echo "========================================"
echo "ServiceEM Automated Test Suite"
echo "========================================"
echo ""

# Check if Docker is available
if ! command -v docker &> /dev/null; then
    echo "❌ Docker is required but not installed"
    exit 1
fi

echo "Building test image..."
docker build -f Dockerfile.test -t entraops-test:latest . > /dev/null 2>&1

echo "Running mock-based unit tests..."
docker run --rm \
    -v "$(pwd):/workspace" \
    -w /workspace \
    entraops-test:latest \
    pwsh -Command "Import-Module Pester -Force; \$results = Invoke-Pester -Path '/workspace/Tests/ServiceEM/Mock-EntraOpsServiceEntraGroup.Tests.ps1' -PassThru; exit \$results.FailedCount"

TEST_EXIT_CODE=$?

if [ $TEST_EXIT_CODE -eq 0 ]; then
    echo ""
    echo "✅ All tests passed!"
    exit 0
else
    echo ""
    echo "❌ Some tests failed"
    exit 1
fi
