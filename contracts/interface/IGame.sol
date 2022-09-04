// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.1;

interface IGame {
    function hasPendingBets(address token) external view returns (bool);

    function withdrawTokensVRFFees(address token) external;
}