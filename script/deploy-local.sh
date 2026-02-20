#!/usr/bin/env bash
set -euo pipefail

RPC_URL="${RPC_URL:-http://127.0.0.1:8545}"
PRIVATE_KEY="${PRIVATE_KEY:-0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80}"

ROOT_NODE="0x0000000000000000000000000000000000000000000000000000000000000000"
ETH_LABEL_HASH="$(cast keccak "eth")"
VERSION_LABEL_HASH="$(cast keccak "version")"
ETH_NODE="$(cast namehash eth)"
VERSION_ROOT_NODE="$(cast namehash version.eth)"
DEPLOYER="$(cast wallet address --private-key "$PRIVATE_KEY")"

echo "RPC_URL=$RPC_URL"
echo "DEPLOYER=$DEPLOYER"

echo "Deploying ENSRegistry..."
ENS_REGISTRY="$(forge create lib/ens-contracts/contracts/registry/ENSRegistry.sol:ENSRegistry \
  --rpc-url "$RPC_URL" \
  --private-key "$PRIVATE_KEY" \
  --broadcast | awk '/Deployed to:/ {print $3}')"

echo "ENS_REGISTRY=$ENS_REGISTRY"

echo "Deploying OwnedResolver..."
RESOLVER="$(forge create lib/ens-contracts/contracts/resolvers/OwnedResolver.sol:OwnedResolver \
  --rpc-url "$RPC_URL" \
  --private-key "$PRIVATE_KEY" \
  --broadcast | awk '/Deployed to:/ {print $3}')"

echo "RESOLVER=$RESOLVER"

echo "Registering .eth from root..."
cast send "$ENS_REGISTRY" \
  "setSubnodeRecord(bytes32,bytes32,address,address,uint64)" \
  "$ROOT_NODE" "$ETH_LABEL_HASH" "$DEPLOYER" "$RESOLVER" 0 \
  --rpc-url "$RPC_URL" \
  --private-key "$PRIVATE_KEY" >/dev/null

echo "Deploying VersioningRegistrar..."
REGISTRAR="$(forge create src/VersioningRegistrar.sol:VersioningRegistrar \
  --rpc-url "$RPC_URL" \
  --private-key "$PRIVATE_KEY" \
  --broadcast \
  --constructor-args "$ENS_REGISTRY" "$RESOLVER" "$VERSION_ROOT_NODE" | awk '/Deployed to:/ {print $3}')"

echo "REGISTRAR=$REGISTRAR"

echo "Transferring resolver ownership to registrar..."
cast send "$RESOLVER" \
  "transferOwnership(address)" \
  "$REGISTRAR" \
  --rpc-url "$RPC_URL" \
  --private-key "$PRIVATE_KEY" >/dev/null

echo "Registering version.eth under .eth and assigning ownership to registrar..."
cast send "$ENS_REGISTRY" \
  "setSubnodeRecord(bytes32,bytes32,address,address,uint64)" \
  "$ETH_NODE" "$VERSION_LABEL_HASH" "$REGISTRAR" "$RESOLVER" 0 \
  --rpc-url "$RPC_URL" \
  --private-key "$PRIVATE_KEY" >/dev/null

echo

echo "Local deployment complete"
echo "ENSRegistry:        $ENS_REGISTRY"
echo "Resolver:           $RESOLVER"
echo "VersioningRegistrar:$REGISTRAR"
echo "version.eth node:   $VERSION_ROOT_NODE"
