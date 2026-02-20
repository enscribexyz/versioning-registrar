// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract SimpleOwnable {
    error NotOwner();
    error NewOwnerIsZeroAddress();

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event ValueUpdated(uint256 indexed newValue);

    address public owner;
    uint256 public value;

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor(address initialOwner) {
        if (initialOwner == address(0)) revert NewOwnerIsZeroAddress();
        owner = initialOwner;
        emit OwnershipTransferred(address(0), initialOwner);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert NewOwnerIsZeroAddress();

        address previousOwner = owner;
        owner = newOwner;
        emit OwnershipTransferred(previousOwner, newOwner);
    }

    function setValue(uint256 newValue) external onlyOwner {
        value = newValue;
        emit ValueUpdated(newValue);
    }
}
