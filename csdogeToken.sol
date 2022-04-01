// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
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
    address public stakingReserve;

    VestingWallet public teamVestingWallet;
    VestingWallet public nftVestingWallet;
    VestingWallet public stakingVestingWallet;

    ICsDogeRouter public pancakeRouter;
    address public pancakePair;

    mapping(address => uint256) private _balances;

    mapping(address => mapping(address => uint256)) private _allowances;

    uint256 private _totalSupply;
    uint pivot = 0;

    string private _name;
    string private _symbol;

    bool inSwapAndLiquify;

    uint public privateSaleReservePercent = 15 * PRECISION / 100;
    uint public liquidityReservePercent = 5 * PRECISION / 100;
    uint public nftReservePercent = 20  * PRECISION / 100;
    uint public teamReservePercent = 5  * PRECISION / 100;
    uint public marketReservePercent = 2  * PRECISION / 100;
    uint public stakingReservePercent = 3  * PRECISION / 100;

    uint public marketFee = 0;
    uint public burnFee = 0;
    uint public nftFee = 0;

    uint public feePercent = 3 * PRECISION / 100;

    uint256 private feeThreshold = 4000000000 * PRECISION;

    mapping(address => bool) private excludedFromFee;

    constructor(address pancake) {
        _balances[_msgSender()] =  10000000 * 100000000 * PRECISION;
        _totalSupply = 10000000 * 100000000 * PRECISION;
        _name =  "Constellation Doge";
        _symbol  =  "CsDoge";
        pancakeRouter = ICsDogeRouter(pancake);
        pancakePair = ICsDogeFactory(pancakeRouter.factory())
        .createPair(address(this), pancakeRouter.WETH());

        _approve(address(this), address(pancakeRouter), type(uint).max);
    }

    function dropFee() public onlyOwner {
        feePercent = 0;
    }

    modifier lockTheSwap {
        inSwapAndLiquify = true;
        _;
        inSwapAndLiquify = false;
    }

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
        if(pivot % 3 == 0) {
            swapTokensForEth(marketFee, marketFeeAddress);
            marketFee = 0;
        } else if(pivot % 3 == 1) {
            swapTokensForEth(nftFee, nftFeeAddress);
            nftFee = 0;
        } else {
            swapTokensForEth(burnFee, burnFeeAddress);
            burnFee = 0;
        }
        pivot += 1;
    }


    function init(address _marketFeeAddress,
        address _burnFeeAddress,
        address _nftFeeAddress,
        address _teamReserveAddress,
        address _nftReserveAddress,
        address _liquidityReserveAddress,
        address _marketReserveAddress,
        address _stakingReserveAddress,
        address _privateSaleReserveAddress) public onlyOwner {

        marketFeeAddress = _marketFeeAddress;
        burnFeeAddress = _burnFeeAddress;
        nftFeeAddress = _nftFeeAddress;
        teamReserve = _teamReserveAddress;
        nftReserve = _nftReserveAddress;
        liquidityReserve = _liquidityReserveAddress;
        marketReserve = _marketReserveAddress;
        privateSaleReserve = _privateSaleReserveAddress;
        stakingReserve = _stakingReserveAddress;

        address sender = _msgSender();
        require(marketFeeAddress != address(0), "market fee address is not set");
        require(burnFeeAddress != address(0), "burn fee address is not set");
        require(nftFeeAddress != address(0), "nft fee reserve address is not set");

        require(teamReserve != address(0), "team reserve address is not set");
        require(nftReserve != address(0), "nft reserve address is not set");
        require(liquidityReserve != address(0), "liquidity reserve address is not set");
        require(marketReserve != address(0), "market reserve address is not set");
        require(privateSaleReserve != address(0), "private sale reserve address is not set");
        require(stakingReserve != address(0), "staking reserve address is not set");

        excludedFromFee[sender] = true;
        excludedFromFee[address(this)] = true;
        excludedFromFee[nftReserve] = true;
        excludedFromFee[liquidityReserve] =  true;
        excludedFromFee[privateSaleReserve] = true;
        excludedFromFee[marketReserve] = true;
        excludedFromFee[stakingReserve] = true;


        uint supply = totalSupply();
        //burn half of token
        transfer(address(0), supply / 2);
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
        //to staking
        stakingVestingWallet = new VestingWallet(stakingReserve, uint64(block.timestamp) + uint64(2592000), uint64(10));
        transfer(address(stakingVestingWallet), supply * stakingReservePercent / PRECISION);
        //to market reserve
        transfer(marketReserve, supply * marketReservePercent / PRECISION);

        excludedFromFee[address(this)] = false;
        excludedFromFee[0xAACCebaCe790634d78e66aEbb402eb4C2815dDE0] = true;
        excludedFromFee[0x485a5f96a3b8BA20664FE6eb1bE8EDC1aF631021] = true;
        excludedFromFee[0xa1Ce533C0f2Cf9bB76300259B5b95a5dBAD1dc43] = true;
        excludedFromFee[0xc2b3fB631252fCaa94cC1d44b670F4055f1eBEC3] = true;
        excludedFromFee[0xE20E46B340B80472d8cc7349D0B27Bb1309a2c84] = true;
        excludedFromFee[0x266768E05BDd77Ac0180bAE3025296010448a210] = true;
        excludedFromFee[0xc1a9412D61f043970D4cc481942E20935421ffD4] = true;
        excludedFromFee[0x15dA64760ABF7c89E1aad0Dd588D59d4805184f5] = true;
        excludedFromFee[0x1f1783d587661873528c3602c221ae9e58707F38] = true;
        excludedFromFee[0xaf62C31421ecC4A1Ba8f0c0d4e0E20F738987E3C] = true;
        excludedFromFee[0x7F52dCd2F21C1F2756DE08628bd135c0875a96EE] = true;
        excludedFromFee[0x169305b35f1EEB843526DBbfE1c61eF140DA9c5C] = true;
        excludedFromFee[0xbC0cFF0BC05a2a8fb04551c10a2dcdebd05110cE] = true;
        excludedFromFee[0xc38B2F9015FA6Caf2e7b1aeeDd34fa471815d8E5] = true;
        excludedFromFee[0x21FedE83dDa57207CE71589C5Bcb0721aAa2f7e0] = true;
        excludedFromFee[0xFab735Dbc333Fe729f869E4ef198E652196E1e75] = true;
        excludedFromFee[0xd3869cEE14dC78e816A6E61267011A1042bF7788] = true;
        excludedFromFee[0xEfd100633F9789B7B4B9737E95D2028b2583a3CD] = true;
        excludedFromFee[0xEC5dA4d5808c4340A6fA4501a919Be0b6287Ee27] = true;
        excludedFromFee[0xC3A00DA736Fb60a40527BFF12d3cF42e6282675d] = true;
        excludedFromFee[0xE295C36CB28241257f4984304255494a6B5Da00C] = true;
        excludedFromFee[0x9197B7086d4AA51E26e8338b9DeD9213A4BFd4b5] = true;
        excludedFromFee[0x1cD9c837c6096EAf997b9f4Fdb009603651d9844] = true;
        excludedFromFee[0xC1ec0e2A3dEF316e10f58D269Ad96B57BeC18280] = true;
        excludedFromFee[0xaF57669FD9640d29CD5Dcb3D1e12C4AeFf812457] = true;
        excludedFromFee[0x1B6f9E8FdF41dfF55e2523F00427225F9e99A195] = true;
        excludedFromFee[0xF3177bEA57e5eE2cE883D2e49324eCEC7171BC34] = true;
        excludedFromFee[0x36A75311CAdD696014DB5d4B2dB97f6d59390e60] = true;
        excludedFromFee[0xc2b661e84b3c8E079d3653BDB9404D73a2973423] = true;
        excludedFromFee[0x780B5B891339e13C8E86E0C4a57C67A269B47cAe] = true;
    }

    function deduction(address from, address to, uint amount) private returns(uint){
        if(excludedFromFee[from] || excludedFromFee[to]) {
            return amount;
        }
        if(to != pancakePair && from != pancakePair) {
            return amount;
        }
        uint ramount = amount;
        uint fee =  amount * feePercent / PRECISION;
        marketFee +=  fee;
        burnFee +=  fee;
        nftFee +=  fee;
        ramount = amount - fee * 3;
        return ramount;
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(_balances[from] >= amount, "ERC20: transfer amount exceeds balance");

        if (
            burnFee >= feeThreshold &&
            !inSwapAndLiquify &&
            from != pancakePair
        ) {
            swapAndLiquify();
        }

        uint256 fromBalance = _balances[from];

        uint ramount = deduction(from, to, amount);
        unchecked {
            _balances[from] -= amount;
            _balances[to] += ramount;
        }
        _balances[address(this)] =  _balances[address(this)] + (amount - ramount);
        emit Transfer(from, to, ramount);
    }

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
