# --- Build stage ---
FROM swift:latest AS builder
WORKDIR /app

COPY . .

RUN swift build -c release

# --- Runtime stage ---
FROM swift:slim AS runner
WORKDIR /app

RUN apt update && apt install -y tini

COPY --from=builder /app/.build/release/zmqtt2prom .

ENTRYPOINT ["/usr/bin/tini", "--", "/app/zmqtt2prom"]