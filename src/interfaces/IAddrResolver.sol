// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IAddrResolver {
    function setAddr(bytes32 node, address addr_) external;

    function addr(bytes32 node) external view returns (address);
}
