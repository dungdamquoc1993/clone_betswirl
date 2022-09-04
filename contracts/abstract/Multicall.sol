// SPDX-License-Identifier: UNLICENSED
import "../library/Address.sol";

pragma solidity ^0.8.1;


abstract contract Multicall {
    function multicall(bytes[] calldata data)
        external
        virtual
        returns (bytes[] memory results)
    {
        results = new bytes[](data.length);
        for (uint256 i = 0; i < data.length; i++) {
            results[i] = Address.functionDelegateCall(address(this), data[i]);
        }
        return results;
    }
}