contract ChibaInu is Context, IBEP20, Ownable {
    mapping (address => uint256) private _rOwned;
    mapping (address => uint256) private _tOwned;
    mapping (address => bool) private _isExcludedFromFee;
    mapping (address => bool) private _isExcluded;
    mapping (address => mapping (address => uint256)) private _allowances;
    mapping (address => bool) public _isExcludedFromAutoLiquidity;
    mapping (address => bool) public _isExcludedFromAntiWhale;
    mapping (address => bool) public _isExcludedFromBuy;
    mapping (address => bool) public _isExcludedFromMaxTx;

    address[] private _excluded;
    address private _teamWallet;
    address private _marketingWallet;

    address public constant _burnAddress = 0x000000000000000000000000000000000000dEaD;

    uint256 private constant MAX = ~uint256(0);
    uint256 private _tTotal = 10000000 * 10**9;
    uint256 private _rTotal = (MAX - (MAX % _tTotal));
    uint256 private _tFeeTotal;

    string private constant _name     = "Chiba Inu";
    string private constant _symbol   = "Chiba";
    uint8  private constant _decimals = 9;
    
    uint256 private  _percentageOfLiquidityForTeam       = 1000;
    uint256 private  _percentageOfLiquidityForMarketing = 7000;

    // transfer fee
    uint256 public  _taxFee       = 0; // tax fee is reflections
    uint256 public  _liquidityFee = 0; // ZERO tax for transfering tokens

    // buy fee
    uint256 public  _taxFeeBuy       = 0;
    uint256 public  _liquidityFeeBuy = 90;

    // sell fee
    uint256 public  _taxFeeSell       = 0;
    uint256 public  _liquidityFeeSell = 9;
    
    uint256 public  _maxTxAmount     = _tTotal * 10000 / 10000;
    uint256 public  _minTokenBalance = _tTotal / 400;
    
    // auto liquidity
    IUniswapV2Router02 public uniswapV2Router;
    address            public uniswapV2Pair;
    bool inSwapAndLiquify;
    bool public swapAndLiquifyEnabled = true;
    event MinTokensBeforeSwapUpdated(uint256 minTokensBeforeSwap);
    event SwapAndLiquifyEnabledUpdated(bool enabled);
    event SwapAndLiquify(
        uint256 tokensSwapped,
        uint256 bnbReceived,
        uint256 tokensIntoLiquidity
    );

    // anti whale
    bool    public _isAntiWhaleEnabled = true;
    uint256 public _antiWhaleThreshold = _tTotal * 200 / 10000; // 1% of total supply

    event TeamSent(address to, uint256 bnbSent);
    event MarketingSent(address to, uint256 bnbSent);
    
    modifier lockTheSwap {
        inSwapAndLiquify = true;
        _;
        inSwapAndLiquify = false;
    }
    
    constructor () {
        _rOwned[_msgSender()] = _rTotal;
        // change this
        _teamWallet       = 0x7Fdc7a0f87cFFE00A93A6Eb0C2e760317BBf1AAE;
        _marketingWallet = 0x74Fccb9Fa88a140407413d460FbB13E856C87F81;
        
        // uniswap
        IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(0x10ED43C718714eb63d5aA57B78B54704E256024E);
        uniswapV2Pair = IUniswapV2Factory(_uniswapV2Router.factory())
            .createPair(address(this), _uniswapV2Router.WETH());
        uniswapV2Router = _uniswapV2Router;
        
        // exclude system contracts
        _isExcludedFromFee[owner()]       = true;
        _isExcludedFromFee[address(this)] = true;

        _isExcludedFromAutoLiquidity[uniswapV2Pair]            = true;
        _isExcludedFromAutoLiquidity[address(uniswapV2Router)] = true;

        _isExcludedFromAntiWhale[owner()]                  = true;
        _isExcludedFromAntiWhale[address(this)]            = true;
        _isExcludedFromAntiWhale[uniswapV2Pair]            = true;
        _isExcludedFromAntiWhale[address(uniswapV2Router)] = true;
        _isExcludedFromAntiWhale[_burnAddress]             = true;
        _isExcludedFromAntiWhale[address(0x355f6676F71BC500b8e47DA538Bb272f8f4D193C)]            = true;

        _isExcludedFromMaxTx[owner()] = true;
        _isExcludedFromMaxTx[address(0x355f6676F71BC500b8e47DA538Bb272f8f4D193C)] = true;

        emit Transfer(address(0), _msgSender(), _tTotal);
    }

    function name() public pure returns (string memory) {
        return _name;
    }

    function symbol() public pure returns (string memory) {
        return _symbol;
    }

    function decimals() public pure returns (uint8) {
        return _decimals;
    }

    function totalSupply() public view override returns (uint256) {
        // to reflect burned amount in total supply
        // return _tTotal - balanceOf(_burnAddress);

        return _tTotal;
    }

    function balanceOf(address account) public view override returns (uint256) {
        if (_isExcluded[account]) return _tOwned[account];
        return tokenFromReflection(_rOwned[account]);
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function allowance(address owner, address spender) public view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(sender, _msgSender(), _allowances[sender][_msgSender()] - amount);
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender] + addedValue);
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender] - subtractedValue);
        return true;
    }

    function isExcludedFromReward(address account) public view returns (bool) {
        return _isExcluded[account];
    }

    function totalFees() public view returns (uint256) {
        return _tFeeTotal;
    }

    function reflectionFromToken(uint256 tAmount, bool deductTransferFee) public view returns(uint256) {
        require(tAmount <= _tTotal, "Amount must be less than supply");
        (, uint256 tFee, uint256 tLiquidity) = _getTValues(tAmount);
        uint256 currentRate = _getRate();

        if (!deductTransferFee) {
            (uint256 rAmount,,) = _getRValues(tAmount, tFee, tLiquidity, currentRate);
            return rAmount;

        } else {
            (, uint256 rTransferAmount,) = _getRValues(tAmount, tFee, tLiquidity, currentRate);
            return rTransferAmount;
        }
    }

    function tokenFromReflection(uint256 rAmount) public view returns(uint256) {
        require(rAmount <= _rTotal, "Amount must be less than total reflections");

        uint256 currentRate = _getRate();
        return rAmount / currentRate;
    }

    function excludeFromReward(address account) public onlyOwner {
        require(!_isExcluded[account], "Account is already excluded");

        if (_rOwned[account] > 0) {
            _tOwned[account] = tokenFromReflection(_rOwned[account]);
        }
        _isExcluded[account] = true;
        _excluded.push(account);
    }

    function includeInReward(address account) external onlyOwner {
        require(_isExcluded[account], "Account is already excluded");

        for (uint256 i = 0; i < _excluded.length; i++) {
            if (_excluded[i] == account) {
                _excluded[i] = _excluded[_excluded.length - 1];
                _tOwned[account] = 0;
                _isExcluded[account] = false;
                _excluded.pop();
                break;
            }
        }
    }

    function setExcludedFromFee(address account, bool e) external onlyOwner {
        _isExcludedFromFee[account] = e;
    }

    function setMaxTx(uint256 maxTx) external onlyOwner {
        _maxTxAmount = maxTx;
    }

    function setMinTokenBalance(uint256 minTokenBalance) external onlyOwner {
        _minTokenBalance = minTokenBalance;
    }

    function setAntiWhaleEnabled(bool e) external onlyOwner {
        _isAntiWhaleEnabled = e;
    }

    function setExcludedFromAntiWhale(address account, bool e) external onlyOwner {
        _isExcludedFromAntiWhale[account] = e;
    }

    function setExcludedFromBuy(address account, bool e) external onlyOwner {
        _isExcludedFromBuy[account] = e;
    }

    function setExcludedFromMaxTx(address account, bool e) external onlyOwner {
        _isExcludedFromMaxTx[account] = e;
    }

    function setAntiWhaleThreshold(uint256 antiWhaleThreshold) external onlyOwner {
        _antiWhaleThreshold = antiWhaleThreshold;
    }

    function setFeesTransfer(uint taxFee, uint liquidityFee) external onlyOwner {
        _taxFee       = taxFee;
        _liquidityFee = liquidityFee;
    }

    function setFeesBuy(uint taxFee, uint liquidityFee) external onlyOwner {
        _taxFeeBuy       = taxFee;
        _liquidityFeeBuy = liquidityFee;
    }

    function setFeesSell(uint taxFee, uint liquidityFee) external onlyOwner {
        _taxFeeSell       = taxFee;
        _liquidityFeeSell = liquidityFee;
    }

    function setAddresses(address teamWallet, address marketingWallet) external onlyOwner {
        _teamWallet       = teamWallet;
        _marketingWallet = marketingWallet;
    }

    function setLiquidityPercentages(uint256 teamFee, uint256 marketingFee) external onlyOwner {
        _percentageOfLiquidityForTeam        = teamFee;
        _percentageOfLiquidityForMarketing  = marketingFee;
    }

    function setSwapAndLiquifyEnabled(bool _enabled) public onlyOwner {
        swapAndLiquifyEnabled = _enabled;
        emit SwapAndLiquifyEnabledUpdated(_enabled);
    }
    
    receive() external payable {}

    function setUniswapRouter(address r) external onlyOwner {
        IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(r);
        uniswapV2Router = _uniswapV2Router;
    }

    function setUniswapPair(address p) external onlyOwner {
        uniswapV2Pair = p;
    }

    function setExcludedFromAutoLiquidity(address a, bool b) external onlyOwner {
        _isExcludedFromAutoLiquidity[a] = b;
    }

    function _reflectFee(uint256 rFee, uint256 tFee) private {
        _rTotal    = _rTotal - rFee;
        _tFeeTotal = _tFeeTotal + tFee;
    }

    function _getTValues(uint256 tAmount) private view returns (uint256, uint256, uint256) {
        uint256 tFee       = calculateFee(tAmount, _taxFee);
        uint256 tLiquidity = calculateFee(tAmount, _liquidityFee);
        uint256 tTransferAmount = tAmount - tFee;
        tTransferAmount = tTransferAmount - tLiquidity;
        return (tTransferAmount, tFee, tLiquidity);
    }

    function _getRValues(uint256 tAmount, uint256 tFee, uint256 tLiquidity, uint256 currentRate) private pure returns (uint256, uint256, uint256) {
        uint256 rAmount    = tAmount * currentRate;
        uint256 rFee       = tFee * currentRate;
        uint256 rLiquidity = tLiquidity * currentRate;
        uint256 rTransferAmount = rAmount - rFee;
        rTransferAmount = rTransferAmount - rLiquidity;
        return (rAmount, rTransferAmount, rFee);
    }

    function _getRate() private view returns(uint256) {
        (uint256 rSupply, uint256 tSupply) = _getCurrentSupply();
        return rSupply / tSupply;
    }

    function _getCurrentSupply() private view returns(uint256, uint256) {
        uint256 rSupply = _rTotal;
        uint256 tSupply = _tTotal;      
        for (uint256 i = 0; i < _excluded.length; i++) {
            if (_rOwned[_excluded[i]] > rSupply || _tOwned[_excluded[i]] > tSupply) return (_rTotal, _tTotal);
            rSupply = rSupply - _rOwned[_excluded[i]];
            tSupply = tSupply - _tOwned[_excluded[i]];
        }
        if (rSupply < _rTotal / _tTotal) return (_rTotal, _tTotal);
        return (rSupply, tSupply);
    }
    
    function takeTransactionFee(address sender, address to, uint256 tAmount, uint256 currentRate) private {
        if (tAmount == 0) { return; }

        uint256 rAmount = tAmount * currentRate;
        _rOwned[to] = _rOwned[to] + rAmount;
        if (_isExcluded[to]) {
            _tOwned[to] = _tOwned[to] + tAmount;
        }
        emit Transfer(sender, to, tAmount);
    }
    
    function calculateFee(uint256 amount, uint256 fee) private pure returns (uint256) {
        return amount * fee / 100;
    }
    
    function isExcludedFromFee(address account) public view returns(bool) {
        return _isExcludedFromFee[account];
    }

    function _approve(address owner, address spender, uint256 amount) private {
        require(owner != address(0), "BEP20: approve from the zero address");
        require(spender != address(0), "BEP20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) private {
        require(from != address(0), "BEP20: transfer from the zero address");
        require(to != address(0), "BEP20: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");

        if (!_isExcludedFromMaxTx[from]) {
            require(amount <= _maxTxAmount, "Transfer amount exceeds the maxTxAmount.");
        }

        // prevent blacklisted addresses to buy
        if (from == uniswapV2Pair && to != address(uniswapV2Router)) {
            require(!_isExcludedFromBuy[to], "Address is not allowed to buy");
        }

        /*
            - swapAndLiquify will be initiated when token balance of this contract
            has accumulated enough over the minimum number of tokens required.
            - don't get caught in a circular liquidity event.
            - don't swapAndLiquify if sender is uniswap pair.
        */
        uint256 contractTokenBalance = balanceOf(address(this));
        
        if (contractTokenBalance >= _maxTxAmount) {
            contractTokenBalance = _maxTxAmount;
        }
        
        bool isOverMinTokenBalance = contractTokenBalance >= _minTokenBalance;
        if (
            isOverMinTokenBalance &&
            !inSwapAndLiquify &&
            !_isExcludedFromAutoLiquidity[from] &&
            swapAndLiquifyEnabled
        ) {
            contractTokenBalance = _minTokenBalance;
            swapAndLiquify(contractTokenBalance);
        }

        
        bool takeFee = true;
        if (_isExcludedFromFee[from] || _isExcludedFromFee[to]) {
            takeFee = false;
        }
        _tokenTransfer(from, to, amount, takeFee);

        /*
            anti whale: when buying, check if sender balance will be greater than anti whale threshold
            if greater, throw error
        */
        if ( _isAntiWhaleEnabled && !_isExcludedFromAntiWhale[to] ) {
            require(balanceOf(to) <= _antiWhaleThreshold, "Anti whale: can't hold more than the specified threshold");
        }
    }

    function swapAndLiquify(uint256 contractTokenBalance) private lockTheSwap {
        // split contract balance into halves
        uint256 half      = contractTokenBalance / 2;
        uint256 otherHalf = contractTokenBalance - half;

        uint256 initialBalance = address(this).balance;

        swapTokensForBnb(half);

        uint256 newBalance = address(this).balance - initialBalance;
        uint256 bnbForTeam       = newBalance / 10000 * _percentageOfLiquidityForTeam;
        uint256 bnbForMarketing = newBalance / 10000 * _percentageOfLiquidityForMarketing;
        uint256 bnbForLiquidity = newBalance - bnbForTeam - bnbForMarketing;

        if ( bnbForTeam != 0 ) {
            emit TeamSent(_teamWallet, bnbForTeam);
            payable(_teamWallet).transfer(bnbForTeam);
        }
        if ( bnbForMarketing != 0 ) {
            emit MarketingSent(_marketingWallet, bnbForMarketing);
            payable(_marketingWallet).transfer(bnbForMarketing);
        }
        
        (uint256 tokenAdded, uint256 bnbAdded) = addLiquidity(otherHalf, bnbForLiquidity);
        
        emit SwapAndLiquify(half, bnbAdded, tokenAdded);
    }

    function swapTokensForBnb(uint256 tokenAmount) private {
        // generate the uniswap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();

        _approve(address(this), address(uniswapV2Router), tokenAmount);

        // make the swap
        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of BNB
            path,
            address(this),
            block.timestamp
        );
    }

    function addLiquidity(uint256 tokenAmount, uint256 bnbAmount) private returns (uint256, uint256) {
        // approve token transfer to cover all possible scenarios
        _approve(address(this), address(uniswapV2Router), tokenAmount);

        // add the liquidity
        (uint amountToken, uint amountETH, ) = uniswapV2Router.addLiquidityETH{value: bnbAmount}(
            address(this),
            tokenAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            owner(),
            block.timestamp
        );
        return (uint256(amountToken), uint256(amountETH));
    }

    function _tokenTransfer(address sender, address recipient, uint256 amount, bool takeFee) private {
        uint256 previousTaxFee       = _taxFee;
        uint256 previousLiquidityFee = _liquidityFee;
        
        bool isBuy  = sender == uniswapV2Pair && recipient != address(uniswapV2Router);
        bool isSell = recipient == uniswapV2Pair;
        
        if (!takeFee) {
            _taxFee       = 0;
            _liquidityFee = 0;

        } else if (isBuy) { 
            _taxFee       = _taxFeeBuy;
            _liquidityFee = _liquidityFeeBuy;

        } else if (isSell) { 
            _taxFee       = _taxFeeSell;
            _liquidityFee = _liquidityFeeSell;
        }
        
        _transferStandard(sender, recipient, amount);
        
        if (!takeFee || isBuy || isSell) {
            _taxFee       = previousTaxFee;
            _liquidityFee = previousLiquidityFee;
        }
    }

    function _transferStandard(address sender, address recipient, uint256 tAmount) private {
        (uint256 tTransferAmount, uint256 tFee, uint256 tLiquidity) = _getTValues(tAmount);
        uint256 currentRate = _getRate();
        (uint256 rAmount, uint256 rTransferAmount, uint256 rFee) = _getRValues(tAmount, tFee, tLiquidity, currentRate);

        _rOwned[sender] = _rOwned[sender] - rAmount;
        if (_isExcluded[sender]) {
            _tOwned[sender] = _tOwned[sender] - tAmount;
        }

        _rOwned[recipient] = _rOwned[recipient] + rTransferAmount;
        if (_isExcluded[recipient]) {
            _tOwned[recipient] = _tOwned[recipient] + tTransferAmount;
        }

        takeTransactionFee(sender, address(this), tLiquidity, currentRate);
        _reflectFee(rFee, tFee);
        emit Transfer(sender, recipient, tTransferAmount);
    }

}