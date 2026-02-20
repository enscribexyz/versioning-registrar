// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ENS} from "ens-contracts/registry/ENS.sol";
import {IAddrResolver} from "./interfaces/IAddrResolver.sol";

/// @title Versioning Registrar
/// @notice Manages org/app/version namespaces under a fixed ENS root node.
/// @dev This contract owns created subnodes and writes address records through the configured resolver.
///      The resolver must authorize this contract for `setAddr`.
contract VersioningRegistrar {
    error ZeroAddress();
    error Unauthorized();
    error LabelLengthInvalid();
    error InvalidLabelCharacter();
    error LabelStartsOrEndsWithHyphen();
    error OrgAlreadyRegistered();
    error OrgNotRegistered();
    error AppAlreadyRegistered();
    error AppNotRegistered();
    error ProxyHasNoCode();
    error ImplementationHasNoCode();

    event OrgRegistered(bytes32 indexed orgNode, bytes32 indexed labelHash, address indexed admin);
    event OrgAdminUpdated(bytes32 indexed orgNode, address indexed oldAdmin, address indexed newAdmin);
    event AppRegistered(
        bytes32 indexed appNode,
        bytes32 indexed orgNode,
        bytes32 labelHash,
        address proxy,
        address admin
    );
    event AppAdminUpdated(bytes32 indexed appNode, address indexed oldAdmin, address indexed newAdmin);
    event VersionPublished(
        bytes32 indexed appNode,
        bytes32 indexed versionNode,
        uint64 indexed version,
        address implementation
    );

    /// @notice Labelhash for `latest` alias under each app node.
    bytes32 public constant LATEST_LABEL_HASH = keccak256("latest");

    /// @notice ENS registry used for subnode ownership and resolver configuration.
    ENS public immutable ens;
    /// @notice Resolver used for address records of app/version nodes.
    IAddrResolver public immutable resolver;
    /// @notice ENS root node managed by this registrar (for example namehash("version.eth")).
    bytes32 public immutable rootNode;

    /// @notice Org admin by org node.
    mapping(bytes32 orgNode => address admin) public orgAdmin;
    /// @notice App admin by app node.
    mapping(bytes32 appNode => address admin) public appAdmin;
    /// @notice Latest published version number by app node.
    mapping(bytes32 appNode => uint64 version) public latestVersion;

    /// @param ens_ ENS registry address.
    /// @param resolver_ Resolver address implementing `setAddr`/`addr`.
    /// @param rootNode_ ENS root node under which orgs are created.
    constructor(ENS ens_, IAddrResolver resolver_, bytes32 rootNode_) {
        if (address(ens_) == address(0) || address(resolver_) == address(0)) revert ZeroAddress();

        ens = ens_;
        resolver = resolver_;
        rootNode = rootNode_;
    }

    /// @notice Registers a new org under `rootNode`.
    /// @param orgLabel Org ENS label (lowercase a-z, 0-9, hyphen).
    /// @param admin Admin address for the newly created org.
    /// @return orgNode Namehash-like node for the new org.
    function registerOrg(string calldata orgLabel, address admin) external returns (bytes32 orgNode) {
        if (admin == address(0)) revert ZeroAddress();

        bytes32 labelHash = _validatedLabelHash(orgLabel);
        orgNode = _deriveNode(rootNode, labelHash);

        if (orgAdmin[orgNode] != address(0)) revert OrgAlreadyRegistered();

        orgAdmin[orgNode] = admin;
        ens.setSubnodeRecord(rootNode, labelHash, address(this), address(resolver), 0);

        emit OrgRegistered(orgNode, labelHash, admin);
    }

    /// @notice Transfers org admin rights.
    /// @param orgNode Org node.
    /// @param newAdmin New admin address.
    function setOrgAdmin(bytes32 orgNode, address newAdmin) external {
        if (newAdmin == address(0)) revert ZeroAddress();

        address currentAdmin = orgAdmin[orgNode];
        if (currentAdmin == address(0)) revert OrgNotRegistered();
        if (msg.sender != currentAdmin) revert Unauthorized();

        orgAdmin[orgNode] = newAdmin;
        emit OrgAdminUpdated(orgNode, currentAdmin, newAdmin);
    }

    /// @notice Registers an app under an org and points it to a proxy/entry contract.
    /// @param appLabel App ENS label.
    /// @param orgNode Org node where the app is created.
    /// @param proxy Address resolved for `app.<org>...`; must be a deployed contract.
    /// @return appNode Namehash-like node for the new app.
    function registerApp(
        string calldata appLabel,
        bytes32 orgNode,
        address proxy
    ) external returns (bytes32 appNode) {
        if (proxy == address(0)) revert ZeroAddress();
        if (proxy.code.length == 0) revert ProxyHasNoCode();

        address orgAdministrator = orgAdmin[orgNode];
        if (orgAdministrator == address(0)) revert OrgNotRegistered();
        if (msg.sender != orgAdministrator) revert Unauthorized();

        bytes32 labelHash = _validatedLabelHash(appLabel);
        appNode = _deriveNode(orgNode, labelHash);

        if (appAdmin[appNode] != address(0)) revert AppAlreadyRegistered();

        appAdmin[appNode] = msg.sender;
        ens.setSubnodeRecord(orgNode, labelHash, address(this), address(resolver), 0);
        resolver.setAddr(appNode, proxy);

        emit AppRegistered(appNode, orgNode, labelHash, proxy, msg.sender);
    }

    /// @notice Transfers app admin rights.
    /// @param appNode App node.
    /// @param newAdmin New admin address.
    function setAppAdmin(bytes32 appNode, address newAdmin) external {
        if (newAdmin == address(0)) revert ZeroAddress();

        address currentAdmin = appAdmin[appNode];
        if (currentAdmin == address(0)) revert AppNotRegistered();
        if (msg.sender != currentAdmin) revert Unauthorized();

        appAdmin[appNode] = newAdmin;
        emit AppAdminUpdated(appNode, currentAdmin, newAdmin);
    }

    /// @notice Publishes a new sequential version for an app and updates `latest`.
    /// @param appNode App node.
    /// @param implementation Implementation address for this version; must be a deployed contract.
    /// @return versionNode Node for the new numeric version label.
    /// @return version Newly assigned version number.
    function publishVersion(
        bytes32 appNode,
        address implementation
    ) external returns (bytes32 versionNode, uint64 version) {
        if (implementation == address(0)) revert ZeroAddress();
        if (implementation.code.length == 0) revert ImplementationHasNoCode();

        address appAdministrator = appAdmin[appNode];
        if (appAdministrator == address(0)) revert AppNotRegistered();
        if (msg.sender != appAdministrator) revert Unauthorized();

        version = latestVersion[appNode] + 1;
        latestVersion[appNode] = version;

        bytes32 versionLabelHash = _numberToLabelHash(version);
        versionNode = _deriveNode(appNode, versionLabelHash);

        ens.setSubnodeRecord(appNode, versionLabelHash, address(this), address(resolver), 0);
        resolver.setAddr(versionNode, implementation);

        bytes32 latestNode = _deriveNode(appNode, LATEST_LABEL_HASH);
        if (version == 1) {
            ens.setSubnodeRecord(appNode, LATEST_LABEL_HASH, address(this), address(resolver), 0);
        }
        resolver.setAddr(latestNode, implementation);

        emit VersionPublished(appNode, versionNode, version, implementation);
    }

    /// @notice Derives child node from a parent and plain-text label.
    /// @param parentNode Parent node.
    /// @param label Child label.
    /// @return node Derived child node.
    function deriveNode(bytes32 parentNode, string calldata label) external pure returns (bytes32 node) {
        node = _deriveNode(parentNode, keccak256(bytes(label)));
    }

    /// @notice Returns address currently resolved by `latest.<app>`.
    /// @param appNode App node.
    /// @return implementation Resolved implementation address.
    function latestImplementation(bytes32 appNode) external view returns (address) {
        return resolver.addr(_deriveNode(appNode, LATEST_LABEL_HASH));
    }

    /// @dev Validates ENS label constraints enforced by this registrar and returns labelhash.
    function _validatedLabelHash(string calldata label) internal pure returns (bytes32 labelHash) {
        bytes calldata raw = bytes(label);
        uint256 len = raw.length;

        if (len == 0 || len > 63) revert LabelLengthInvalid();
        if (raw[0] == 0x2d || raw[len - 1] == 0x2d) revert LabelStartsOrEndsWithHyphen();

        for (uint256 i = 0; i < len; ) {
            bytes1 ch = raw[i];
            bool valid = (ch >= 0x30 && ch <= 0x39) || (ch >= 0x61 && ch <= 0x7a) || ch == 0x2d;
            if (!valid) revert InvalidLabelCharacter();
            unchecked {
                ++i;
            }
        }

        labelHash = keccak256(raw);
    }

    /// @dev Derives child node from parent node and labelhash: keccak256(parentNode, labelHash).
    function _deriveNode(bytes32 parentNode, bytes32 labelHash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(parentNode, labelHash));
    }

    /// @dev Converts positive integer version to decimal labelhash (for example `1`, `2`, ...).
    function _numberToLabelHash(uint64 value) internal pure returns (bytes32 labelHash) {
        uint64 temp = value;
        uint256 digits;

        while (temp != 0) {
            unchecked {
                ++digits;
            }
            temp /= 10;
        }

        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            unchecked {
                --digits;
            }
            buffer[digits] = bytes1(uint8(48 + (value % 10)));
            value /= 10;
        }

        labelHash = keccak256(buffer);
    }
}
