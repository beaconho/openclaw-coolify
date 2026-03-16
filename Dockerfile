# syntax=docker/dockerfile:1

########################################
# Stage 1: Base System
########################################
FROM node:22-bookworm-slim AS base

ENV DEBIAN_FRONTEND=noninteractive \
    PIP_ROOT_USER_ACTION=ignore

# Core packages + build tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    wget \
    git \
    unzip \
    build-essential \
    python3 \
    python3-pip \
    python3-venv \
    jq \
    lsof \
    openssl \
    ca-certificates \
    gnupg \
    ripgrep fd-find fzf bat \
    pandoc \
    poppler-utils \
    ffmpeg \
    imagemagick \
    graphviz \
    sqlite3 \
    pass \
    chromium \
    && rm -rf /var/lib/apt/lists/*

# Install modern Docker client to match host API
RUN curl -fsSL https://download.docker.com/linux/static/stable/x86_64/docker-27.3.1.tgz | tar -xzC /tmp && \
    mv /tmp/docker/docker /usr/local/bin/ && \
    rm -rf /tmp/docker

# 🔥 CRITICAL FIX (native modules)
ENV PYTHON=/usr/bin/python3 \
    npm_config_python=/usr/bin/python3

RUN ln -sf /usr/bin/python3 /usr/bin/python && \
    npm install -g node-gyp

########################################
# Stage 2: Runtimes
########################################
FROM base AS runtimes

ENV BUN_INSTALL="/data/.bun" \
    PATH="/usr/local/go/bin:/data/.bun/bin:/data/.bun/install/global/bin:$PATH"

# Install Bun (allow bun to manage compatible node)
RUN curl -fsSL https://bun.sh/install | bash

# Cache the heavy pip packages first
RUN pip3 install ipython csvkit openpyxl python-docx pypdf botasaurus browser-use playwright --break-system-packages

# Then run the OS-level dependency installation in a separate layer
RUN playwright install-deps

ENV XDG_CACHE_HOME="/data/.cache"

########################################
# Stage 3: Dependencies
########################################
FROM runtimes AS dependencies

ARG OPENCLAW_BETA=false
ENV OPENCLAW_BETA=${OPENCLAW_BETA} \
    OPENCLAW_NO_ONBOARD=1 \
    NPM_CONFIG_UNSAFE_PERM=true

# 1. Configure NPM to be highly resilient to network drops
RUN npm config set fetch-retries 5 && \
    npm config set fetch-retry-mintimeout 20000 && \
    npm config set fetch-retry-maxtimeout 120000 && \
    npm config set fetch-timeout 600000 && \
    npm config set maxsockets 15 && \
    npm cache clean --force

# 2. Install Vercel globally (robust version)
RUN npm install -g vercel@latest --force

# 3. Split the heavy packages into separate RUN layers.
# If a network drop happens here, Docker caches the successful layers!
RUN npm install -g @marp-team/marp-cli @openai/codex
RUN npm install -g @google/gemini-cli opencode-ai
RUN npm install -g @steipete/summarize @hyperbrowser/agent clawhub

# 4. Clone the GitHub package using git
RUN git clone https://github.com/tobi/qmd /tmp/qmd && \
    cd /tmp/qmd && \
    npm install -g . && \
    rm -rf /tmp/qmd

# Ensure global npm bin is in PATH
ENV PATH="/usr/local/bin:/usr/local/lib/node_modules/.bin:${PATH}"

# OpenClaw (Official npm global install to build UI assets)
RUN if [ "$OPENCLAW_BETA" = "true" ]; then \
    npm install -g openclaw@beta --force; \
    else \
    npm install -g openclaw --force; \
    fi

# Install uv explicitly
RUN curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR="/usr/local/bin" sh

# Kimi only
RUN curl -L https://code.kimi.com/install.sh | bash && \
    command -v uv

# Make sure uv and other local bins are available
ENV PATH="/root/.local/bin:${PATH}"

########################################
# Stage 4: Final
########################################
FROM dependencies AS final

WORKDIR /app
COPY . .

# Symlinks
RUN ln -sf /data/.kimi/bin/kimi /usr/local/bin/kimi || true && \
    chmod +x /app/scripts/*.sh

ENV PATH="/root/.local/bin:/usr/local/go/bin:/usr/local/bin:/usr/bin:/bin:/data/.bun/bin:/data/.bun/install/global/bin:/data/.claude/bin:/data/.kimi/bin"
EXPOSE 18789
CMD ["bash", "/app/scripts/bootstrap.sh"]
