// SPDX-License-Identifier: MIT
 
 

pragma solidity ^0.8.0;

import "./interface/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Faucet is Ownable {
    IERC20 public token0;
    IERC20 public token1;
    IERC20 public token2;
    IERC20 public token3;

    mapping(address => uint256) public timeFaucet;

    uint256 public lockhourPeriods;
    uint256 public amount0;
    uint256 public amount1;
    uint256 public amount2;
    uint256 public amount3;
    bool public isOpen;

    modifier onlyOpen() {
        require(isOpen, 'Facuet Close');
        _;
    }

    constructor(
        address _token0,
        address _token1,
        address _token2,
        address _token3,
        uint256 _amount0,
        uint256 _amount1,
        uint256 _amount2,
        uint256 _amount3,
        uint256 _lockhourPeriods
    ) {
        token0 = IERC20(_token0);
        token1 = IERC20(_token1);
        token2 = IERC20(_token2);
        token3 = IERC20(_token3);
        lockhourPeriods = _lockhourPeriods;
        amount0 = _amount0;
        amount1 = _amount1;
        amount2 = _amount2;
        amount3 = _amount3;
        isOpen = true;
    }

    function changeTimeFaucet(
        address user,
        uint256 newTime
    ) external onlyOwner {
        timeFaucet[user] = newTime;
    }

    function changeLockHourPeriods(
        uint256 _newlockhourPeriods
    ) external onlyOwner {
        lockhourPeriods = _newlockhourPeriods;
    }

    function changeAmountToken(
        uint256 _amount0,
        uint256 _amount1,
        uint256 _amount2,
        uint256 _amount3
    ) external onlyOwner {
        amount0 = _amount0;
        amount1 = _amount1;
        amount2 = _amount2;
        amount3 = _amount3;
    }

    function changeToken(
        address _token0,
        address _token1,
        address _token2,
        address _token3
    ) external onlyOwner {
        token0 = IERC20(_token0);
        token1 = IERC20(_token1);
        token2 = IERC20(_token2);
        token3 = IERC20(_token3);
    }

    function togleOpen() external onlyOwner {
        isOpen = !isOpen;
    }

    function withdrawToken(address _token) external onlyOwner {
        IERC20(_token).transfer(
            owner(),
            IERC20(_token).balanceOf(address(this))
        );
    }

    function getFaucet() external onlyOpen {
        if (timeFaucet[msg.sender] == 0) {
            timeFaucet[msg.sender] = block.timestamp;
        }
        require(
            timeFaucet[msg.sender] <= block.timestamp,
            'It is not time please wait'
        );
        timeFaucet[msg.sender] = block.timestamp + (60 * 60 * lockhourPeriods);
        token0.transfer(msg.sender, amount0);
        token1.transfer(msg.sender, amount1);
        token2.transfer(msg.sender, amount2);
        token3.transfer(msg.sender, amount3);
    }
}
