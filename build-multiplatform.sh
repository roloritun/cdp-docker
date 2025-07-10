#!/bin/bash
set -e

echo "🏗️  Building Multi-Platform Playwright/Patchright CDP + noVNC Container"
echo "======================================================================"

# Check if Docker buildx is available
if ! docker buildx version > /dev/null 2>&1; then
    echo "❌ Docker buildx is not available. Please install Docker Desktop or enable buildx."
    exit 1
fi

# Create a new builder if it doesn't exist
if ! docker buildx inspect multiplatform-builder > /dev/null 2>&1; then
    echo "📦 Creating multi-platform builder..."
    docker buildx create --name multiplatform-builder --driver docker-container --bootstrap
fi

# Use the builder
docker buildx use multiplatform-builder

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATCHWRIGHT_DIR="${SCRIPT_DIR}/patchwright"

# Change to patchwright directory
cd "${PATCHWRIGHT_DIR}"

# Use date-based versioning by default
VERSION_TAG="${VERSION_TAG:-$(date +%Y.%m.%d)}"
BUILD_TAG="${BUILD_TAG:-${VERSION_TAG}-$(date +%H%M)}"
BUILD_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
REGISTRY="${REGISTRY:-}"  # Optional Docker registry prefix

# Add registry prefix if provided
if [ -n "$REGISTRY" ]; then
    if [[ "$REGISTRY" != */ ]]; then
        REGISTRY="${REGISTRY}/"
    fi
fi

# Docker image name
IMAGE_NAME="${REGISTRY}playwright-cdp-novnc"

echo "🔨 Building Multi-Platform image (AMD64 + ARM64)..."
echo "   Version: ${VERSION_TAG}"
echo "   Build: ${BUILD_TAG}"
echo "   Date: ${BUILD_DATE}"
echo "   Image: ${IMAGE_NAME}"
echo ""

# Build for multiple platforms
echo "⚙️  Starting multi-platform build process..."
docker buildx build \
    --platform linux/amd64,linux/arm64 \
    -f Dockerfile.playwright-cdp-novnc \
    --build-arg VERSION_TAG=${VERSION_TAG} \
    --build-arg BUILD_DATE=${BUILD_DATE} \
    -t ${IMAGE_NAME}:${VERSION_TAG} \
    -t ${IMAGE_NAME}:${BUILD_TAG} \
    -t ${IMAGE_NAME}:latest \
    ${PUSH_FLAG:+--push} \
    .

# If --push wasn't specified, also build and load the images for local use
# Note: buildx can't --load for multiple platforms at once, so we build them separately
if [ -z "$PUSH_FLAG" ]; then
    echo "📦 Building AMD64 image for local use..."
    docker buildx build \
        --platform linux/amd64 \
        -f Dockerfile.playwright-cdp-novnc \
        --build-arg VERSION_TAG=${VERSION_TAG} \
        --build-arg BUILD_DATE=${BUILD_DATE} \
        -t ${IMAGE_NAME}:${VERSION_TAG} \
        -t ${IMAGE_NAME}:${BUILD_TAG} \
        -t ${IMAGE_NAME}:latest \
        --load \
        .
    
    # Check if running on ARM64 to also build that version locally
    if [ "$(uname -m)" = "arm64" ] || [ "$(uname -m)" = "aarch64" ]; then
        echo "📦 Building ARM64 image for local use..."
        docker buildx build \
            --platform linux/arm64 \
            -f Dockerfile.playwright-cdp-novnc \
            --build-arg VERSION_TAG=${VERSION_TAG} \
            --build-arg BUILD_DATE=${BUILD_DATE} \
            -t ${IMAGE_NAME}:${VERSION_TAG}-arm64 \
            --load \
            .
    fi
fi

echo "✅ Multi-platform build completed successfully!"
echo ""
echo "🎯 Usage Options:"
echo ""
echo "1️⃣  Run locally with Docker:"
echo "   docker run -p 8000:8000 -p 6080:6080 -p 9222:9222 -p 5901:5901 ${IMAGE_NAME}:${VERSION_TAG}"
echo ""
echo "2️⃣  Run with docker-compose:"
echo "   cd ${PATCHWRIGHT_DIR} && docker-compose up"
echo ""
echo "3️⃣  Push to a registry:"
echo "   PUSH_FLAG=--push REGISTRY=your-registry/ ./build-multiplatform.sh"
echo ""
echo "4️⃣  Deploy to Daytona:"
echo "   cd ${PATCHWRIGHT_DIR} && ./deploy-daytona.sh"
echo ""
echo "📋 Container exposes the following services:"
echo "  📺 noVNC Web UI: Available on port 6080"
echo "  🔧 VNC Direct:   Available on port 5901"
echo "  🌐 CDP Endpoint: Available on port 9222"
echo "  📡 API Server:   Available on port 8000"
echo "  💻 Workspace:    /workspace directory"
echo ""
echo "🏥 Health check: GET /health endpoint"
echo "📚 API docs: GET /docs endpoint"
echo ""
echo "🏷️  Built tags:"
echo "   - ${IMAGE_NAME}:${VERSION_TAG} (version tag)"
echo "   - ${IMAGE_NAME}:${BUILD_TAG} (build tag)"
echo "   - ${IMAGE_NAME}:latest (latest tag)"

# Return to original directory
cd "${SCRIPT_DIR}"
