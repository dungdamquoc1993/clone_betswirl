// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.1;

import "./openzepplin/ERC20.sol";
import "./openzepplin/Ownable.sol";

contract BankLPToken is ERC20("Bank LP Token", "BLP") {
    address public bank;

    constructor() {
        bank = msg.sender;
    }

    // called once by the bank at time of deployment
    function initialize() external view {
        require(msg.sender == bank, "BankEbet: FORBIDDEN"); // sufficient check
    }

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlyOwner {
        _burn(from, amount);
    }
    function getOwner() external view returns (address) {
        return owner();
    }

    function transferByPool(
        address from,
        address to,
        uint256 amount
    ) external returns (bool) {
        address spender = address(this);
        _spendAllowance(from, spender, amount);
        _transfer(from, to, amount);
        return true;
    }
}
