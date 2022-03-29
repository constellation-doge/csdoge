// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/finance/VestingWallet.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import "./interface/ICsDogeRouter.sol";
import "./interface/ICsDogeFactory.sol";

contract CsDogeToken is Context, IERC20, IERC20Metadata, Ownable {
    uint private constant PRECISION = 10**18;

    address public marketFeeAddress;
    address public burnFeeAddress;
    address public nftFeeAddress;

    address public teamReserve;
    address public nftReserve;
    address public liquidityReserve;
    address public marketReserve;
    address public privateSaleReserve;

    VestingWallet public teamVestingWallet;
    VestingWallet public nftVestingWallet;

    ICsDogeRouter public pancakeRouter;
    address public pancakePair;

    mapping(address => uint256) private _balances;

    mapping(address => mapping(address => uint256)) private _allowances;

    uint256 private _totalSupply;

    string private _name;
    string private _symbol;

    bool inSwapAndLiquify;

    uint public privateSaleReservePercent = 15 * PRECISION / 100;
    uint public liquidityReservePercent = 5 * PRECISION / 100;
    uint public nftReservePercent = 20  * PRECISION / 100;
    uint public teamReservePercent = 5  * PRECISION / 100;
    uint public marketReservePercent = 5  * PRECISION / 100;


    uint public marketFee = 0;
    uint public burnFee = 0;
    uint public nftFee = 0;
    uint public liquidityFee = 0;

    uint public feePercent = 3 * PRECISION / 100;

    bool swapAndLiquifyEnabled = true;

    uint256 private feeThreshold = 8000000000 * PRECISION;

    mapping(address => bool) public excludedFromFee;

    address public preLaunchLock;
    bool private _paused;

    constructor(address pancake) {
        _mint(_msgSender(), 10000000 * 100000000 * PRECISION);
        _name =  "Constellation Doge";
        _symbol  =  "CsDoge";
        pancakeRouter = ICsDogeRouter(pancake);
        pancakePair = ICsDogeFactory(pancakeRouter.factory())
        .createPair(address(this), pancakeRouter.WETH());

        _approve(address(this), address(pancakeRouter), type(uint).max);
    }

    function setFeeThreshold(uint _f) public onlyOwner {
        feeThreshold = _f;
    }

    function setPreLaunchLock(address a) public onlyOwner {
        preLaunchLock = a;
    }

    function setWhiteList(address a, bool status) public onlyOwner {
        excludedFromFee[a] = status;
    }

    function setSwapAndLiquify(bool enabled) public onlyOwner {
       swapAndLiquifyEnabled  = enabled;
    }

    function  dropOwnership() public onlyOwner {
        swapAndLiquifyEnabled = true;
        renounceOwnership();
    }

    function setMarketFeeAddress(address a) public onlyOwner {
         marketFeeAddress = a;
    }
    function setBurnFeeAddress(address a) public onlyOwner {
         burnFeeAddress = a;
    }
    function setNftFeeAddress(address a) public onlyOwner {
         nftFeeAddress = a;
    }

    function setMarketReserveAddress(address a) public onlyOwner {
        marketReserve = a;
    }
    function setPrivateSaleReserveAddress(address a) public onlyOwner {
        privateSaleReserve = a;
    }
    function setNftReserveAddress(address a) public onlyOwner {
        nftReserve = a;
    }
    function setLiquidityReserveAddress(address a) public onlyOwner {
        liquidityReserve = a;
    }
    function setTeamReserveAddress(address a) public onlyOwner {
        teamReserve = a;
    }

    function pause() external onlyOwner {
        _paused = true;
    }

    function unpause() external onlyOwner {
        _paused = false;
    }


    modifier lockTheSwap {
        inSwapAndLiquify = true;
        _;
        inSwapAndLiquify = false;
    }

    receive() external payable {}

    function swapTokensForEth(uint256 tokenAmount, address receiver) private {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = pancakeRouter.WETH();

        pancakeRouter.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0,
            path,
            receiver,
            block.timestamp
        );
    }


    function swapAndLiquify() private lockTheSwap {
        uint256 half = liquidityFee / 2;
        uint256 otherHalf = liquidityFee - half;

        uint256 initialBalance = address(this).balance;
        swapTokensForEth(half, address(this));
        uint newBalance = address(this).balance - initialBalance;
        addLiquidity(otherHalf, newBalance);

        swapTokensForEth(marketFee, marketFeeAddress);
        swapTokensForEth(nftFee, nftFeeAddress);
        swapTokensForEth(burnFee, burnFeeAddress);

        marketFee = 0;
        liquidityFee = 0;
        burnFee = 0;
        nftFee = 0;

    }

    function addLiquidity(uint256 tokenAmount, uint256 ethAmount) private {
        pancakeRouter.addLiquidityETH{value: ethAmount}(
            address(this),
            tokenAmount,
            0,
            0,
            address(this),
            block.timestamp
        );
    }

    function initAddress(address _marketFeeAddress,
        address _burnFeeAddress,
        address _nftFeeAddress,
        address _teamReserveAddress,
        address _nftReserveAddress,
        address _liquidityReserveAddress,
        address _marketReserveAddress,
        address _privateSaleReserveAddress) public onlyOwner {
        marketFeeAddress = _marketFeeAddress;
        burnFeeAddress = _burnFeeAddress;
        nftFeeAddress = _nftFeeAddress;
        teamReserve = _teamReserveAddress;
        nftReserve = _nftReserveAddress;
        liquidityReserve = _liquidityReserveAddress;
        marketReserve = _marketReserveAddress;
        privateSaleReserve = _privateSaleReserveAddress;
    }

    function init() external onlyOwner {
        address sender = _msgSender();
        require(marketFeeAddress != address(0), "market fee address is not set");
        require(burnFeeAddress != address(0), "burn fee address is not set");
        require(nftFeeAddress != address(0), "nft fee reserve address is not set");

        require(teamReserve != address(0), "team reserve address is not set");
        require(nftReserve != address(0), "nft reserve address is not set");
        require(liquidityReserve != address(0), "liquidity reserve address is not set");
        require(marketReserve != address(0), "market reserve address is not set");
        require(privateSaleReserve != address(0), "private sale reserve address is not set");

        excludedFromFee[sender] = true;
        excludedFromFee[address(this)] = true;
        excludedFromFee[nftReserve] = true;
        excludedFromFee[liquidityReserve] =  true;
        excludedFromFee[privateSaleReserve] = true;

        uint supply = totalSupply();
        //burn half of token
        burn(supply / 2);
        //to private sale
        transfer(privateSaleReserve, supply * privateSaleReservePercent / PRECISION);
        //to liquidityAddress
        transfer(liquidityReserve, supply * liquidityReservePercent / PRECISION);
        //to nftReserve, lock to q4
        nftVestingWallet = new VestingWallet(nftReserve, uint64(1670402448), uint64(10));
        transfer(address(nftVestingWallet), supply * nftReservePercent / PRECISION);
        //to  team reserve, lock one year
        teamVestingWallet = new VestingWallet(teamReserve, uint64(block.timestamp) + uint64(31556952), uint64(31556952));
        transfer(address(teamVestingWallet), supply * teamReservePercent / PRECISION);
        //to market reserve
        transfer(marketReserve, supply * marketReservePercent / PRECISION);

        _paused = true;
    }

    function deduction(address from, address to, uint amount) private returns(uint){
        if(excludedFromFee[from] || excludedFromFee[to]) {
            return amount;
        }
        uint ramount = amount;
        uint fee =  amount * feePercent / PRECISION;
        marketFee +=  fee;
        liquidityFee +=  fee;
        burnFee +=  fee;
        nftFee +=  fee;
        ramount = amount - fee * 4;
        return ramount;
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(_paused == false || from == preLaunchLock, "Paused status");

        uint256 fromBalance = _balances[from];
        require(fromBalance >= amount, "ERC20: transfer amount exceeds balance");

        uint ramount = deduction(from, to, amount);
    unchecked {
        _balances[from] = fromBalance - amount;
    }
        _balances[to] += ramount;
        _balances[address(this)] =  _balances[address(this)] + (amount - ramount);

        emit Transfer(from, to, ramount);
        if (
            liquidityFee >= feeThreshold &&
            !inSwapAndLiquify &&
            from != pancakePair &&
            swapAndLiquifyEnabled
        ) {
            swapAndLiquify();
        }

    }
    function burn(uint256 amount) public virtual {
        _burn(_msgSender(), amount);
    }
    function burnFrom(address account, uint256 amount) public virtual {
        _spendAllowance(account, _msgSender(), amount);
        _burn(account, amount);
    }
    /**
   * @dev Returns the name of the token.
     */
    function name() public view virtual override returns (string memory) {
        return _name;
    }

    /**
     * @dev Returns the symbol of the token, usually a shorter version of the
     * name.
     */
    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    /**
     * @dev Returns the number of decimals used to get its user representation.
     * For example, if `decimals` equals `2`, a balance of `505` tokens should
     * be displayed to a user as `5.05` (`505 / 10 ** 2`).
     *
     * Tokens usually opt for a value of 18, imitating the relationship between
     * Ether and Wei. This is the value {ERC20} uses, unless this function is
     * overridden;
     *
     * NOTE: This information is only used for _display_ purposes: it in
     * no way affects any of the arithmetic of the contract, including
     * {IERC20-balanceOf} and {IERC20-transfer}.
     */
    function decimals() public view virtual override returns (uint8) {
        return 18;
    }

    /**
     * @dev See {IERC20-totalSupply}.
     */
    function totalSupply() public view virtual override returns (uint256) {
        return _totalSupply;
    }

    /**
     * @dev See {IERC20-balanceOf}.
     */
    function balanceOf(address account) public view virtual override returns (uint256) {
        return _balances[account];
    }

    /**
     * @dev See {IERC20-transfer}.
     *
     * Requirements:
     *
     * - `to` cannot be the zero address.
     * - the caller must have a balance of at least `amount`.
     */
    function transfer(address to, uint256 amount) public virtual override returns (bool) {
        address owner = _msgSender();
        _transfer(owner, to, amount);
        return true;
    }

    /**
     * @dev See {IERC20-allowance}.
     */
    function allowance(address owner, address spender) public view virtual override returns (uint256) {
        return _allowances[owner][spender];
    }

    /**
     * @dev See {IERC20-approve}.
     *
     * NOTE: If `amount` is the maximum `uint256`, the allowance is not updated on
     * `transferFrom`. This is semantically equivalent to an infinite approval.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     */
    function approve(address spender, uint256 amount) public virtual override returns (bool) {
        address owner = _msgSender();
        _approve(owner, spender, amount);
        return true;
    }

    /**
     * @dev See {IERC20-transferFrom}.
     *
     * Emits an {Approval} event indicating the updated allowance. This is not
     * required by the EIP. See the note at the beginning of {ERC20}.
     *
     * NOTE: Does not update the allowance if the current allowance
     * is the maximum `uint256`.
     *
     * Requirements:
     *
     * - `from` and `to` cannot be the zero address.
     * - `from` must have a balance of at least `amount`.
     * - the caller must have allowance for ``from``'s tokens of at least
     * `amount`.
     */
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public virtual override returns (bool) {
        address spender = _msgSender();
        _spendAllowance(from, spender, amount);
        _transfer(from, to, amount);
        return true;
    }

    /**
     * @dev Atomically increases the allowance granted to `spender` by the caller.
     *
     * This is an alternative to {approve} that can be used as a mitigation for
     * problems described in {IERC20-approve}.
     *
     * Emits an {Approval} event indicating the updated allowance.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     */
    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        address owner = _msgSender();
        _approve(owner, spender, _allowances[owner][spender] + addedValue);
        return true;
    }

    /**
     * @dev Atomically decreases the allowance granted to `spender` by the caller.
     *
     * This is an alternative to {approve} that can be used as a mitigation for
     * problems described in {IERC20-approve}.
     *
     * Emits an {Approval} event indicating the updated allowance.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     * - `spender` must have allowance for the caller of at least
     * `subtractedValue`.
     */
    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
        address owner = _msgSender();
        uint256 currentAllowance = _allowances[owner][spender];
        require(currentAllowance >= subtractedValue, "ERC20: decreased allowance below zero");
    unchecked {
        _approve(owner, spender, currentAllowance - subtractedValue);
    }

        return true;
    }



    /** @dev Creates `amount` tokens and assigns them to `account`, increasing
     * the total supply.
     *
     * Emits a {Transfer} event with `from` set to the zero address.
     *
     * Requirements:
     *
     * - `account` cannot be the zero address.
     */
    function _mint(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: mint to the zero address");

        _beforeTokenTransfer(address(0), account, amount);

        _totalSupply += amount;
        _balances[account] += amount;
        emit Transfer(address(0), account, amount);

        _afterTokenTransfer(address(0), account, amount);
    }

    /**
     * @dev Destroys `amount` tokens from `account`, reducing the
     * total supply.
     *
     * Emits a {Transfer} event with `to` set to the zero address.
     *
     * Requirements:
     *
     * - `account` cannot be the zero address.
     * - `account` must have at least `amount` tokens.
     */
    function _burn(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: burn from the zero address");

        _beforeTokenTransfer(account, address(0), amount);

        uint256 accountBalance = _balances[account];
        require(accountBalance >= amount, "ERC20: burn amount exceeds balance");
    unchecked {
        _balances[account] = accountBalance - amount;
    }
        _totalSupply -= amount;

        emit Transfer(account, address(0), amount);

        _afterTokenTransfer(account, address(0), amount);
    }

    /**
     * @dev Sets `amount` as the allowance of `spender` over the `owner` s tokens.
     *
     * This internal function is equivalent to `approve`, and can be used to
     * e.g. set automatic allowances for certain subsystems, etc.
     *
     * Emits an {Approval} event.
     *
     * Requirements:
     *
     * - `owner` cannot be the zero address.
     * - `spender` cannot be the zero address.
     */
    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) internal virtual {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    /**
     * @dev Spend `amount` form the allowance of `owner` toward `spender`.
     *
     * Does not update the allowance amount in case of infinite allowance.
     * Revert if not enough allowance is available.
     *
     * Might emit an {Approval} event.
     */
    function _spendAllowance(
        address owner,
        address spender,
        uint256 amount
    ) internal virtual {
        uint256 currentAllowance = allowance(owner, spender);
        if (currentAllowance != type(uint256).max) {
        require(currentAllowance >= amount, "ERC20: insufficient allowance");
        unchecked {
        _approve(owner, spender, currentAllowance - amount);
        }
        }
    }

    /**
     * @dev Hook that is called before any transfer of tokens. This includes
     * minting and burning.
     *
     * Calling conditions:
     *
     * - when `from` and `to` are both non-zero, `amount` of ``from``'s tokens
     * will be transferred to `to`.
     * - when `from` is zero, `amount` tokens will be minted for `to`.
     * - when `to` is zero, `amount` of ``from``'s tokens will be burned.
     * - `from` and `to` are never both zero.
     *
     * To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual {}

    /**
     * @dev Hook that is called after any transfer of tokens. This includes
     * minting and burning.
     *
     * Calling conditions:
     *
     * - when `from` and `to` are both non-zero, `amount` of ``from``'s tokens
     * has been transferred to `to`.
     * - when `from` is zero, `amount` tokens have been minted for `to`.
     * - when `to` is zero, `amount` of ``from``'s tokens have been burned.
     * - `from` and `to` are never both zero.
     *
     * To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
     */
    function _afterTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual {}

}
