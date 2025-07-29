# syntax=docker/dockerfile:1

# --- Build stage ---
FROM swift:latest AS builder
WORKDIR /app

# Copy the entire project files
COPY . .

# Build the release binary
RUN swift build -c release

# --- Runtime stage ---
FROM swift:slim AS runner
WORKDIR /app

# Copy the built binary from the builder stage
COPY --from=builder /app/.build/release/zmqtt2prom .

# (Optional) Copy additional configuration files if needed
# COPY --from=builder /app/config ./config

# Set the default command to run the binary
CMD ["./zmqtt2prom"]
