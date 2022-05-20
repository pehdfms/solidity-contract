pragma solidity ^0.8.4;

library SafeMath {
    function div(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b > 0, errorMessage);
        uint256 c = a / b;
        return c;
    }

    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        return div(a, b, "SafeMath: division by zero");
    }

    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        return sub(a, b, "SafeMath: subtraction overflow");
    }

	function sub(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b <= a, errorMessage);
        uint256 c = a - b;
        return c;
    }

    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) {
            return 0;
        }
        uint256 c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");
        return c;
    }

    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "SafeMath: addition overflow");
        return c;
    }
}

interface IBEP20 {
    function approve(address spender, uint256 amount) external returns (bool);
    function symbol() external view returns (string memory);
    function totalSupply() external view returns (uint256);
    function decimals() external view returns (uint8);
    function balanceOf(address account) external view returns (uint256);
    function name() external view returns (string memory);
    function getOwner() external view returns (address);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address _owner, address spender) external view returns (uint256);

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

interface IDEXFactory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
}

interface IDEXRouter {
    function WETH() external pure returns (address);
    function factory() external pure returns (address);
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;
    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external payable returns (uint amountToken, uint amountETH, uint liquidity);
    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external payable;
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB, uint liquidity);
}

abstract contract Ownable {
    address public owner;
    constructor(address owner_) {
        owner = owner_;
    }
    modifier onlyOwner() {
        require(isOwner(msg.sender), "Ownership required."); _;
    }
    function isOwner(address account) public view returns (bool) {
        return account == owner;
    }
    function transferOwnership(address payable adr) public onlyOwner {
        address oldOwner = owner;
        owner = adr;
        emit OwnershipTransferred(oldOwner, owner);
    }
    function renounceOwnership() public onlyOwner {
        emit OwnershipTransferred(owner, address(0));
        owner = address(0);
    }
    event OwnershipTransferred(address from, address to);
}

interface IDividendDistributor {
    function setShare(address shareholder, uint256 amount) external;
    function process(uint256 gas) external;
    function claimDividend() external;
    function deposit() external payable;
    function setDistributionCriteria(uint256 _minPeriod, uint256 _minDistribution) external;
}

contract DividendDistributor is IDividendDistributor {
    using SafeMath for uint256;
    address _token;

//  IBEP20 BUSD = IBEP20(0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56); // Main
//  address WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;        // Main
    IBEP20 BUSD = IBEP20(0xeD24FC36d5Ee211Ea25A80239Fb8C4Cfd80f12Ee); // Test
    address WBNB = 0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd;        // Test

    struct Share {
        uint256 amount;
        uint256 totalExcluded;
        uint256 totalRealised;
    }
    IDEXRouter router;
    mapping (address => Share) public shares;
    mapping (address => uint256) shareholderIndexes;
    uint256 public totalShares;
    uint256 public dividendsPerShare;
    uint256 public dividendsPerShareAccuracyFactor = 10 ** 36;
    address[] shareholders;
    mapping (address => uint256) shareholderClaims;
    uint256 public minPeriod = 1 hours;
    uint256 public minDistribution = 1 * (10 ** 18);
    uint256 public totalDividends;
    uint256 public totalDistributed;
    uint256 currentIndex;
    bool initialized;
    modifier initialization() {
        require(!initialized);
        _;
        initialized = true;
    }
    modifier onlyToken() {
        require(msg.sender == _token); _;
    }
    constructor (address _router) {
        router = _router != address(0)
            ? IDEXRouter(_router)
//          : IDEXRouter(0x10ED43C718714eb63d5aA57B78B54704E256024E); // Main
    		: IDEXRouter(0x9Ac64Cc6e4415144C455BD8E4837Fea55603e5c3); // Test
        _token = msg.sender;
    }
    function setDistributionCriteria(uint256 _minPeriod, uint256 _minDistribution) external override onlyToken {
        minPeriod = _minPeriod;
        minDistribution = _minDistribution;
    }
    function setShare(address shareholder, uint256 amount) external override onlyToken {
        if(shares[shareholder].amount > 0){
            distributeDividend(shareholder);
        }
        if(amount > 0 && shares[shareholder].amount == 0){
            addShareholder(shareholder);
        }else if(amount == 0 && shares[shareholder].amount > 0){
            removeShareholder(shareholder);
        }
        totalShares = totalShares.sub(shares[shareholder].amount).add(amount);
        shares[shareholder].amount = amount;
        shares[shareholder].totalExcluded = getCumulativeDividends(shares[shareholder].amount);
    }
    function deposit() external payable override onlyToken {
        uint256 balanceBefore = BUSD.balanceOf(address(this));
        address[] memory path = new address[](2);
        path[0] = WBNB;
        path[1] = address(BUSD);
        router.swapExactETHForTokensSupportingFeeOnTransferTokens{value: msg.value}(
            0,
            path,
            address(this),
            block.timestamp
        );
        uint256 amount = BUSD.balanceOf(address(this)).sub(balanceBefore);
        totalDividends = totalDividends.add(amount);
        dividendsPerShare = dividendsPerShare.add(dividendsPerShareAccuracyFactor.mul(amount).div(totalShares));
    }
    function process(uint256 gas) external override onlyToken {
        uint256 shareholderCount = shareholders.length;
        if(shareholderCount == 0) { return; }
        uint256 gasUsed = 0;
        uint256 gasLeft = gasleft();
        uint256 iterations = 0;
        while(gasUsed < gas && iterations < shareholderCount) {
            if(currentIndex >= shareholderCount){
                currentIndex = 0;
            }
            if(shouldDistribute(shareholders[currentIndex])){
                distributeDividend(shareholders[currentIndex]);
            }
            gasUsed = gasUsed.add(gasLeft.sub(gasleft()));
            gasLeft = gasleft();
            currentIndex++;
            iterations++;
        }
    }
    function shouldDistribute(address shareholder) internal view returns (bool) {
        return shareholderClaims[shareholder] + minPeriod < block.timestamp
                && getUnpaidEarnings(shareholder) > minDistribution;
    }
    function getCumulativeDividends(uint256 share) internal view returns (uint256) {
        return share.mul(dividendsPerShare).div(dividendsPerShareAccuracyFactor);
    }
    function distributeDividend(address shareholder) internal {
        if(shares[shareholder].amount == 0){ return; }
        uint256 amount = getUnpaidEarnings(shareholder);
        if(amount > 0){
            totalDistributed = totalDistributed.add(amount);
            BUSD.transfer(shareholder, amount);
            shareholderClaims[shareholder] = block.timestamp;
            shares[shareholder].totalRealised = shares[shareholder].totalRealised.add(amount);
            shares[shareholder].totalExcluded = getCumulativeDividends(shares[shareholder].amount);
        }
    }
    function claimDividend() external override {
        distributeDividend(msg.sender);
    }
    function removeShareholder(address shareholder) internal {
        shareholders[shareholderIndexes[shareholder]] = shareholders[shareholders.length-1];
        shareholderIndexes[shareholders[shareholders.length-1]] = shareholderIndexes[shareholder];
        shareholders.pop();
    }
    function getUnpaidEarnings(address shareholder) public view returns (uint256) {
        if(shares[shareholder].amount == 0){ return 0; }
        uint256 shareholderTotalDividends = getCumulativeDividends(shares[shareholder].amount);
        uint256 shareholderTotalExcluded = shares[shareholder].totalExcluded;
        if(shareholderTotalDividends <= shareholderTotalExcluded){ return 0; }
        return shareholderTotalDividends.sub(shareholderTotalExcluded);
    }
    function addShareholder(address shareholder) internal {
        shareholderIndexes[shareholder] = shareholders.length;
        shareholders.push(shareholder);
    }
}

contract BSCTESTTOKEN is IBEP20, Ownable {
    using SafeMath for uint256;

    string constant _name = "BSCTESTTOKEN";
    string constant _symbol = "TEST";
    uint8 constant _decimals = 9;
    uint256 _tTotal = 10 ** 12 * (10 ** _decimals);
    uint256 _rTotal = (MAX - (MAX % _tTotal));
    uint256 public liquidityFee = 300;
    uint256 public reflectionFee = 0;
    uint256 public marketingFee = 100;
    uint256 public rewardFee = 600;
    uint256 public _maxTxAmount = _tTotal / 10;
    uint256 public _maxHold = _tTotal / 100;
    uint256 public _rewardHold = _maxHold / 2;
    uint256 public bigHoldings = 0;
    uint256 public marketingFeeReceiver = 0xda7355ee177e84560533ec184199ba04fa4c7d69;

    struct Account {
        uint256 balance;
        uint256 rOwned;
    }

//  address BUSD = 0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56; // Main
//  address WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c; // Main
    address BUSD = 0xeD24FC36d5Ee211Ea25A80239Fb8C4Cfd80f12Ee; // Test
    address WBNB = 0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd; // Test

    address DEAD = 0x000000000000000000000000000000000000dEaD;
    address ZERO = 0x0000000000000000000000000000000000000000;
    mapping (address => bool) isTxLimitExempt;
    mapping (address => Account) _accounts;
    mapping (address => bool) isBigWallet;
    mapping (address => mapping(address => uint256)) _allowances;
    mapping (address => bool) isMaxHoldExempt;
    mapping (address => bool) isFeeExempt;
    mapping (address => bool) isDividendExempt;
    mapping (address => bool) isReflectionExempt;
    address[] _excluded;
    uint256 public feeDenominator = 10000;
    uint256 totalFee = liquidityFee + reflectionFee + rewardFee + marketingFee;
    address public autoLiquidityReceiver;
    address[] public pairs;
    IDEXRouter public router;
    address pancakeV2BNBPair;
    DividendDistributor distributor;
    uint256 distributorGas = 600000;
    uint256 public launchedAt;
    bool public liquifyEnabled = true;
    bool public feesOnNormalTransfers = false;
    bool public swapEnabled = true;
    bool inSwap;
    uint256 public swapThreshold = _tTotal / 5000; // 0.02%
    modifier swapping() { inSwap = true; _; inSwap = false; }
    event SwapBackSuccess(uint256 amount);
    event Launched(uint256 blockNumber, uint256 timestamp);
    event SwapBackFailed(string message);
    event AutoLiquify(uint256 amountBNB, uint256 amountBOG);
    event MarketTransfer(bool status);
    constructor () Ownable(msg.sender) {
//      router = IDEXRouter(0x10ED43C718714eb63d5aA57B78B54704E256024E); // Mainnet
		router = IDEXRouter(0x9Ac64Cc6e4415144C455BD8E4837Fea55603e5c3); // Testnet

        autoLiquidityReceiver = DEAD;
        pancakeV2BNBPair = IDEXFactory(router.factory()).createPair(WBNB, address(this));
        _allowances[address(this)][address(router)] = ~uint256(0);
        pairs.push(pancakeV2BNBPair);
        distributor = new DividendDistributor(address(router));
        address owner_ = msg.sender;
        isDividendExempt[DEAD] = true;
        isMaxHoldExempt[DEAD] = true;
        isMaxHoldExempt[pancakeV2BNBPair] = true;
        isDividendExempt[pancakeV2BNBPair] = true;
        isReflectionExempt[pancakeV2BNBPair] = true;
        isMaxHoldExempt[address(this)] = true;
        isFeeExempt[address(this)] = true;
        isDividendExempt[address(this)] = true;
        isReflectionExempt[address(this)] = true;
        isTxLimitExempt[address(this)] = true;
        isFeeExempt[owner_] = true;
        isTxLimitExempt[owner_] = true;
        isMaxHoldExempt[owner_] = true;
        _accounts[owner_].balance = _tTotal;
        emit Transfer(address(0), owner_, _tTotal);
    }
    receive() external payable {  }
    function approve(address spender, uint256 amount) public override returns (bool) {
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }
    function decimals() external pure override returns (uint8) { return _decimals; }
    function name() external pure override returns (string memory) { return _name; }
    function symbol() external pure override returns (string memory) { return _symbol; }
    function getOwner() external view override returns (address) { return owner; }
    function allowance(address holder, address spender) external view override returns (uint256) { return _allowances[holder][spender]; }
    function totalSupply() external view override returns (uint256) { return _tTotal; }

    function transfer(address recipient, uint256 amount) external override returns (bool) {
        return _transferFrom(msg.sender, recipient, amount);
    }

    function transferFrom(address sender, address recipient, uint256 amount) external override returns (bool) {
        if(_allowances[sender][msg.sender] != ~uint256(0)){
            _allowances[sender][msg.sender] = _allowances[sender][msg.sender].sub(amount, "Insufficient Allowance");
        }
        return _transferFrom(sender, recipient, amount);
    }

    function _transferFrom(address sender, address recipient, uint256 amount) internal returns (bool) {
        checkTxLimit(sender, amount);
        if (shouldSwapBack()) { swapBack(); }
        if (!launched() && recipient == pancakeV2BNBPair) { require(_accounts[sender].balance > 0); launch(); }
        if (!isMaxHoldExempt[recipient]) {
            require((_accounts[recipient].balance + (amount - amount * totalFee / feeDenominator)) <= _maxHold, "Wallet cannot hold more than 1%");
        }

        require(_accounts[sender].balance >= amount, "Insufficient Balance");

        uint256 prevSender = _accounts[sender].balance;
        uint256 prevRecipient = _accounts[recipient].balance;

        capReflections(sender)
        capReflections(recipient)

        _accounts[sender].balance = _accounts[sender].balance.sub(amount);
        calculateBigWallet(sender, prevSender);

        uint256 amountReceived = shouldTakeFee(sender, recipient) ? takeFee(sender, amount) : amount;
        _accounts[recipient].balance = _accounts[recipient].balance.add(amountReceived);
        calculateBigWallet(recipient, prevRecipient);

        try distributor.process(distributorGas) {} catch {}
        emit Transfer(sender, recipient, amountReceived);

        adjustFees();
        return true;
    }

    function approveMax(address spender) external returns (bool) {
        return approve(spender, ~uint256(0));
    }

    function getTotalFee() public view returns (uint256) {
        if(launchedAt + 1 >= block.number){ return feeDenominator.sub(1); }
        return totalFee;
    }

    function shouldTakeFee(address sender, address recipient) internal view returns (bool) {
        if (isFeeExempt[sender] || isFeeExempt[recipient] || !launched()) return false;
        address[] memory liqPairs = pairs;
        for (uint256 i = 0; i < liqPairs.length; i++) {
            if (sender == liqPairs[i] || recipient == liqPairs[i]) return true;
        }
        return feesOnNormalTransfers;
    }

    function isSell(address recipient) internal view returns (bool) {
        address[] memory liqPairs = pairs;
        for (uint256 i = 0; i < liqPairs.length; i++) {
            if (recipient == liqPairs[i]) return true;
        }
        return false;
    }

    function checkTxLimit(address sender, uint256 amount) internal view {
        require(amount <= _maxTxAmount || isTxLimitExempt[sender], "TX Limit Exceeded");
    }

    function takeFee(address sender, uint256 amount) internal returns (uint256) {
        uint256 feeAmount = amount.mul(getTotalFee()).div(feeDenominator);
        uint256 finalFee = feeAmount;
        _accounts[address(this)].balance = _accounts[address(this)].balance.add(finalFee);
        emit Transfer(sender, address(this), finalFee);
        return amount.sub(feeAmount);
    }


    function setIsMaxHoldExempt(address holder, bool exempt) public onlyOwner() {
        isMaxHoldExempt[holder] = exempt;
    }

    function setIsTxLimitExempt(address holder, bool exempt) public onlyOwner() {
        isTxLimitExempt[holder] = exempt;
    }

    function shouldSwapBack() internal view returns (bool) {
        return msg.sender != pancakeV2BNBPair
        && swapEnabled
        && _accounts[address(this)].balance >= swapThreshold;
    }

    function setTxLimit(uint256 amount, bool _withCSupply) public onlyOwner() {
        if (_withCSupply) {
            require(amount >= getCirculatingSupply() / 2000);
            _maxTxAmount = amount;
        } else {
            require(amount >= _tTotal / 2000);
            _maxTxAmount = amount;
        }
    }

    function launch() internal {
        launchedAt = block.number;
        emit Launched(block.number, block.timestamp);
    }

    function setIsDividendExempt(address holder, bool exempt) public onlyOwner() {
        require(holder != address(this) && holder != pancakeV2BNBPair);
        isDividendExempt[holder] = exempt;
        if(exempt){
            distributor.setShare(holder, 0);
        }else{
            distributor.setShare(holder, _accounts[holder].balance);
        }
    }

    function launched() internal view returns (bool) {
        return launchedAt != 0;
    }


    function setIsFeeExempt(address holder, bool exempt) public onlyOwner() {
        isFeeExempt[holder] = exempt;
    }

    function setDistributionCriteria(uint256 _minPeriod, uint256 _minDistribution) public onlyOwner() {
        distributor.setDistributionCriteria(_minPeriod, _minDistribution);
    }

    function setDistributorSettings(uint256 gas) public onlyOwner() {
        require(gas <= 1000000);
        distributorGas = gas;
    }

    function setFeesOnNormalTransfers(bool _enabled) public onlyOwner() {
        feesOnNormalTransfers = _enabled;
    }

    function setFees(uint256 _liquidityFee, uint256 _reflectionFee, uint256 _rewardFee, uint256 _marketingFee, uint256 _feeDenominator) public onlyOwner() {
        liquidityFee = _liquidityFee;
        reflectionFee = _reflectionFee;
        rewardFee = _rewardFee;
        marketingFee = _marketingFee;
        totalFee = _liquidityFee.add(_reflectionFee).add(_rewardFee).add(_marketingFee);
        feeDenominator = _feeDenominator;
    }

    function setFeeReceivers(address _autoLiquidityReceiver, address _marketingFeeReceiver) public onlyOwner() {
        autoLiquidityReceiver = _autoLiquidityReceiver;
        marketingFeeReceiver = _marketingFeeReceiver;
    }

    function setSwapBackSettings(bool _enabled, uint256 _amount) public onlyOwner() {
        swapEnabled = _enabled;
        swapThreshold = _amount;
    }

    function setLiquifyEnabled(bool _enabled) public onlyOwner() {
        liquifyEnabled = _enabled;
    }

    function getCirculatingSupply() public view returns (uint256) {
        return _tTotal.sub(balanceOf(DEAD)).sub(balanceOf(ZERO));
    }

    function getBigHoldings() public view returns (uint256) {
        return bigHoldings;
    }

    function addPair(address pair) public onlyOwner() {
        pairs.push(pair);
    }

    function claimDividend() external {
        distributor.claimDividend();
    }

    function clearStuckBNB() external {
        payable(marketingFeeReceiver).transfer(address(this).balance);
    }

    function setMaxHoldPercentage(uint256 percent) public onlyOwner() {
         _maxHold = (_tTotal / 100) * percent;
    }

    function setLaunchedAt(uint256 launched_) public onlyOwner() {
        launchedAt = launched_;
    }

    function removeLastPair() public onlyOwner() {
        pairs.pop();
    }

    function swapBack() internal swapping {
        uint256 swapLiquidityFee = liquifyEnabled ? liquidityFee : 0;
        uint256 amountToLiquify = swapThreshold.mul(swapLiquidityFee).div(totalFee).div(2);
        uint256 amountToSwap = swapThreshold.sub(amountToLiquify);
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = WBNB;
        uint256 balanceBefore = address(this).balance;
        try router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            amountToSwap,
            0,
            path,
            address(this),
            block.timestamp
        ) {
            uint256 amountBNB = address(this).balance.sub(balanceBefore);
            uint256 totalBNBFee = totalFee.sub(swapLiquidityFee.div(2));
            uint256 amountBNBLiquidity = amountBNB.mul(swapLiquidityFee).div(totalBNBFee).div(2);
            uint256 amountBNBReflection = amountBNB.mul(reflectionFee).div(totalBNBFee);
            uint256 amountBNBReward = amountBNB.mul(rewardFee).div(totalBNBFee);
            uint256 amountBNBMarketing = amountBNB.mul(marketingFee).div(totalBNBFee);
            try distributor.deposit{value: amountBNBReflection}() {} catch {}
            (bool marketSuccess, ) = payable(marketingFeeReceiver).call{value: amountBNBMarketing, gas: 30000}("");
            emit MarketTransfer(marketSuccess);

            if(amountToLiquify > 0){
                try router.addLiquidityETH{ value: amountBNBLiquidity }(
                    address(this),
                    amountToLiquify,
                    0,
                    0,
                    autoLiquidityReceiver,
                    block.timestamp
                ) {
                    emit AutoLiquify(amountToLiquify, amountBNBLiquidity);
                } catch {
                    emit AutoLiquify(0, 0);
                }
            }
            emit SwapBackSuccess(amountToSwap);
        } catch Error(string memory e) {
            emit SwapBackFailed(string(abi.encodePacked("SwapBack failed with error ", e)));
        } catch {
            emit SwapBackFailed("SwapBack failed without an error message from pancakeSwap");
        }
    }

    function calculateBigWallet(address account, uint256 prevBalance) private {
        if (_accounts[account].balance >= _rewardHold) {
            if (!isDividendExempt[account]) { try distributor.setShare(account, _accounts[account].balance) {} catch {} }
            bigHoldings += isBigWallet[account] ? (_accounts[account].balance - prevBalance) : _accounts[account].balance;
            isBigWallet[account] = true;
        } else {
            try distributor.setShare(account, 0) {} catch {}
            if (isBigWallet[account]) { bigHoldings -= prevBalance; }
            isBigWallet[account] = false;
        }
    }

    function distributeReflections(uint256 amount) private {
        _rTotal = _rTotal.sub(amount);
    }

    function limitHold(address account) private {
    }

    function excludeReflections(address account) private {
        require(!isReflectionExempt[account], "Account is already excluded.");
        if (_accounts[account].rOwned > 0) {
            reflectionTokens = tokenFromReflection(_accounts[account].rOwned);
            if (reflectionTokens >= _rewardHold) {
                _accounts[account].balance = _rewardHold;
                distributeReflections(reflectionTokens - _rewardHold);
            } else _accounts[account].balance = reflectionTokens;
        }
        isReflectionExempt[account] = true;
        _excluded.push(account);
    }

    function _getCurrentSupply() private view returns (uint256, uint256) {
        uint256 rSupply = _rTotal;
        uint256 tSupply = _tTotal;
        for (uint256 i = 0; i < _excluded.length; i++) {
            if (_rOwned[_excluded[i]] > rSupply || _tOwned[_excluded[i]] > tSupply) return (_rTotal, _tTotal);
            rSupply = rSupply.sub(_rOwned[_excluded[i]]);
            tSupply = tSupply.sub(_tOwned[_excluded[i]]);
        }
        if (rSupply < _rTotal.div(_tTotal)) return (_rTotal, _tTotal);
        return (rSupply, tSupply);
    }

    function _getRate() private view returns (uint256) {
        (uint256 rSupply, uint256 tSupply) = _getCurrentSupply();
        return rSupply.div(tSupply);
    }

    function tokenFromReflection(uint256 rAmount) public view returns (uint256) {
        require(rAmount <= _rTotal, "Amount must be less than total reflections");
        uint256 currentRate = _getRate();
        return rAmount.div(currentRate);
    }

    function balanceOf(address account) public view override returns (uint256) {
        // reflection exempt accounts and accounts who already reached max reflection hold get judged by their actual balance
        // if you've gotten past the reflection cap by holding and getting reflections, your balance might appear to go down massively,
        // but the next transaction will reimburse your reflections UP TO max reflections, and redistribute the overflow to others.
        if (_accounts[account].balance >= _rewardHold
            || isReflectionExempt[account]) return _accounts[account].balance;

        uint256 reflectionTotal = tokenFromReflection(_accounts[account].rOwned);
        if (reflectionTotal >= _rewardHold) return _rewardHold;
        return reflectionTotal;
    }

    function adjustFees() private {
        // magic number here, reflectionFee + rewardFee should always equal 6%, but relying on their values could lead to decreasing fees over time from precision errors,
        // we calculate how much of that fee goes to whales by checking how much of total supply they hold
        // the reason we don't use circulating supply here is because the DEAD address receives reflections but IS NOT circulating
        uint256 totalFee = 600;
        rewardFee = totalFee * bigHoldings.div(_tTotal);
        reflectionFee = totalFee - rewardFee;
    }
}
