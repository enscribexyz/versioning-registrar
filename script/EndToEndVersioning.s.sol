// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ENS} from "ens-contracts/registry/ENS.sol";
import {ENSRegistry} from "ens-contracts/registry/ENSRegistry.sol";
import {OwnedResolver} from "ens-contracts/resolvers/OwnedResolver.sol";
import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {IAddrResolver} from "../src/interfaces/IAddrResolver.sol";
import {VersioningRegistrar} from "../src/VersioningRegistrar.sol";
import {SimpleOwnable} from "../src/SimpleOwnable.sol";

contract EndToEndVersioningScript is Script {
    error ResolutionMismatch();
    error LatestVersionMismatch(uint64 expected, uint64 actual);

    event ContractDeployed(string name, address addr);
    event FlowComplete(
        address indexed deployer,
        address ensRegistry,
        address resolver,
        address registrar,
        address appContract,
        bytes32 orgNode,
        bytes32 appNode,
        bytes32 v1Node,
        bytes32 latestNode
    );

    uint256 private constant DEFAULT_ANVIL_PRIVATE_KEY =
        0xAC0974BEC39A17E36BA4A6B4D238FF944BACB478CBED5EFCAE784D7BF4F2FF80;

    bytes32 private constant ROOT_NODE = bytes32(0);
    bytes32 private constant ETH_LABEL_HASH = keccak256("eth");
    bytes32 private constant VERSION_LABEL_HASH = keccak256("version");
    bytes32 private constant V1_LABEL_HASH = keccak256("1");
    bytes32 private constant LATEST_LABEL_HASH = keccak256("latest");

    string private constant ORG_LABEL = "org";
    string private constant APP_LABEL = "app";

    function run() external {
        uint256 deployerPrivateKey = _deployerPrivateKey();
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        ENSRegistry ens = new ENSRegistry();
        emit ContractDeployed("ENSRegistry", address(ens));
        console2.log("ENSRegistry:", address(ens));

        OwnedResolver resolver = new OwnedResolver();
        emit ContractDeployed("OwnedResolver", address(resolver));
        console2.log("OwnedResolver:", address(resolver));

        bytes32 ethNode = _deriveNode(ROOT_NODE, ETH_LABEL_HASH);
        bytes32 versionRootNode = _deriveNode(ethNode, VERSION_LABEL_HASH);

        ens.setSubnodeRecord(ROOT_NODE, ETH_LABEL_HASH, deployer, address(resolver), 0);

        VersioningRegistrar registrar =
            new VersioningRegistrar(ENS(address(ens)), IAddrResolver(address(resolver)), versionRootNode);
        emit ContractDeployed("VersioningRegistrar", address(registrar));
        console2.log("VersioningRegistrar:", address(registrar));

        resolver.transferOwnership(address(registrar));

        ens.setSubnodeRecord(ethNode, VERSION_LABEL_HASH, address(registrar), address(resolver), 0);

        SimpleOwnable app = new SimpleOwnable(deployer);
        emit ContractDeployed("SimpleOwnable", address(app));
        console2.log("SimpleOwnable:", address(app));

        bytes32 orgNode = registrar.registerOrg(ORG_LABEL, deployer);
        bytes32 appNode = registrar.registerApp(APP_LABEL, orgNode, address(app)); // pass initial version
        console2.logBytes32(orgNode);
        console2.logBytes32(appNode);

        registrar.publishVersion(appNode, address(app)); // start version'
        registrar.publishVersion(appNode, address(app));

        bytes32 v1Node = _deriveNode(appNode, V1_LABEL_HASH);
        bytes32 latestNode = _deriveNode(appNode, LATEST_LABEL_HASH);

        address v1Resolved = resolver.addr(v1Node);
        address latestResolved = resolver.addr(latestNode);

        if (v1Resolved != address(app) || latestResolved != address(app)) revert ResolutionMismatch();

        uint64 latestVersion = registrar.latestVersion(appNode);
        if (latestVersion != 2) revert LatestVersionMismatch(2, latestVersion);

        vm.stopBroadcast();

        emit FlowComplete(
            deployer,
            address(ens),
            address(resolver),
            address(registrar),
            address(app),
            orgNode,
            appNode,
            v1Node,
            latestNode
        );
    }

    function _deployerPrivateKey() private returns (uint256 pk) {
        pk = DEFAULT_ANVIL_PRIVATE_KEY;

        try vm.envUint("PRIVATE_KEY") returns (uint256 envPk) {
            if (envPk != 0) {
                pk = envPk;
            }
        } catch {}
    }

    function _deriveNode(bytes32 parentNode, bytes32 labelHash) private pure returns (bytes32) {
        return keccak256(abi.encodePacked(parentNode, labelHash));
    }
}
