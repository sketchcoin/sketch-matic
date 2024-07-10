// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;


import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./ISentry.sol";
import "./IVoucher.sol";


contract Sketch is 
    IERC20, 
    IERC20Metadata,
    ISentry,
    IVoucher,
    Pausable,
    AccessControl,
    ReentrancyGuard 
{

    // Balance Keeping Unit
    struct BKU {

        // This represents total amount of all the 'prepaid' transfer made to authroized address
        uint256 balance;

        // this is used to cross-check balance
        address[] allRecipients;

        mapping(address => uint256) ledger;
    }

    uint256 private immutable CAPPED_SUPPLY = 100_000_000_000 * 10 ** uint256(18);

    bytes32 public constant CEO_ROLE = keccak256("CEO_ROLE");
    bytes32 public constant CFO_ROLE = keccak256("CFO_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant SENTRY_ROLE = keccak256("SENTRY_ROLE");

    mapping(address => BKU) private _voucher;

    mapping(address => mapping(address => uint256)) private _allowances;
 
    mapping(address => uint256) private _balances;
 
    mapping(address => uint256) private _blacklist;

    /// The account additional supply is minted to.
    address private _mintAccount = address(0);

    // 10% of CAPPED SUPPLY at deployment
    uint256 private _totalSupply = 10_000_000_000 * 10 ** uint256(18);

    uint256 private immutable MINT_INTERVAL = 365 days;

    uint256 private _lastMintedTime;

    uint256 private _mintCount;

    string private _name;

    string private _symbol;

    constructor(
        address ceoRole, 
        address cfoRole, 
        address pauserRole, 
        address sentryRole
    ) {
        _name = "SketchCoin";
        _symbol = "SKETCH";

        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _grantRole(CEO_ROLE, ceoRole);
        _grantRole(CFO_ROLE, cfoRole);
        _grantRole(PAUSER_ROLE, pauserRole);
        _grantRole(SENTRY_ROLE, sentryRole);

        _balances[cfoRole] = _totalSupply;

        _lastMintedTime = block.timestamp;
    }

    function _settlerExists(address payer, address settler) internal view returns (bool) {
        uint256 len = _voucher[payer].allRecipients.length;
        for(uint i = 0; i < len; ++i) {
            if(settler ==  _voucher[payer].allRecipients[i]) {
                return true;
            }
        }

        return false;
    }

    function voucherBalanceOf(address payer)
    public view 
    returns(uint256) {
        require(address(0) != payer);
        return _voucher[payer].balance;
    }

    function settlerBalanceOf(address payer, address settler)
    public view 
    returns(uint256) {
        require(address(0) != payer);
        require(address(0) != settler);

        return _voucher[payer].ledger[settler];
    }

    function approveVoucher(address recipient, uint256 amount) 
    public 
    whenNotPaused
    transferrableFundOnly(_msgSender(), amount) 
    {

        require(0 == blacklistedTime(recipient));

        require(recipient != address(0));
        require(amount > uint256(0));

        address ms = _msgSender();

        // prevent self fund-distribution
        require(ms != recipient);
        
        require(0 == blacklistedTime(ms));

        _voucher[ms].balance += amount;
        _voucher[ms].ledger[recipient] += amount;
        
        
        if(!_settlerExists(ms, recipient)) {
            _voucher[ms].allRecipients.push(recipient);
        }

        emit ApproveVoucher(ms, recipient, amount);
    }   

    function settleVoucherAmount(address payer, uint256 amount)
    public 
    whenNotPaused 
    {

        address settler = _msgSender();

        require(0 == blacklistedTime(payer));

        require(0 == blacklistedTime(settler));

        require(address(0) != payer);
        require(address(0) != settler);

        // check eligilibility
        bool isValidSettler = _settlerExists(payer, settler);
        require(isValidSettler);

        // check balance for each recipient
        uint256 availableFundsForSettler = _voucher[payer].ledger[settler];
        require(availableFundsForSettler >= amount);

        // update payer bal
        _balances[payer] -= amount;

        // update BKU
        _voucher[payer].balance -= amount;
        _voucher[payer].ledger[settler] -= amount;

        _balances[settler] += amount;

        emit SettleVoucherAmount(settler, payer, amount);
    }

    function relinquishVoucherAmount(address payer, uint256 amount)
    public
    whenNotPaused 
    {

        address settler = _msgSender();

        require(0 == blacklistedTime(payer));
        
        require(0 == blacklistedTime(settler));

        require(address(0) != payer);
        require(address(0) != settler);

        bool isValidSettler = _settlerExists(payer, settler);
        require(isValidSettler);

        // check balance for each recipient
        uint256 availableFundsForSettler = _voucher[payer].ledger[settler];
        require(availableFundsForSettler >= amount);
           
        _voucher[payer].balance -= amount;
        _voucher[payer].ledger[settler] -= amount;

        emit RelinquishVoucherAmount(settler, payer, amount);
    }

    function mint() 
    public 
    whenNotPaused
    onlyRole(MINTER_ROLE) {
        require(_mintAccount != address(0));

        // check cool time
        require((block.timestamp - _lastMintedTime) > MINT_INTERVAL, "Invaliud mint time");

        uint256 amount = 100_000_000 * 10 ** uint256(18);
        if(_mintCount > 100) {
            amount = 88_888_889 * 10 ** uint256(18);
        }

        require(totalSupply() + amount <= CAPPED_SUPPLY, "Supply overflow");

        unchecked {
            // Overflow not possible: balance + amount is at most totalSupply + amount, which is checked above.
            _balances[_mintAccount] += amount;
        }
        _totalSupply += amount;

        _lastMintedTime = block.timestamp;
        _mintCount++;
        
        emit Transfer(address(0), _mintAccount, amount);
    }

    /// Setting account to address(0) disables minting
    function setMintAddress(address account)
    public 
    whenNotPaused 
    onlyRole(CFO_ROLE)
    {
        _mintAccount = account;
    }

    function mintAddress () 
    public view 
    onlyRole(CFO_ROLE)
    returns (address) {
        return _mintAccount;
    }

    function nextMint()
    public view 
    onlyRole(CFO_ROLE)
    returns (uint256) {

        return (MINT_INTERVAL / 1 days)  -  ((block.timestamp - _lastMintedTime) / 1 days);
    }

    /**
     * @dev Grants `role` to `account`.
     *
     * If `account` had not been already granted `role`, emits a {RoleGranted}
     * event.
     *
     * Requirements:
     *
     * - the caller must have ``role``'s admin role.
     *
     * May emit a {RoleGranted} event.
     */
    function grantRole(bytes32 role, address account) 
    public virtual override
    onlyRole(CEO_ROLE) {

        // we can't allow blacklisted account to hold any role
        require(0 == blacklistedTime(account));

        super._grantRole(role, account);
    }

    /**
     * @dev Revokes `role` from `account`.
     *
     * If `account` had been granted `role`, emits a {RoleRevoked} event.
     *
     * Requirements:
     *
     * - the caller must have ``role``'s admin role.
     *
     * May emit a {RoleRevoked} event.
     */
    function revokeRole(bytes32 role, address account) 
    public virtual override 
    onlyRole(CEO_ROLE) {

        super._revokeRole(role, account);
    }


    function pause() 
    public 
    adminOrPauser {
        _pause();
    }

    function unpause() 
    public 
    adminOrPauser {
        _unpause();
    }

    function addToBlacklist(address addr) 
    public
    staffOnly
    returns(bool success) {
        require(addr != address(0));

        if(0 == _blacklist[addr]) {
            _blacklist[addr] = block.timestamp;

            emit BlacklistedAddressAdded(addr, block.timestamp);
            return true;
        }

        // Certik: [SKE-09] fix
        emit BlacklistedAddressAdded(addr, _blacklist[addr]);
        return false;
    }

    function removeFromBlacklist(address addr)
    public 
    staffOnly
    returns(bool success) {
        require(addr != address(0));

        if(0 < _blacklist[addr]) {
            _blacklist[addr] = 0;

            emit BlacklistedAddressRemoved(addr, block.timestamp);
            return true;
        }

        emit BlacklistedAddressRemoved(addr, 0);
        return false;
    }


    /// No neet to check for zero(0) addr
    function blacklistedTime(address addr)
    public view
    returns (uint256 timestmap) {
        return _blacklist[addr];
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
     * Ether and Wei. This is the default value returned by this function, unless
     * it's overridden.
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
    function transfer(address to, uint256 amount) 
    whenNotPaused
    public virtual override returns (bool) {
        address owner = _msgSender();
        _transfer(owner, to, amount);
        return true;
    }

    /**
     * Certik: [SKE-05] fix
     * 
     * @dev See {IERC20-allowance}.
     */
    function allowance(address owner, address spender) public view virtual override returns (uint256) {

        uint256 currentAllowance = _allowances[owner][spender];

        uint256 voucherBalance = _voucher[owner].balance;

        // no need to check underflow
        uint256 availableMovableFund = _balances[owner] - voucherBalance;

        
        if(availableMovableFund >= currentAllowance) {
            return currentAllowance; 
        }

        return availableMovableFund;
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
    function approve(address spender, uint256 amount) 
    whenNotPaused
    public virtual override returns (bool) {
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
    function transferFrom(address from, address to, uint256 amount) 
    whenNotPaused
    public virtual override returns (bool) {
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
    function increaseAllowance(address spender, uint256 addedValue) 
    whenNotPaused
    public virtual returns (bool) {
        address owner = _msgSender();
        _approve(owner, spender, allowance(owner, spender) + addedValue);

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
     * 
     */
    function decreaseAllowance(address spender, uint256 subtractedValue)
    whenNotPaused 
    public virtual returns (bool) {
        address owner = _msgSender();
        uint256 currentAllowance = allowance(owner, spender);
        require(currentAllowance >= subtractedValue, "ERC20: decreased allowance below zero");
        unchecked {
            _approve(owner, spender, currentAllowance - subtractedValue);
        }

        return true;
    }

    /**
     * @dev Moves `amount` of tokens from `from` to `to`.
     *
     * This internal function is equivalent to {transfer}, and can be used to
     * e.g. implement automatic token fees, slashing mechanisms, etc.
     *
     * Emits a {Transfer} event.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     * - `from` must have a balance of at least `amount`.
     */
    function _transfer(address from, address to, uint256 amount) 
    transferrableFundOnly(from, amount)
    internal virtual {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");

        _beforeTokenTransfer(from, to, amount);
        
        unchecked {
            _balances[from] -= amount;
            // Overflow not possible: the sum of all balances is capped by totalSupply, and the sum is preserved by
            // decrementing then incrementing.
            _balances[to] += amount;
        }

        emit Transfer(from, to, amount);
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
    function _approve(address owner, address spender, uint256 amount) 
    transferrableFundOnly(owner, amount)
    internal virtual {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    /**
     * @dev Updates `owner` s allowance for `spender` based on spent `amount`.
     *
     * Does not update the allowance amount in case of infinite allowance.
     * Revert if not enough allowance is available.
     *
     * Might emit an {Approval} event.
     */
    function _spendAllowance(address owner, address spender, uint256 amount) internal virtual {
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
    function _beforeTokenTransfer(address from, address to, uint256 amount) internal virtual {

        /// we need to check both address
        require(0 == blacklistedTime(from));
        require(0 == blacklistedTime(to));
        require(amount > 0);
    }

    modifier transferrableFundOnly(address account, uint256 amount) {
  
        uint256 fund = _balances[account] - _voucher[account].balance;
        require(fund >= amount );
        _;
    }

    modifier staffOnly {
        require(
               hasRole(DEFAULT_ADMIN_ROLE, _msgSender())
            || hasRole(PAUSER_ROLE, _msgSender())
            || hasRole(SENTRY_ROLE, _msgSender())
        );
        _;
    }


    modifier adminOrPauser {
        require(
               hasRole(DEFAULT_ADMIN_ROLE, _msgSender())
            || hasRole(PAUSER_ROLE, _msgSender())
        );
        _;
    }
}
