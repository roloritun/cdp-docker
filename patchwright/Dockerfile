# Patchright CDP + noVNC Container for Daytona
# Optimized for browser-use library connection via CDP

FROM ubuntu:22.04

# Metadata for Daytona
LABEL daytona.compatible="true"
LABEL daytona.version="1.0.0"
LABEL org.opencontainers.image.title="Patchright CDP + noVNC"
LABEL org.opencontainers.image.description="Patchright browser automation with CDP and noVNC for Daytona"

# Prevent interactive prompts
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC

# Service ports
ENV DISPLAY=:99
ENV CHROME_BIN="/ms-playwright/chromium-1169/chrome-linux/chrome"
ENV VNC_PORT=5901
ENV NOVNC_PORT=6080
ENV CDP_PORT=9223
ENV CDP_STANDALONE_PORT=9221
ENV API_PORT=8000
ENV CDP_API_PORT=8080

RUN mkdir -p /tmp/.X11-unix && chmod 1777 /tmp/.X11-unix

# Install system dependencies in smaller chunks to avoid memory issues
RUN apt-get update && apt-get install -y --no-install-recommends \
    wget curl unzip git sudo nano vim \
    && rm -rf /var/lib/apt/lists/*

RUN apt-get update && apt-get install -y --no-install-recommends \
    netstat-nat net-tools \
    python3 python3-pip python3-venv \
    && rm -rf /var/lib/apt/lists/*

RUN apt-get update && apt-get install -y --no-install-recommends \
    nodejs npm \
    && rm -rf /var/lib/apt/lists/*

RUN apt-get update && apt-get install -y --no-install-recommends \
    xvfb x11vnc fluxbox \    
    && rm -rf /var/lib/apt/lists/*

RUN apt-get update && apt-get install -y --no-install-recommends \
    fonts-liberation fonts-noto-color-emoji \
    tesseract-ocr tesseract-ocr-eng \
    && rm -rf /var/lib/apt/lists/*

RUN apt-get update && apt-get install -y --no-install-recommends \
    libnss3 libxss1 libasound2 libatk-bridge2.0-0 \
    libgtk-3-0 libdrm2 libgbm1 libxcomposite1 \
    && rm -rf /var/lib/apt/lists/*

RUN apt-get update && apt-get install -y --no-install-recommends \
    libxdamage1 libxrandr2 libxfixes3 libatk1.0-0 \
    libcups2 libdbus-1-3 libatspi2.0-0 libxkbcommon0 \
    && rm -rf /var/lib/apt/lists/*

RUN apt-get update && apt-get install -y --no-install-recommends \
    supervisor socat \
    && rm -rf /var/lib/apt/lists/*

# Install noVNC with network retry resilience
RUN git clone --depth 1 https://github.com/novnc/noVNC.git /opt/novnc \
    && (git clone --depth 1 https://github.com/novnc/websockify.git /opt/novnc/utils/websockify || \
        (sleep 10 && git clone --depth 1 https://github.com/novnc/websockify.git /opt/novnc/utils/websockify) || \
        (sleep 30 && git clone --depth 1 https://github.com/novnc/websockify.git /opt/novnc/utils/websockify)) \
    && chmod +x /opt/novnc/utils/websockify/run \
    && ln -s /opt/novnc/vnc.html /opt/novnc/index.html

# Node.js is already installed - our CDP proxy uses only built-in modules

# Create Python virtual environment
RUN python3 -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Install Python dependencies in smaller steps
COPY requirements.txt /tmp/requirements.txt
RUN pip install --upgrade pip setuptools wheel

# Install Python dependencies first
RUN pip install --no-cache-dir -r /tmp/requirements.txt \
    && rm /tmp/requirements.txt \
    && rm -rf /root/.cache/pip

# Install Patchright in smaller steps to avoid memory issues
ENV PLAYWRIGHT_BROWSERS_PATH=/ms-playwright
# Memory optimization for Patchright installation
ENV PYTHONDONTWRITEBYTECODE=1
ENV PIP_NO_CACHE_DIR=1
ENV PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1

# Install system dependencies for Patchright (chromium only to save memory)
RUN patchright install-deps chromium

# Install Chromium browser separately with retry logic
RUN for i in {1..3}; do \
    patchright install chromium && break || \
    (echo "Browser install attempt $i failed, retrying..." && sleep 10); \
    done && \
    rm -rf /tmp/* /var/tmp/* /root/.cache/*
    
# Install Chromium browser separately
#RUN patchright install chromium \
#    && rm -rf /tmp/* /var/tmp/*

# Verify installation
RUN python -c "from patchright.sync_api import sync_playwright; print('Patchright installed successfully')"

# Create user for running services
RUN useradd -m -s /bin/bash patchright \
    && usermod -aG sudo patchright \
    && echo "patchright ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Create directories and set basic permissions
RUN mkdir -p \
    /app \
    /workspace \
    /tmp/chrome-profile \
    /tmp/chrome-cdp-profile \
    /var/log/supervisor

# Set ownership in smaller batches to reduce memory usage
RUN chown -R patchright:patchright /app /workspace
RUN chown -R patchright:patchright /tmp/chrome-profile /tmp/chrome-cdp-profile  
RUN chown -R patchright:patchright /var/log/supervisor
# RUN chown -R patchright:patchright /ms-playwright /opt/venv  # Moved to runtime to avoid memory issues
RUN chmod 755 /tmp/chrome-profile /tmp/chrome-cdp-profile

# Fix dbus socket permissions for Chrome
RUN chmod 666 /run/dbus/system_bus_socket || true

RUN mkdir -p /run/dbus && touch /run/dbus/system_bus_socket

# Copy configuration files
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY startup.sh /usr/local/bin/startup.sh
COPY healthcheck.sh /usr/local/bin/healthcheck.sh
COPY start_chrome_cdp.sh /usr/local/bin/start_chrome_cdp.sh
COPY cdp_proxy_simple.js /usr/local/bin/cdp_proxy_simple.js

# Make scripts executable
RUN chmod +x /usr/local/bin/startup.sh /usr/local/bin/healthcheck.sh /usr/local/bin/start_chrome_cdp.sh /usr/local/bin/cdp_proxy_simple.js

# Copy application files
COPY app/ /app/
COPY package.json /app/
RUN chown -R patchright:patchright /app

# Don't switch to patchright user yet - startup script needs root permissions initially
WORKDIR /workspace

# Expose ports (including standalone CDP port 9221)
EXPOSE $VNC_PORT $NOVNC_PORT $CDP_PORT $CDP_STANDALONE_PORT $API_PORT $CDP_API_PORT

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD /usr/local/bin/healthcheck.sh

# Start services - supervisord embedded in startup.sh
ENTRYPOINT ["/usr/local/bin/startup.sh"]
