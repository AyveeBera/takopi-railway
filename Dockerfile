FROM ghcr.io/astral-sh/uv:python3.14-bookworm

# System deps
RUN apt-get update && apt-get install -y --no-install-recommends \
    nodejs npm git curl cron gh openssl && rm -rf /var/lib/apt/lists/*

# Install engine CLIs
RUN npm install -g @anthropic-ai/claude-code @openai/codex

# Install takopi from fix branch
RUN uv tool install git+https://github.com/asianviking/takopi.git@fix/chat-id-validation

# Persistent data mount point
WORKDIR /data

COPY docker-entrypoint.sh /usr/local/bin/
COPY refresh-github-token.sh /usr/local/bin/
COPY github-token-daemon.sh /usr/local/bin/
COPY github-token /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/refresh-github-token.sh /usr/local/bin/github-token-daemon.sh /usr/local/bin/github-token

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["takopi"]
