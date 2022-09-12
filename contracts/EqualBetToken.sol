// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.1;

import "./openzepplin/ERC20.sol";

contract CakeToken is ERC20('PancakeSwap Token', 'Cake'){
    function mint(address _to, uint256 _amount) public onlyOwner {
        _mint(_to, _amount);
    }
}
