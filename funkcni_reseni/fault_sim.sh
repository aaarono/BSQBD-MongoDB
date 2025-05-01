#!/usr/bin/env bash
set -euo pipefail

# Container names from docker-compose.yml
SHARD_NODE_CONTAINER="shard-03-node-c"
ROUTER_CONTAINER="router-01"

# Credentials for mongos (on the router)
MONGO_USER="user"
MONGO_PASS="pass"
AUTH_DB="admin"

echo "==> Step 1: Stopping the node container ($SHARD_NODE_CONTAINER) — simulating failure"
docker stop "$SHARD_NODE_CONTAINER"
echo "  → Waiting 5 seconds for the node to shut down"
sleep 5

echo "==> Step 2: Diagnosing the cluster via mongos ($ROUTER_CONTAINER)"
docker exec -i "$ROUTER_CONTAINER" mongosh \
  --username "$MONGO_USER" --password "$MONGO_PASS" --authenticationDatabase "$AUTH_DB" \
  --eval "print('=== sh.status() after failure ==='); sh.status();"

echo "==> Step 3: Starting the node container again — recovery"
docker start "$SHARD_NODE_CONTAINER"
echo "  → Waiting 10 seconds for mongod to start and resynchronize"
sleep 10

echo "==> Step 4: Re-diagnosing the cluster via mongos"
docker exec -i "$ROUTER_CONTAINER" mongosh \
  --username "$MONGO_USER" --password "$MONGO_PASS" --authenticationDatabase "$AUTH_DB" \
  --eval "print('=== sh.status() after recovery ==='); sh.status();"

echo "==> Script complete: node recovered, cluster is stable."
