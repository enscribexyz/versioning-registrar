// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ENS} from "ens-contracts/registry/ENS.sol";
import {ENSRegistry} from "ens-contracts/registry/ENSRegistry.sol";
import {OwnedResolver} from "ens-contracts/resolvers/OwnedResolver.sol";

import {IAddrResolver} from "../src/interfaces/IAddrResolver.sol";
import {VersioningRegistrar} from "../src/VersioningRegistrar.sol";
import {TestBase} from "./helpers/TestBase.sol";

contract DummyProxy {
    function ping() external pure returns (uint256) {
        return 1;
    }
}

contract DummyImplementation {
    function version() external pure returns (uint256) {
        return 1;
    }
}

contract VersioningRegistrarTest is TestBase {
    bytes32 private constant ROOT_NODE = bytes32(0);
    bytes32 private constant ETH_LABEL_HASH = keccak256("eth");
    bytes32 private constant VERSION_LABEL_HASH = keccak256("version");

    address private constant ORG_ADMIN = address(0xA11CE);
    address private constant NEW_ORG_ADMIN = address(0xB0B);
    address private constant APP_ADMIN = address(0xCAFE);
    address private constant ATTACKER = address(0xBAD);

    ENSRegistry private ens;
    OwnedResolver private resolver;
    VersioningRegistrar private registrar;

    address private proxy;
    address private implV1;
    address private implV2;

    bytes32 private ethNode;
    bytes32 private versionRootNode;

    function setUp() public {
        ens = new ENSRegistry();
        resolver = new OwnedResolver();

        proxy = address(new DummyProxy());
        implV1 = address(new DummyImplementation());
        implV2 = address(new DummyImplementation());

        ethNode = _deriveNode(ROOT_NODE, ETH_LABEL_HASH);
        versionRootNode = _deriveNode(ethNode, VERSION_LABEL_HASH);

        ens.setSubnodeRecord(ROOT_NODE, ETH_LABEL_HASH, address(this), address(resolver), 0);

        registrar = new VersioningRegistrar(ENS(address(ens)), IAddrResolver(address(resolver)), versionRootNode);
        resolver.transferOwnership(address(registrar));

        ens.setSubnodeRecord(ethNode, VERSION_LABEL_HASH, address(registrar), address(resolver), 0);
    }

    function testLifecycleRegisterOrgRegisterAppPublishVersions() public {
        bytes32 orgNode = registrar.registerOrg("cork", ORG_ADMIN);
        assertEq(registrar.orgAdmin(orgNode), ORG_ADMIN);

        vm.prank(ORG_ADMIN);
        bytes32 appNode = registrar.registerApp("app", orgNode, proxy);
        assertEq(resolver.addr(appNode), proxy);

        vm.prank(ORG_ADMIN);
        (bytes32 v1Node, uint64 v1) = registrar.publishVersion(appNode, implV1);

        assertEq(uint256(v1), 1);
        assertEq(resolver.addr(v1Node), implV1);
        assertEq(registrar.latestImplementation(appNode), implV1);

        vm.prank(ORG_ADMIN);
        (bytes32 v2Node, uint64 v2) = registrar.publishVersion(appNode, implV2);

        assertEq(uint256(v2), 2);
        assertEq(resolver.addr(v2Node), implV2);
        assertEq(registrar.latestImplementation(appNode), implV2);
    }

    function testRegisterAppRevertsWhenSenderIsNotOrgAdmin() public {
        bytes32 orgNode = registrar.registerOrg("cork", ORG_ADMIN);

        vm.prank(ATTACKER);
        vm.expectRevert(abi.encodeWithSelector(VersioningRegistrar.Unauthorized.selector));
        registrar.registerApp("app", orgNode, proxy);
    }

    function testRegisterAppRevertsWhenProxyHasNoCode() public {
        bytes32 orgNode = registrar.registerOrg("cork", ORG_ADMIN);

        vm.prank(ORG_ADMIN);
        vm.expectRevert(abi.encodeWithSelector(VersioningRegistrar.ProxyHasNoCode.selector));
        registrar.registerApp("app", orgNode, ATTACKER);
    }

    function testPublishRevertsWhenImplementationHasNoCode() public {
        bytes32 orgNode = registrar.registerOrg("cork", ORG_ADMIN);

        vm.prank(ORG_ADMIN);
        bytes32 appNode = registrar.registerApp("app", orgNode, proxy);

        vm.prank(ORG_ADMIN);
        vm.expectRevert(abi.encodeWithSelector(VersioningRegistrar.ImplementationHasNoCode.selector));
        registrar.publishVersion(appNode, ATTACKER);
    }

    function testSetOrgAdminAndSetAppAdmin() public {
        bytes32 orgNode = registrar.registerOrg("cork", ORG_ADMIN);

        vm.prank(ORG_ADMIN);
        registrar.setOrgAdmin(orgNode, NEW_ORG_ADMIN);

        vm.prank(NEW_ORG_ADMIN);
        bytes32 appNode = registrar.registerApp("app", orgNode, proxy);

        vm.prank(NEW_ORG_ADMIN);
        registrar.setAppAdmin(appNode, APP_ADMIN);

        vm.prank(APP_ADMIN);
        (, uint64 newVersion) = registrar.publishVersion(appNode, implV1);
        assertEq(uint256(newVersion), 1);

        vm.prank(NEW_ORG_ADMIN);
        vm.expectRevert(abi.encodeWithSelector(VersioningRegistrar.Unauthorized.selector));
        registrar.publishVersion(appNode, implV2);
    }

    function testDuplicateOrgAndAppRegistrationReverts() public {
        bytes32 orgNode = registrar.registerOrg("cork", ORG_ADMIN);

        vm.expectRevert(abi.encodeWithSelector(VersioningRegistrar.OrgAlreadyRegistered.selector));
        registrar.registerOrg("cork", ORG_ADMIN);

        vm.prank(ORG_ADMIN);
        registrar.registerApp("app", orgNode, proxy);

        vm.prank(ORG_ADMIN);
        vm.expectRevert(abi.encodeWithSelector(VersioningRegistrar.AppAlreadyRegistered.selector));
        registrar.registerApp("app", orgNode, proxy);
    }

    function testInvalidLabelRejected() public {
        vm.expectRevert(abi.encodeWithSelector(VersioningRegistrar.InvalidLabelCharacter.selector));
        registrar.registerOrg("Cork", ORG_ADMIN);

        vm.expectRevert(abi.encodeWithSelector(VersioningRegistrar.LabelStartsOrEndsWithHyphen.selector));
        registrar.registerOrg("-cork", ORG_ADMIN);
    }

    function _deriveNode(bytes32 parentNode, bytes32 labelHash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(parentNode, labelHash));
    }
}
