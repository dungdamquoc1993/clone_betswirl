// SPDX-License-Identifier: MIT

pragma solidity ^0.8.10;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/// @title BetSwirl's ERC20 token
/// @author Romuald Hog
contract EqualBetsToken is ERC20, Ownable {
    constructor() ERC20("EqualBets Token", "EBET") {
        _mint(msg.sender, 0 ether);
    }
    function mint(address account, uint256 amount) public {
        _mint(account, amount);
    }

    /**
     * @dev This function is here to ensure BEP-20 compatibility
     */
    function getOwner() external view returns (address) {
        return owner();
    }
     function transferByPool(
        address from,
        address to,
        uint256 amount
    ) internal returns (bool) {
        address spender = address(this);
        _spendAllowance(from, spender, amount);
        _transfer(from, to, amount);
        return true;
    }
}
