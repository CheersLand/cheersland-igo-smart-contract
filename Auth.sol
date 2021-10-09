// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0 <0.9.0;

import '@openzeppelin/contracts/GSN/Context.sol';
import '@openzeppelin/contracts/access/Ownable.sol';

contract Auth is Context, Ownable {

    mapping(address => bool) public authMap;
    event AddAuth(address addr);
    event RemoveAuth(address addr);

    constructor() internal {
        authMap[_msgSender()] = true;
    }

    modifier onlyOperator() {
        require(
            authMap[_msgSender()],
            'Auth: caller is not the operator'
        );
        _;
    }

    function isOperator(address addr) public view returns (bool) {
        return authMap[addr];
    }

    function addAuth(address addr) public onlyOwner {
        require(addr != address(0), "Auth: addr can not be 0x0");
        authMap[addr] = true;
        emit AddAuth(addr);
    }

    function removeAuth(address addr) public onlyOwner {
        require(addr != address(0), "Auth: addr can not be 0x0");
        authMap[addr] = false;
        emit RemoveAuth(addr);
    }

}
