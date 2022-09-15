// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.1;

import "./openzepplin/ERC20.sol";
import "./openzepplin/Ownable.sol";


contract EqualBetsToken is ERC20("EqualBets Token", "EBET"), Ownable {

    function mint(address account, uint256 amount) public onlyOwner {
        _mint(account, amount);
    }

    function getOwner() external view returns (address) {
        return owner();
    }

}



