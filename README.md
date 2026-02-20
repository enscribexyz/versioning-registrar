## Versioning Registrar (Foundry)

This project implements the ENS-based versioning flow from your sequence diagram:
- `cork.version.eth` for org namespace
- `app.cork.version.eth` for app identity that resolves to a proxy
- `1.app.cork.version.eth` + `latest.app.cork.version.eth` for implementation versions

## Dependencies

ENS core contracts are installed via Forge:
```bash
forge install ensdomains/ens-contracts --no-git
forge install OpenZeppelin/openzeppelin-contracts@v4.9.6 --no-git
```

Imports used in this repo:
- `ens-contracts/registry/ENS.sol`
- `ens-contracts/registry/ENSRegistry.sol`
- `ens-contracts/resolvers/OwnedResolver.sol`

## Contracts

- `src/VersioningRegistrar.sol`
  - Secure org/app/version registration with custom errors and strict access control.
  - App registration requires proxy contract code to exist.
  - Version publish requires implementation contract code to exist.
  - Updates `latest` alias on each publish.

- `lib/ens-contracts/contracts/resolvers/OwnedResolver.sol`
  - ENS resolver used for `setAddr` / `addr`.
  - Resolver ownership is transferred to the registrar so the registrar can update records.

## Forge Test Strategy

`forge test` does full E2E setup and validation:
1. Deploy ENS core (`ENSRegistry`) and resolver.
2. Register `.eth` from root.
3. Deploy `VersioningRegistrar` with `rootNode = namehash("version.eth")`.
4. Transfer resolver ownership to registrar.
5. Register `version.eth` in ENS with owner = registrar.
6. Run org/app/version lifecycle and negative security tests.

Run:
```bash
forge build
forge test -vvv
```

## Local Anvil Deployment Flow

1. Start local chain:
```bash
anvil
```

2. Deploy ENS + resolver + registrar and register `.eth` + `version.eth`:
```bash
./script/deploy-local.sh
```

Optional environment overrides:
```bash
RPC_URL=http://127.0.0.1:8545 PRIVATE_KEY=<anvil_private_key> ./script/deploy-local.sh
```

3. Run tests against the running local chain snapshot:
```bash
forge test --fork-url http://127.0.0.1:8545 -vvv
```
