#!/bin/bash
# Interactive Docker test runner for ServiceEM

echo "========================================"
echo "ServiceEM Docker Test Environment"
echo "========================================"
echo ""
echo "Building Docker image..."
docker build -f Dockerfile.test -t entraops-test:latest .

echo ""
echo "Starting interactive container..."
echo "Tenant: M365x60294116.onmicrosoft.com"
echo ""
echo "You will need to:"
echo "  1. Wait for the container to start"
echo "  2. Approve MFA when prompted"
echo "  3. Review test results"
echo ""
echo "Run the test script with:"
echo "  ./test-servicem-docker.ps1"
echo ""
echo "Or with cleanup after:"
echo "  ./test-servicem-docker.ps1 -CleanupAfterTest"
echo ""

# Run interactive container with host network for MFA
docker run -it --rm \
    --name entraops-test \
    -v "$(pwd):/workspace" \
    -w /workspace \
    entraops-test:latest
