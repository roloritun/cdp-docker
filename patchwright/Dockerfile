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
ENV VNC_PORT=5901
ENV NOVNC_PORT=6080
ENV CDP_PORT=9222
ENV API_PORT=8000
ENV CDP_API_PORT=8080

# Install system dependencies
RUN apt-get update && apt-get install -y \
    # Basic tools
    wget curl unzip git sudo nano vim \
    # Python and Node.js
    python3 python3-pip python3-venv nodejs npm \
    # X11 and VNC
    xvfb x11vnc fluxbox \
    # Fonts and display
    fonts-liberation fonts-noto-color-emoji \
    # Browser dependencies
    libnss3 libxss1 libasound2 libatk-bridge2.0-0 \
    libgtk-3-0 libdrm2 libgbm1 libxcomposite1 \
    libxdamage1 libxrandr2 libxfixes3 libatk1.0-0 \
    libcups2 libdbus-1-3 libatspi2.0-0 libxkbcommon0 \
    # OCR dependencies
    tesseract-ocr tesseract-ocr-eng \
    # Process management
    supervisor socat \
    # Cleanup
    && rm -rf /var/lib/apt/lists/*

# Install noVNC
RUN git clone --depth 1 https://github.com/novnc/noVNC.git /opt/novnc \
    && git clone --depth 1 https://github.com/novnc/websockify.git /opt/novnc/utils/websockify \
    && chmod +x /opt/novnc/utils/websockify/run \
    && ln -s /opt/novnc/vnc.html /opt/novnc/index.html

# Create Python virtual environment
RUN python3 -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Install Python dependencies
COPY requirements.txt /tmp/requirements.txt
RUN pip install --upgrade pip setuptools wheel \
    && pip install -r /tmp/requirements.txt \
    && rm /tmp/requirements.txt

# Install Patchright only (avoid conflicts)
ENV PLAYWRIGHT_BROWSERS_PATH=/ms-playwright
RUN pip install patchright \
    && patchright install-deps \
    && patchright install chromium \
    && python -c "from patchright.sync_api import sync_playwright; print('Patchright installed successfully')"

# Create user for running services
RUN useradd -m -s /bin/bash patchright \
    && usermod -aG sudo patchright \
    && echo "patchright ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Create directories
RUN mkdir -p \
    /app \
    /workspace \
    /tmp/chrome-profile \
    /var/log/supervisor \
    && chown -R patchright:patchright \
        /app \
        /workspace \
        /tmp/chrome-profile \
        /var/log/supervisor \
        /ms-playwright \
        /opt/venv

# Copy configuration files
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY startup.sh /usr/local/bin/startup.sh
COPY healthcheck.sh /usr/local/bin/healthcheck.sh

# Make scripts executable
RUN chmod +x /usr/local/bin/startup.sh /usr/local/bin/healthcheck.sh

# Copy application files
COPY app/ /app/
RUN chown -R patchright:patchright /app

# Don't switch to patchright user yet - startup script needs root permissions initially
WORKDIR /workspace

# Expose ports (including socat forwarder port 9223)
EXPOSE $VNC_PORT $NOVNC_PORT $CDP_PORT 9223 $API_PORT $CDP_API_PORT

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD /usr/local/bin/healthcheck.sh

# Start services - supervisord will handle user switching
ENTRYPOINT ["/usr/local/bin/startup.sh"]
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
