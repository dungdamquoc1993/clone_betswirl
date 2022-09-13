// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.1;
import "../openzepplin/Ownable.sol";
import "../interface/IERC20.sol";

interface IBankLPToken is IERC20 {
    function initialize() external;

    function getOwner() external view returns (address);

    function transferByPool(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);

    function mint(address to, uint256 amount) external;

    function burn(address from, uint256 amount) external;

    function totalSupply() external view returns (uint256);

    function balanceOf() external view returns (uint256);

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);
}
