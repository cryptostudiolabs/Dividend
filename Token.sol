// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./ERC20.sol";
import "./IUniswapV2Factory.sol";
import "./IUniswapV2Router02.sol";
import "./IUniswapV2Pair.sol";
import "./SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";


/**
 * @dev Implementation of the {IERC20} interface.
 */
contract TX is ERC20 {
    
    using SafeMath for uint;
    using Address for address;
    
    address routerAddr = 0x10ED43C718714eb63d5aA57B78B54704E256024E;  // polygon 0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff;
    address rewardToken = 0xbA2aE424d960c26247Dd6c32edC70B295c744C43; //polygon dai 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063;
    address marketingWallet = 0xD32e5c150b9Ca49506D6f04C5498B71e6fC9d027;
    address back2lpWallet = 0xD32e5c150b9Ca49506D6f04C5498B71e6fC9d027;
    
    IUniswapV2Pair public pair;
    IUniswapV2Router02 public router;
    
    uint internal maxTxAmount = totalSupply().mul(5) / 100; //5 percent of the supply (Anti Whale Measures)
    bool antiWhaleEnabled;
    
	uint internal minTokensBeforeSwap = 2000; // 2 billion (no decimal adjustment)
    uint internal minTokensForRewards = 2000; // in tokens (no decimal adjustment)
 
    uint internal buyFee = 17; // percent fee for buying, goes towards rewards
    uint internal sellFee = 17; // percent fee for selling, goes towards rewards
    uint internal marketingTax = 20; // Once all fees are accumulated and swapped, what percent goes towards marketing
    
    
    uint internal _minTokensBeforeSwap = minTokensBeforeSwap * 10 ** decimals();
    uint internal _minTokensForRewards = minTokensForRewards * 10 ** decimals();
    
    
    mapping (address => bool) public excludedFromRewards;
	mapping (address => bool) public excludedFromFees;
	

	uint private _swapPeriod = 60;
    uint private swapTime = block.timestamp + _swapPeriod;
    
    uint minTokenAmountBeforeReward;
    
	mapping (address => bool) public whitelisted;
	mapping (address => uint) public index; // Useful for predicting how long until next payout
	address[] public addresses;
	
	address owner ;

    

    uint withdrawnDividendTimePeriod = 60;
    
    uint withdrawnDividendTime = block.timestamp + withdrawnDividendTimePeriod;
    
	uint totalHolders;
    
    
    
    constructor(string memory _name, string memory _symble) ERC20(_name, _symble) {
        _mint(msg.sender, 10000000 * 10** 18);
        
        router = IUniswapV2Router02(routerAddr);
        
		IUniswapV2Factory factory = IUniswapV2Factory(router.factory());
		address pairAddr = factory.createPair(address(this), router.WETH());
		pair = IUniswapV2Pair(pairAddr);
		
		owner = msg.sender;
		

	    excludedFromRewards[marketingWallet] = true;
        excludedFromRewards[address(router)] = true;
        excludedFromRewards[address(pair)] = true;
        excludedFromRewards[address(this)] = true;
        
        excludedFromFees[marketingWallet] = true;
		excludedFromFees[address(this)] = true;
    }  
    
    
    function _transfer(
        address from,
        address to,
        uint256 value
    ) internal virtual override {
        require(value > 0, 'Insufficient transfer amount');
		uint balanceOfFrom = _balances[from];

        require(value <= balanceOfFrom, 'Insufficient token balance');
        
        uint allowance = _allowances[from][msg.sender];

        if (from != msg.sender && allowance != type(uint).max) {
            require(value <= allowance);
            allowance = allowance.sub(value);
        }

		if (excludedFromFees[from] || excludedFromFees[to]) {
			_balances[from] = balanceOfFrom.sub(value);
			_balances[to] = _balances[to].add(value);
		} else {
			uint feeAmount = value.mul(buyFee) / 100;

			// Anti-Whaling
			if (to == address(pair) && antiWhaleEnabled) {
				require(value < maxTxAmount, 'Anti-Whale: Can not sell more than maxTxAmount');
				feeAmount = value.mul(sellFee) / 100;
			}
			
			require(feeAmount > 0, 'Fees are zero');

			if (from != address(pair) && to != address(pair)) feeAmount = 0; // Don't tax on wallet to wallet transfers, only buy/sell

			uint tokensToAdd = value.sub(feeAmount);
			require(tokensToAdd > 0, 'After fees, received amount is zero');

			// Update balances
			_balances[address(this)] = _balances[address(this)].add(feeAmount);
			_balances[from] = balanceOfFrom.sub(value);
			_balances[to] = _balances[to].add(tokensToAdd);
		}
		
		if (!excludedFromRewards[to] && _balances[to] >= minTokensForRewards) {
		    addresses.push(to);
		    totalHolders = addresses.length;
		}

        if (swapTime <= block.timestamp && (from != owner || to != owner)) {	
            _swap();
			swapTime += _swapPeriod;
        }

        emit Transfer(from, to, value);
    }
    bool swapping; 
    
    modifier swapLock() {
		swapping = true;
		_;
		swapping = false;
	}
    
    event SwapLog(uint daibalance);
    function _swap() public swapLock {
        address Doge = 0xbA2aE424d960c26247Dd6c32edC70B295c744C43;
       // uint tokensToSwap = _balances[address(this)];
        uint tokensToSwap = IERC20(Doge).balanceOf(address(this));
        IERC20(Doge).approve(address(router), tokensToSwap);
        
        if(tokensToSwap > minTokenAmountBeforeReward) {
            return ;
        }
        emit SwapLog(tokensToSwap);
		address[] memory bnbPath = new address[](2);
		bnbPath[0] = Doge;
		bnbPath[1] = router.WETH();
        
        // make the swap
        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokensToSwap,
            0,
            bnbPath,
            address(this),
            block.timestamp
        );
	}
	
// Make sure we can receive eth to the contract
	fallback() external payable {}


	//收到bnb触发分红
	receive() external payable {
		_distribute(msg.value);
	}
	
	function destroy() public {
		selfdestruct(payable(msg.sender));
	}
    
    function _distribute(uint deltaBalance) internal {
		uint marketingFee = deltaBalance.mul(marketingTax) / 100;
		payable(marketingWallet).transfer(marketingFee);

		uint percentLeft = uint(100).sub(marketingTax);

		uint amountToBuy = deltaBalance.mul(percentLeft) / 100;
		
	
        address[] memory tokenPath = new address[](2);
        tokenPath[0] = router.WETH();
        tokenPath[1] = rewardToken;
        
        router.swapExactETHForTokensSupportingFeeOnTransferTokens{ value: amountToBuy }(
        	0,
        	tokenPath,
        	address(this),
        	block.timestamp
        );
        if(withdrawnDividendTime <= block.timestamp) {
            withdrawnDividendTime += withdrawnDividendTimePeriod;
            withdrawnDividend();
        }
		
	}
	
	function withdrawnDividend() private {
	    uint excludedAmount = _balances[address(this)].add(_balances[marketingWallet]);
	    excludedAmount = excludedAmount.add(_balances[address(router)]).add(_balances[address(pair)]);
	    
	    uint totalRewardAmount = ERC20(rewardToken).balanceOf(address(this));
	    
	    for(uint i = 0; i < totalHolders ; i++) {
	        uint rewardAmount =  _balances[addresses[i]].div(excludedAmount);

	        IERC20(rewardToken).transfer(addresses[i], rewardAmount.mul(totalRewardAmount));
	    }
	}
	
	event LogWithdraw(uint balance, bool withdaw);
	function withdrawDai() public returns(bool) {
	    uint balance = ERC20(rewardToken).balanceOf(address(this));
	    bool success = IERC20(rewardToken).transfer(msg.sender, balance);
	    
	    emit LogWithdraw(balance, success);
	    
	    return success;
	}
}
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
