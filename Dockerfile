# =============================================================================
# Hermes Agent — Custom Debian Image
# =============================================================================
# Builds Hermes from the official install script on top of debian:trixie.
# All runtime state lives in /opt/data (bind-mounted from ./data on the host).
# The image is fully stateless and can be rebuilt without losing any config.
# =============================================================================

FROM debian:trixie

# ---------------------------------------------------------------------------
# Labels
# ---------------------------------------------------------------------------
LABEL maintainer="you"
LABEL description="Hermes Agent (NousResearch) on Debian Trixie"
LABEL org.opencontainers.image.base.name="debian:trixie"

# ---------------------------------------------------------------------------
# System dependencies
#
# nodejs/npm are intentionally NOT installed here — we install Node.js 20 LTS
# via the NodeSource script below to avoid the signal-exit v3/v4 API mismatch
# caused by Debian's older bundled node.
# ---------------------------------------------------------------------------
RUN apt-get update && apt-get upgrade -y && \
    apt-get install -y \
        curl \
        git \
        python3 \
        python-is-python3 \
        python3-dev \
        ripgrep \
        ffmpeg \
        gcc \
        libffi-dev \
        procps \
        openssh-client \
        tini \
        gosu \
        ca-certificates \
        iputils-ping \
        xz-utils && \
    rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# Install Node.js 20 LTS from NodeSource
# Debian Trixie ships Node 18 via apt; Node 20 is required for the ESM
# signal-exit v4 API that the Hermes TUI depends on.
# ---------------------------------------------------------------------------
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get install -y nodejs && \
    rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# Create a non-root user the entrypoint drops privileges to.
# UID/GID 10000 matches the hermes user inside the official NousResearch image.
# ---------------------------------------------------------------------------
RUN groupadd -g 10000 hermes && \
    useradd -m -u 10000 -g hermes -s /bin/bash hermes

# ---------------------------------------------------------------------------
# Install Hermes Agent as root → FHS layout
#   code    → /usr/local/lib/hermes-agent
#   binary  → /usr/local/bin/hermes
#   data    → /opt/data  (bind-mounted volume; see docker-compose.yml)
#
# --skip-setup   skips the interactive wizard (handled by entrypoint.sh)
# --skip-browser skips Playwright/Chromium (~300 MB); remove flag to enable
#
# NOTE: do NOT run a second `npm install` here. The Hermes installer bundles
# its own node_modules including signal-exit v4. Running npm install again
# resolves signal-exit v3 (latest semver-compatible), which breaks the TUI
# with: TypeError: (0, import_signal_exit.onExit) is not a function
# ---------------------------------------------------------------------------
ENV HERMES_HOME=/opt/data

RUN curl -fsSL https://hermes-agent.nousresearch.com/install.sh \
        | bash -s -- --skip-setup --skip-browser && \
    hermes --tui --version && \
    chown -R hermes:hermes /usr/local/lib/hermes-agent

# ---------------------------------------------------------------------------
# Runtime data directory (the persistent volume mount point)
# ---------------------------------------------------------------------------
RUN mkdir -p /opt/data && chown hermes:hermes /opt/data
VOLUME ["/opt/data"]

# ---------------------------------------------------------------------------
# Copy entrypoint
# ---------------------------------------------------------------------------
COPY --chown=root:root entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# ---------------------------------------------------------------------------
# Ports
#   8642 → gateway OpenAI-compatible API + health endpoint
#   9119 → web dashboard (only if HERMES_DASHBOARD=1)
# ---------------------------------------------------------------------------
EXPOSE 8642 9119

# ---------------------------------------------------------------------------
# tini as PID 1 — clean signal forwarding and zombie reaping.
# The entrypoint seeds config on first run then exec's the gateway.
# ---------------------------------------------------------------------------
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
CMD ["--cli"]
