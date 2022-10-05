// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.1;
import "../library/SafeERC20.sol";
import "../interface/IERC20.sol";
import "../enums.sol";
import "hardhat/console.sol";
import "./EqualBets.sol";

contract HandicapBets is EqualBets {
    constructor(
        address _link,
        address _oracle,
        bytes32 _jobId,
        uint256 _fee
    ) EqualBets(_link, _oracle, _jobId, _fee) {}
}
