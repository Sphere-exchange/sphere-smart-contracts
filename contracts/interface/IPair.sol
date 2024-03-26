// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IPair {

    function token0() external view returns (address);

    function token1() external view returns (address);
    
    function price() external view returns (uint256);

    function createMarketOrder(uint8 _isBuy,uint256 amount,uint256 _price ) external;
}
