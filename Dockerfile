FROM node:22-bookworm@sha256:cd7bcd2e7a1e6f72052feb023c7f6b722205d3fcab7bbcbd2d1bfdab10b1e935

# Install Bun (required for build scripts)
RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/root/.bun/bin:${PATH}"

RUN corepack enable

WORKDIR /app
RUN chown node:node /app

ARG OPENCLAW_DOCKER_APT_PACKAGES=""
RUN if [ -n "$OPENCLAW_DOCKER_APT_PACKAGES" ]; then \
      apt-get update && \
      DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends $OPENCLAW_DOCKER_APT_PACKAGES && \
      apt-get clean && \
      rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*; \
    fi

COPY --chown=node:node package.json pnpm-lock.yaml pnpm-workspace.yaml .npmrc ./
COPY --chown=node:node ui/package.json ./ui/package.json
COPY --chown=node:node patches ./patches
COPY --chown=node:node scripts ./scripts

USER node
RUN pnpm install --frozen-lockfile

# Optionally install Chromium and Xvfb for browser automation.
# Build with: docker build --build-arg OPENCLAW_INSTALL_BROWSER=1 ...
# Adds ~300MB but eliminates the 60-90s Playwright install on every container start.
# Must run after pnpm install so playwright-core is available in node_modules.
USER root
ARG OPENCLAW_INSTALL_BROWSER=""
RUN if [ -n "$OPENCLAW_INSTALL_BROWSER" ]; then \
      apt-get update && \
      DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends xvfb && \
      mkdir -p /home/node/.cache/ms-playwright && \
      PLAYWRIGHT_BROWSERS_PATH=/home/node/.cache/ms-playwright \
      node /app/node_modules/playwright-core/cli.js install --with-deps chromium && \
      chown -R node:node /home/node/.cache/ms-playwright && \
      apt-get clean && \
      rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*; \
    fi

USER node
COPY --chown=node:node . .
RUN pnpm build
# Force pnpm for UI build (Bun may fail on ARM/Synology architectures)
ENV OPENCLAW_PREFER_PNPM=1
RUN pnpm ui:build

ENV NODE_ENV=production

# Install gosu for dropping privileges in entrypoint
USER root
RUN apt-get update && \
    apt-get install -y --no-install-recommends gosu && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Create /data directory for Railway/container volume mounts.
RUN mkdir -p /data && chown -R node:node /data

# Copy entrypoint script (fixes volume permissions at runtime)
COPY docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# Start gateway server for container/PaaS deployments (Railway, Render, etc.).
# Binds to 0.0.0.0 (LAN mode) so container orchestrators can reach the service.
#
# The entrypoint runs as root to fix volume permissions, then drops to node user.
#
# Required env vars for container deployments:
#   - PORT (e.g. 8080): The port to listen on
#   - OPENCLAW_GATEWAY_TOKEN or OPENCLAW_GATEWAY_PASSWORD: Required for non-loopback bind
#
# Recommended env vars:
#   - OPENCLAW_STATE_DIR=/data/.openclaw
#   - OPENCLAW_WORKSPACE_DIR=/data/workspace
ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["node", "openclaw.mjs", "gateway", "--allow-unconfigured", "--bind", "lan"]
