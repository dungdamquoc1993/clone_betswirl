// SPDX-License-Identifier: UNLICENSED
import "./IERC20.sol";
pragma solidity ^0.8.1;


interface IERC20Metadata is IERC20 {
  
    function name() external view returns (string memory);

    function symbol() external view returns (string memory);

    function decimals() external view returns (uint8);
}