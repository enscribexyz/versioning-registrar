// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface Vm {
    function prank(address sender) external;

    function startPrank(address sender) external;

    function stopPrank() external;

    function expectRevert(bytes calldata revertData) external;
}

contract TestBase {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function assertEq(address a, address b) internal pure {
        require(a == b, "assertEq(address)");
    }

    function assertEq(bytes32 a, bytes32 b) internal pure {
        require(a == b, "assertEq(bytes32)");
    }

    function assertEq(uint256 a, uint256 b) internal pure {
        require(a == b, "assertEq(uint256)");
    }
}
