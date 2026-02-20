# Versioning Registrar

`VersioningRegistrar` is an ENS-based registry contract that manages software version naming under a root namespace (for example `version.eth`).

It provides three layers of identity:
- Org namespace: `cork.version.eth`
- App namespace (points to proxy/app entry): `app.cork.version.eth`
- Version namespace (points to implementation): `1.app.cork.version.eth`, `2.app.cork.version.eth`, and `latest.app.cork.version.eth`

The registrar owns the subnodes it creates and writes address records through ENS resolver calls.

## Protocol Flow (Step-by-Step)

Actors:
- User: `Deployer` / org admin / app admin
- `VersioningRegistrar`
- ENS `ENSRegistry`
- ENS resolver (`OwnedResolver` in this project)

### 0) Deployment and Root Setup
1. Deployer deploys `ENSRegistry`.
2. Deployer deploys resolver (`OwnedResolver`).
3. Deployer registers `.eth` in ENS root:
   - `ENSRegistry.setSubnodeRecord(root, keccak256("eth"), deployer, resolver, 0)`
4. Deployer deploys `VersioningRegistrar(ens, resolver, namehash("version.eth"))`.
5. Deployer transfers resolver ownership to registrar:
   - `OwnedResolver.transferOwnership(registrar)`
6. Deployer registers `version.eth` and assigns node ownership to registrar:
   - `ENSRegistry.setSubnodeRecord(namehash("eth"), keccak256("version"), registrar, resolver, 0)`

### 1) Org Registration
1. Deployer calls:
   - `VersioningRegistrar.registerOrg("cork", admin)`
2. Registrar validates label/admin and computes `orgNode`.
3. Registrar creates ENS subnode for `cork.version.eth`:
   - `ENSRegistry.setSubnodeRecord(versionNode, keccak256("cork"), registrar, resolver, 0)`
4. Registrar stores admin in `orgAdmin[orgNode]`.

### 2) App Registration
1. Org admin calls:
   - `VersioningRegistrar.registerApp("app", orgNode, proxy)`
2. Registrar verifies caller is org admin and `proxy.code.length > 0`.
3. Registrar creates ENS subnode for `app.cork.version.eth`:
   - `ENSRegistry.setSubnodeRecord(orgNode, keccak256("app"), registrar, resolver, 0)`
4. Registrar points app node to proxy:
   - `resolver.setAddr(appNode, proxy)`
5. Registrar stores app admin in `appAdmin[appNode]`.

### 3) Publish Version (v1)
1. App admin calls:
   - `VersioningRegistrar.publishVersion(appNode, implementation)`
2. Registrar verifies caller is app admin and `implementation.code.length > 0`.
3. Registrar increments `latestVersion[appNode]` from `0 -> 1`.
4. Registrar creates version node `1.app.cork.version.eth`:
   - `ENSRegistry.setSubnodeRecord(appNode, keccak256("1"), registrar, resolver, 0)`
5. Registrar points version node to implementation:
   - `resolver.setAddr(v1Node, implementation)`
6. Registrar creates `latest.app.cork.version.eth` (first publish only) and points it:
   - `ENSRegistry.setSubnodeRecord(appNode, keccak256("latest"), registrar, resolver, 0)`
   - `resolver.setAddr(latestNode, implementation)`

### 4) Publish Version (v2 and beyond)
1. App admin calls `publishVersion` again.
2. Registrar increments version (`1 -> 2`, etc).
3. Registrar creates numeric version subnode (`2`, `3`, ...), points it to implementation.
4. Registrar updates only `latest` address to newest implementation.

## Run EndToEndVersioning.s.sol

### Prerequisites
```fish
cd /Users/abhi/code/versioning-registrar-foundry
forge build
```

### 1) Start local Anvil node (Terminal 1)
```fish
anvil --host 127.0.0.1 --port 8545
```

### 2) Run the end-to-end script (Terminal 2)
```fish
cd /Users/abhi/code/versioning-registrar-foundry
forge script script/EndToEndVersioning.s.sol:EndToEndVersioningScript --rpc-url http://127.0.0.1:8545 --broadcast -vv
```

The script will:
- deploy ENS registry + resolver + registrar + sample app contract
- run org registration, app registration, publish v1 and v2
- verify forward resolution for v1 and latest
- print deployed contract addresses in script logs

### Optional: use a different deployer private key
```fish
set -x PRIVATE_KEY 0xYOUR_PRIVATE_KEY
forge script script/EndToEndVersioning.s.sol:EndToEndVersioningScript --rpc-url http://127.0.0.1:8545 --broadcast -vv
```
