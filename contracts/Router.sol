// SPDX-License-Identifier: MIT

 

pragma solidity ^0.8.0;
 
import "./interface/IERC20.sol";
import "./interface/IPair.sol";
import "./interface/IFactoryPair.sol";
import "./interface/IMainValueWallet.sol";
import "./interface/IPancakeRouter.sol";



contract Router {
    //=======================================
    //========= State Variables =============
    //=======================================

    struct TradeDescription {
        address srcToken;
        address dstToken;
        uint256 amountIn;
        uint256 amountOutMin;
        address payable to;
        address[] pool;
        address[] InToken;
        address[] OutToken;
        uint256[] amountInPath;
    }
    

    IPancakeRouter public router;
    IFactoryPair public factoryPair;
    IMainValueWallet public mainValueWallet;
  
    //=======================================
    //=============== Events ================
    //=======================================

    event PairCreated(
        address indexed token0,
        address indexed token1,
        address pair,
        uint256
    );

    
    constructor(address _router,address _factoryPair,address _mainValueWallet) {
        router = IPancakeRouter(_router);
        factoryPair = IFactoryPair(_factoryPair);
        mainValueWallet = IMainValueWallet(_mainValueWallet);
    }


    //=======================================
    //============ Functions ================
    //=======================================

    function trade( 
        address dstToken,
        uint256 amountOutMin,
        address payable to,
        uint256[] memory amountIn,
        address[][] memory path
    ) public {
        require( to != address(0),"Trade: to Address_zero");
        require( amountIn.length ==  path.length , "Trade: length amountIn,path must eq" );
        IERC20(path[0][0]).transferFrom(msg.sender,address(this),amountIn[0]);
 
        for (uint256 i; i < path.length; i++) {
            IERC20(path[i][0]).approve( address(router),amountIn[i]);
            router.swapExactTokensForTokens(
                amountIn[i],
                0,
                path[i],
                address(this),
                block.timestamp + 10000
            );
        }

        uint256 afterAmt = IERC20(dstToken).balanceOf(address(this));
        require(afterAmt >= amountOutMin,"Trade: amountOutMin");
        IERC20(dstToken).transfer(to,afterAmt);
    }

    function tradeExchange( 
        uint256 amountIn,
        address srcToken,
        address dstToken,
        uint256 amountOutMin,
        address payable to
    ) public   {
        require( to != address(0),"tradeExchange: to Address_zero");
        IERC20(srcToken).transferFrom(msg.sender,address(this),amountIn);
        IERC20(srcToken).approve(address(mainValueWallet),amountIn);
        mainValueWallet.deposit(amountIn,srcToken);
        IPair pair = IPair(factoryPair.getPair(srcToken,dstToken));
        require(address(pair) != address(0),"tradeExchange: pair Address_zero");
        uint8 isBuy = srcToken == pair.token1() ? 0 : 1;
        uint256 amtBeforeTrade = mainValueWallet.balancesSpot(address(this),dstToken);
        pair.createMarketOrder(isBuy, amountIn, 0);
        uint256 amtAfterTrade = mainValueWallet.balancesSpot(address(this),dstToken);

        uint256 amountOut = amtAfterTrade - amtBeforeTrade;
        require(amountOut >= amountOutMin,"tradeExchange: amountOutMin");
        mainValueWallet.withdraw(amountOut,dstToken);
        IERC20(dstToken).transfer(to,amountOut);
    }

    function tradeBoth(
        address srcToken,
        address dstToken,
        uint256 amountIn,
        uint256 amountOutMin,
        address payable to,
        uint256[] memory amountInPath,
        address[][] memory path
 
    ) external  {

        uint256 amtBeforeTrade = IERC20(dstToken).balanceOf(to);

        trade(   
         dstToken,
         0,
         to,
         amountInPath,
         path);

        tradeExchange(   
         amountIn,
         srcToken,
         dstToken,
         0,
         to
        );

        uint256 amtAfterTrade = IERC20(dstToken).balanceOf(to);
        require(amtAfterTrade - amtBeforeTrade>= amountOutMin,"tradeBoth: amountOutMin");

    }
}

 