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
    
    // address routerAddr = 0x10ED43C718714eb63d5aA57B78B54704E256024E;  
    // address rewardToken = 0xbA2aE424d960c26247Dd6c32edC70B295c744C43; 
    // address marketingWallet = 0xE1935F695D3BA9F9259C89E1Fc8732a347BB234a;
    // address buyback2lpWallet = 0xE1935F695D3BA9F9259C89E1Fc8732a347BB234a;

    
    address routerAddr = 0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff;  // polygon 0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff;
    address rewardToken = 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063; //polygon dai 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063;
    address marketingWallet = 0xD32e5c150b9Ca49506D6f04C5498B71e6fC9d027;
    address buyback2lpWallet = 0xD32e5c150b9Ca49506D6f04C5498B71e6fC9d027;
    
    IUniswapV2Pair public pair;
    IUniswapV2Router02 public router;
    
    uint internal maxTxAmount = totalSupply().mul(5) / 100; //5 percent of the supply (Anti Whale Measures)
    bool antiWhaleEnabled;
    
	uint internal minTokensBeforeSwap = 200; // 2 billion (no decimal adjustment)
    uint internal minTokensForRewards = 20000; // in tokens (no decimal adjustment)
 
    uint internal buyFee = 13; // percent fee for buying, goes towards rewards
    uint internal sellFee = 14; // percent fee for selling, goes towards rewards
    uint internal buybackfee = 4; // percent fee for selling, goes towards rewards
    uint internal marketingTax = 15; // Once all fees are accumulated and swapped, what percent goes towards marketing
    
    
    uint internal _minTokensBeforeSwap = minTokensBeforeSwap * 10 ** decimals();
    uint internal _minTokensForRewards = minTokensForRewards * 10 ** decimals();
    
    
    mapping (address => bool) public excludedFromRewards;
	mapping (address => bool) public excludedFromFees;
	
	bool swapEnable;
	

	uint private _swapPeriod = 60;
    uint private swapTime = block.timestamp + _swapPeriod;
    
	mapping (address => bool) public whitelisted;
	mapping (address => uint) public index; // Useful for predicting how long until next payout
	address[] public addresses;
	mapping(address => uint) addressIndex;
	
	address public owner ;

    

    uint withdrawnDividendTimePeriod = 60;
    
    uint withdrawnDividendTime = block.timestamp + withdrawnDividendTimePeriod;
    
	uint public totalHolders;
    
    
    
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
        excludedFromRewards[msg.sender] = true;
        
        excludedFromFees[marketingWallet] = true;
		excludedFromFees[address(this)] = true;

        _approve(address(this), routerAddr, 10000000 * 10** 18);
        _approve(address(this), msg.sender, 10000000 * 10** 18);
        
        addresses.push(address(0));

    }  
    
    function changeMinTokensBeforeSwap(uint256 newminTokensBeforeSwap) public onlyOwner {
        minTokensBeforeSwap = newminTokensBeforeSwap;
    }
    
    function setExcludedFromRewards(address add, bool status) public onlyOwner {
        excludedFromRewards[add] = status;
    }
    
    function setExcludedFromFees(address add, bool status) public onlyOwner {
        excludedFromFees[add] = status;
    }
    
    function setSwapPeriod(uint256 period) public onlyOwner {
        _swapPeriod = period;
    }
    
    function setWithdrawnDividendTimePeriod(uint256 period) public onlyOwner {
        withdrawnDividendTimePeriod = period;
    }
    
    function setOpenSwap(bool status) public onlyOwner {
        swapEnable = status;
    }
    
    function setAntiWhale(bool status) public onlyOwner {
        antiWhaleEnabled = status;
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
			uint buyfeeAmount = value.mul(buyFee) / 100;
			uint buybackfeeAmount = value.mul(buybackfee) / 100;

			// Anti-Whaling
			if (to == address(pair) && antiWhaleEnabled) {
				require(value < maxTxAmount, 'Anti-Whale: Can not sell more than maxTxAmount');
				buyfeeAmount = value.mul(sellFee) / 100;
			}
			
			require(buyfeeAmount > 0, 'Fees are zero');

			if (from != address(pair) && to != address(pair)) {
			    buyfeeAmount = 0; // Don't tax on wallet to wallet transfers, only buy/sell
			    buybackfeeAmount = 0;
			} else {
			    if (swapTime <= block.timestamp && from != owner && to != owner && swapEnable) {	
                    _swap();
        			swapTime = block.timestamp + _swapPeriod;
                }
			}
			uint tokensToAdd = value.sub(buyfeeAmount).sub(buybackfeeAmount);
			require(tokensToAdd > 0, 'After fees, received amount is zero');
        
			// Update balances
			_balances[address(this)] = _balances[address(this)].add(buyfeeAmount);
			_balances[buyback2lpWallet] = _balances[buyback2lpWallet].add(buybackfeeAmount);
			_balances[from] = balanceOfFrom.sub(value);
			_balances[to] = _balances[to].add(tokensToAdd);
			
			if(addressIndex[to] == 0 && _balances[to] >= _minTokensForRewards) {
			    totalHolders ++;
			    addressIndex[to] = totalHolders;
			    addresses.push(to);
			}
			
			if(addressIndex[from] > 0 && _balances[from] < _minTokensForRewards) {
			    uint _index = addressIndex[from];
			    delete addresses[_index];
			}
			
		}

        emit Transfer(from, to, value);
    }
    bool swapping; 
    
    modifier swapLock() {
		swapping = true;
		_;
		swapping = false;
	}
	
	/**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(owner == _msgSender(), "Ownable: caller is not the owner");
        _;
    }
    
    event SwapLog(uint daibalance);
    
    function _swap() public swapLock {
        uint tokensToSwap = _balances[address(this)];
        uint tokensOfPair = _balances[address(pair)];
        
        if(tokensToSwap <= _minTokensBeforeSwap) {
            return ;
        }
        
        uint maxSwapTokenAmount = tokensOfPair/ 1000;
        if(tokensToSwap > maxSwapTokenAmount) {
            tokensToSwap = maxSwapTokenAmount;
        }
        if(_minTokensBeforeSwap > 0 && tokensToSwap > _minTokensBeforeSwap) {
            tokensToSwap = _minTokensBeforeSwap;
        }
        
        emit SwapLog(tokensToSwap);
		address[] memory bnbPath = new address[](2);
		bnbPath[0] = address(this);
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
	
	function destroy() public onlyOwner {
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
            withdrawnDividendTime = block.timestamp + withdrawnDividendTimePeriod;
            withdrawnDividend();
        }
		
	}
	
	event withdrawnDividendLog(uint indexed denominator, uint totalRewardAmount);
	
	function withdrawnDividend() private {
	    uint excludedAmount = _balances[address(this)].add(_balances[owner]);
	    excludedAmount = excludedAmount.add(_balances[address(router)]).add(_balances[address(pair)]);
	    
	    uint denominator = totalSupply().sub(excludedAmount);
	    
	    if(denominator == 0) {
	        return;
	    }
	    
	    uint split;
	    uint totalRewardAmount = ERC20(rewardToken).balanceOf(address(this));
	    emit withdrawnDividendLog(denominator, totalRewardAmount);
	    
	    uint i;
	    for(uint k = 0; k < totalHolders ; k++) {
	        i = k + 1;
	        address _rewardAddress = addresses[i];
	        if(_rewardAddress == address(0)) {
	            continue;
	        }
	        
	        if(_balances[_rewardAddress] < _minTokensForRewards) {
	            continue;
	        }
	        
	        if(excludedFromRewards[_rewardAddress]) {
	            continue;
	        }
	        
	        uint reward = _balances[_rewardAddress].mul(totalRewardAmount).div(denominator);
	        split += reward;
	        if(split > totalRewardAmount) {
	            break;
	        }

	        IERC20(rewardToken).transfer(_rewardAddress, reward);
	    }
	}
	
	function Distru() public {
	    withdrawnDividend();
	}
	
	
	event LogWithdraw(uint balance, bool withdaw);
	function withdrawDai() public returns(bool) {
	    uint balance = ERC20(rewardToken).balanceOf(address(this));
	    bool success = IERC20(rewardToken).transfer(msg.sender, balance);
	    
	    emit LogWithdraw(balance, success);
	    
	    return success;
	}
	
	event ExcludeAmountLog(uint indexed excludedAmount, uint denominator, uint totalRewardAmount, uint reward1, uint reward2);
	
	function getExcludeAmount() public returns(uint, uint) {
	    uint excludedAmount = _balances[address(this)].add(_balances[owner]);
	    excludedAmount = excludedAmount.add(_balances[address(router)]).add(_balances[address(pair)]);
	    
	    uint denominator = totalSupply().sub(excludedAmount);
	    
	    
	    
	    uint totalRewardAmount = ERC20(rewardToken).balanceOf(address(this));
	    uint reward1 = _balances[addresses[1]].mul(totalRewardAmount).div(denominator);
	    uint reward2 = _balances[addresses[2]].mul(totalRewardAmount).div(denominator);
	    
	    emit ExcludeAmountLog(excludedAmount, denominator, totalRewardAmount, reward1, reward2);
	    
	    return (excludedAmount, denominator);
	}
}
    
//100000000000000000000000
//50000  000000000000000000
//100000 000000000000000000
//99999  000000000000000000
//      1000000000000000000
//237148054949406100
//237143312083164436
    
