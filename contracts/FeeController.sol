// SPDX-License-Identifier: MIT
 

pragma solidity ^0.8.0;

import './interface/IFactoryPair.sol';
import './interface/IMainValueWallet.sol';
import './interface/IPair.sol';
import './interface/ISettingExchange.sol';
import '@openzeppelin/contracts/access/Ownable.sol';

contract FeeController is Ownable {
    //=======================================
    //========= State Variables =============
    //=======================================

    IFactoryPair public factoryPair;
    IMainValueWallet public mainValueWallet;
    ISettingExchange public settingExchange;

    struct TickFee {
        uint256 upperTickPrice;
        uint256 lowerTickPrice;
    }

    struct InfoFee {
        uint256 finishAt;
        uint256 updatedAt;
        uint256 rewardRate;
        uint256 rewardPerTokenStored;
        mapping(address => uint256) userRewardPerTokenPaid;
        mapping(address => uint256) rewards;
        uint256 totalSupply;
        mapping(address => uint256) balanceOf;
        mapping(address => bool) defaultOwnerStake;
    }

    mapping(address => mapping(uint8 => mapping(uint256 => InfoFee))) public infoFee;

    mapping(address => uint256) public currentTickFee;

    mapping(address => mapping(uint256 => TickFee)) public infoTickFee;

    constructor(address _mainValueWallet, address _settingExchange) {
        mainValueWallet = IMainValueWallet(_mainValueWallet);
        settingExchange = ISettingExchange(_settingExchange);
    }

    //=======================================
    //=============== modifier  =============
    //=======================================

    modifier validCaller(address _pair) {
        require(
            factoryPair.getPair(
                IPair(_pair).token0(),
                IPair(_pair).token1()
            ) == msg.sender,
            'invalid caller'
        );
        _;
    }

    //=======================================
    //================ Functions ============
    //=======================================

    function createPosition(
        uint256 _amount,
        uint256 _price,
        address _user,
        address _pair,
        uint8 _isBuy,
        uint256 tickFeeID,
        bool craeteTickFeeID
    ) external validCaller(_pair) returns (uint256) {
        _updateReward(_user, _pair, _isBuy, tickFeeID);
        require(_amount > 0, 'amount = 0');
        uint256 _currentTickFee = currentTickFee[_pair];
        if (_currentTickFee == 0) {
            // First time no price yet
            tickFeeID = 0;
        } else {
            if (craeteTickFeeID) {
                tickFeeID = _updateTickFee(_pair, _price, false);
            }
            require(
                _verifyTickFee(_pair, _price, tickFeeID),
                'tickFeeID not correct'
            );
        }
        infoFee[_pair][_isBuy][tickFeeID].totalSupply += _amount;
        infoFee[_pair][_isBuy][tickFeeID].balanceOf[_user]  += _amount;

        // default set feeController stake 1
        address feeController = settingExchange.FeeCollector();
        if (!infoFee[_pair][_isBuy][tickFeeID].defaultOwnerStake[feeController]) {
            infoFee[_pair][_isBuy][tickFeeID].defaultOwnerStake[feeController] = true;
            infoFee[_pair][_isBuy][tickFeeID].totalSupply += 1;
            infoFee[_pair][_isBuy][tickFeeID].balanceOf[feeController] += 1;
        }
        emit Staked(_pair, _amount, _user, _isBuy);
        return tickFeeID;
    }

    function withdrawnPosition(
        uint256 _amount,
        address _user,
        address _pair,
        uint8 _isBuy,
        uint256 tickFeeID
    ) external validCaller(_pair) {
        _updateReward(_user, _pair, _isBuy, tickFeeID);
        require(_amount > 0, 'amount = 0');
        require(
            infoFee[_pair][_isBuy][tickFeeID].balanceOf[_user] >= _amount,
            'balance insufficient'
        );
        infoFee[_pair][_isBuy][tickFeeID].balanceOf[_user] -= _amount;
        infoFee[_pair][_isBuy][tickFeeID].totalSupply -= _amount;
        emit Withdrawn(msg.sender, _amount, _user, _isBuy);
    }

    function claimFee(address _pair, uint8 _isBuy, uint256 tickFeeID) external {
        require(_isBuy <= 1, 'invalid input isBuy');
        _updateReward(msg.sender, _pair, _isBuy, tickFeeID);
        uint256 reward = infoFee[_pair][_isBuy][tickFeeID].rewards[msg.sender];
        require(reward > 0, 'reward = 0');
        address addressReward = getAddressReward(_pair, _isBuy);
        infoFee[_pair][_isBuy][tickFeeID].rewards[msg.sender] = 0;

        mainValueWallet.decreaseBalancesSpotFee(
            reward,
            address(this),
            addressReward
        );
        mainValueWallet.increaseBalancesSpotFee(
            reward,
            msg.sender,
            addressReward
        );
        // rewardsToken.safeTransfer(msg.sender, reward);
        emit ClaimFee(msg.sender, reward, msg.sender, _isBuy);
    }

    function collectFeeReward(
        address _pair,
        uint256[2] calldata _amount,
        uint8[2] calldata _isBuy
    ) external validCaller(_pair) {
        uint256 tickFeeID = currentTickFee[_pair];
        if (tickFeeID == 0) {
            // First time
            tickFeeID = 2 ** 256 / 2;
            currentTickFee[_pair] = tickFeeID;
            uint256 currentPrice = IPair(_pair).price();
            infoTickFee[_pair][tickFeeID] = TickFee(
                (currentPrice * 105) / 100, // 5% up from current price
                (currentPrice * 95) / 100 // 5% down from current price
            );
        } else {
            _updateTickFee(_pair, IPair(_pair).price(), true);
        }
        _updateReward(address(0), _pair, _isBuy[0], tickFeeID);
        _updateReward(address(0), _pair, _isBuy[1], tickFeeID);

        uint256 duration = settingExchange.durationPaidFee();

        for (uint256 i = 0; i < _amount.length; i++) {
            if (block.timestamp >=  infoFee[_pair][_isBuy[i]][tickFeeID].finishAt) {
                infoFee[_pair][_isBuy[i]][tickFeeID].rewardRate = _amount[i] / duration;
            } else {
                uint256 remainingRewards = (infoFee[_pair][_isBuy[i]][tickFeeID].finishAt - block.timestamp) * infoFee[_pair][_isBuy[i]][tickFeeID].rewardRate;
                 infoFee[_pair][_isBuy[i]][tickFeeID].rewardRate =
                    (_amount[i] + remainingRewards) /
                    duration;
            }

            require(
                infoFee[_pair][_isBuy[i]][tickFeeID].rewardRate > 0,
                'reward rate = 0'
            );
            require(
                infoFee[_pair][_isBuy[i]][tickFeeID].rewardRate * duration <=
                    mainValueWallet.balancesSpot(
                        address(this),
                        getAddressReward(_pair, _isBuy[i])
                    ),
                'reward amount > balance'
            );

             infoFee[_pair][_isBuy[i]][tickFeeID].finishAt = block.timestamp + duration;
             infoFee[_pair][_isBuy[i]][tickFeeID].updatedAt = block.timestamp;

            emit CollectFeeReward(_amount[i], _pair, _isBuy[i]);
        }
    }

    function _updateReward(
        address _account,
        address _pair,
        uint8 _isBuy,
        uint256 tickFeeID
    ) internal {
        infoFee[_pair][_isBuy][tickFeeID].rewardPerTokenStored = rewardPerToken(
            _pair,
            _isBuy,
            tickFeeID
        );
        infoFee[_pair][_isBuy][tickFeeID].updatedAt = lastTimeRewardApplicable(
            _pair,
            _isBuy,
            tickFeeID
        );

        if (_account != address(0)) {
            infoFee[_pair][_isBuy][tickFeeID].rewards[_account] = earned(
                _account,
                _pair,
                _isBuy,
                tickFeeID
            );
            infoFee[_pair][_isBuy][tickFeeID].userRewardPerTokenPaid[_account] =  infoFee[_pair][_isBuy][tickFeeID].rewardPerTokenStored;
        }
    }

    function _updateTickFee(
        address _pair,
        uint256 _price,
        bool updateCurrentTickFee
    ) internal returns (uint256) {
        uint256 tickFeeID = currentTickFee[_pair];
        TickFee memory tickFee = infoTickFee[_pair][tickFeeID];
        // out of range fee
        while (
            tickFee.upperTickPrice < _price || _price < tickFee.lowerTickPrice
        ) {
            // up
            if (_price > tickFee.upperTickPrice) {
                tickFeeID++;
                TickFee memory tempTickFee = infoTickFee[_pair][tickFeeID];
                // check first time tickFee
                if (
                    tempTickFee.upperTickPrice == 0 &&
                    tempTickFee.lowerTickPrice == 0
                ) {
                    //  First time tickFee
                    infoTickFee[_pair][tickFeeID] = TickFee(
                        (tickFee.upperTickPrice * 110) / 100, // 5% up from current price
                        tickFee.upperTickPrice // 5% down from current price
                    );
                }
                // down
            } else if (_price < tickFee.lowerTickPrice) {
                tickFeeID--;
                TickFee memory tempTickFee = infoTickFee[_pair][tickFeeID];
                // check first time tickFee
                if (
                    tempTickFee.upperTickPrice == 0 &&
                    tempTickFee.lowerTickPrice == 0
                ) {
                    //  First time tickFee
                    infoTickFee[_pair][tickFeeID] = TickFee(
                        tickFee.lowerTickPrice, // 5% up from current price
                        (tickFee.lowerTickPrice * 100) / 110 // 5% down from current price
                    );
                }
            }

            tickFee = infoTickFee[_pair][tickFeeID];
        }
        if (updateCurrentTickFee) {
            currentTickFee[_pair] = tickFeeID;
        }
        return tickFeeID;
    }

    //=======================================
    //=========== View Functions ============
    //=======================================

    function findTickFeeByPrice(
        address _pair,
        uint256 _price
    ) public view returns (bool, uint256) {
        require(_price > 0, 'price = 0');
        uint256 tickFeeID = currentTickFee[_pair];
        TickFee memory tickFee = infoTickFee[_pair][tickFeeID];

        while (
            tickFee.upperTickPrice < _price || _price < tickFee.lowerTickPrice
        ) {
            // up
            if (_price > tickFee.upperTickPrice) {
                tickFeeID++;
                // down
            } else if (_price < tickFee.lowerTickPrice) {
                tickFeeID--;
            }

            tickFee = infoTickFee[_pair][tickFeeID];
            if (tickFee.upperTickPrice == 0 && tickFee.lowerTickPrice == 0) {
                // not create yet
                return (false, tickFeeID);
            }
        }
        return (true, tickFeeID);
    }

    function _verifyTickFee(
        address _pair,
        uint256 _price,
        uint256 tickFeeID
    ) private view returns (bool) {
        TickFee memory tickFee = infoTickFee[_pair][tickFeeID];
        return (tickFee.upperTickPrice >= _price &&
            tickFee.lowerTickPrice <= _price);
    }

    function getAddressReward(
        address _pair,
        uint8 _isBuy
    ) private view returns (address) {
        return
            _isBuy == 0
                ? IPair(_pair).token0()
                : IPair(_pair).token1();
    }

    function lastTimeRewardApplicable(
        address _pair,
        uint8 _isBuy,
        uint256 tickFeeID
    ) public view returns (uint256) {
        return _min( infoFee[_pair][_isBuy][tickFeeID].finishAt, block.timestamp);
    }

    function rewardPerToken(
        address _pair,
        uint8 _isBuy,
        uint256 tickFeeID
    ) public view returns (uint256) {
        if ( infoFee[_pair][_isBuy][tickFeeID].totalSupply == 0) {
            return infoFee[_pair][_isBuy][tickFeeID].rewardPerTokenStored;
        }

        return
            infoFee[_pair][_isBuy][tickFeeID].rewardPerTokenStored +
            ( infoFee[_pair][_isBuy][tickFeeID].rewardRate *
                (lastTimeRewardApplicable(_pair, _isBuy, tickFeeID) -
                     infoFee[_pair][_isBuy][tickFeeID].updatedAt) *
                1e18) /
            infoFee[_pair][_isBuy][tickFeeID].totalSupply;
    }

    function earned(
        address _account,
        address _pair,
        uint8 _isBuy,
        uint256 tickFeeID
    ) public view returns (uint256) {
        return
            (( infoFee[_pair][_isBuy][tickFeeID].balanceOf[_account] *
                (rewardPerToken(_pair, _isBuy, tickFeeID) -  infoFee[_pair][_isBuy][tickFeeID].userRewardPerTokenPaid[ _account])) / 1e18) + infoFee[_pair][_isBuy][tickFeeID].rewards[_account];
    }

    function _min(uint256 x, uint256 y) private pure returns (uint256) {
        return x <= y ? x : y;
    }

    function setFactoryPair(address _factoryPair) public onlyOwner {
        factoryPair = IFactoryPair(_factoryPair);
    }

    /* ========== EVENTS ========== */

    event CollectFeeReward(uint256 reward, address pair, uint8 isBuy);
    event Staked(
        address indexed user,
        uint256 amount,
        address pair,
        uint8 isBuy
    );
    event Withdrawn(
        address indexed user,
        uint256 amount,
        address pair,
        uint8 isBuy
    );
    event ClaimFee(
        address indexed user,
        uint256 reward,
        address pair,
        uint8 isBuy
    );
}
