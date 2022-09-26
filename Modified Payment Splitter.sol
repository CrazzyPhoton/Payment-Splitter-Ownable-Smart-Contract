// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract PaymentSplitter is Context, Ownable {
    event PayeeAdded(address account, uint256 shares);
    event PayeeRemoved(address account, uint256 shares);
    event PaymentReleased(address to, uint256 amount);
    event ERC20PaymentReleased(IERC20 indexed token, address to, uint256 amount);
    event PaymentReceived(address from, uint256 amount);

    uint256 private _totalShares;
    uint256 private _totalReleased;

    mapping(address => uint256) private _shares;
    mapping(address => uint256) private _released;
    address[] private _payees;

    mapping(IERC20 => uint256) private _erc20TotalReleased;
    mapping(IERC20 => mapping(address => uint256)) private _erc20Released;

    // EXTERNAL FUNCTIONS //

    receive() external payable virtual {
        emit PaymentReceived(_msgSender(), msg.value);
    }

    // WRITE CONTRACT PUBLIC FUNCTIONS //
    // SMART CONTRACT OWNER ONLY FUNCTIONS //

    /**
     * @notice Function adds new payees and their shares,
     * payees addresses are to be wrote in an array form like this ["address1","address2","address3"] and
     * shares are also to be wrote in an array form like this [share1,share2,share3]
     * such that address1 will share1, address2 will receive share2 and address3 will receive share3.
     * If you want to add more payees afterwards you will have to remove all the existing payees before,
     * use the removeAllPayees function for this.
     * Individual share must be an integer. 
     * Sum of all shares must be a power of 10 which is 100,1000,10000,... 
     * such that shares are distributed properly according to the expected share percentage.
     */
    function addNewPayees(address[] calldata payees, uint256[] calldata shares_) public onlyOwner {
        require(payees.length == shares_.length, "PaymentSplitter: payees and shares length mismatch");
        require(payees.length > 0, "PaymentSplitter: no payees");
        require(_payees.length == 0, "PaymentSplitter: please remove all the existing payees before adding new payees");
        for (uint256 i = 0; i < payees.length; i++) {
            _addPayee(payees[i], shares_[i]);
        }
    }

    /**
     * @notice Function removes all the existing payees and their shares,
     * payees addresses are to be wrote in an array form like this ["address1","address2","address3"] and
     * shares are also to be wrote in an array form like this [share1,share2,share3].
     * Enter all the exisitng payees in the array.
     * Entered shares must be the exact shares owed by the payees.
     * Enter the array of payees in the payees field and the array of shares in the shares_ field.
     */
    function removeAllPayees(address[] calldata payees, uint256[] calldata shares_) public onlyOwner {
        require(_payees.length > 0, "PaymentSplitter: payees don't exist");
        require(_payees.length == payees.length, "Payment Splitter: payees and exisitng payees length mismatch");
        require(payees.length == shares_.length, "PaymentSplitter: payees and shares length mismatch");
        for (uint256 i = 0; i < payees.length; i++) {
            _removePayee(payees[i], shares_[i]);
        }
    }

    /**
     * @notice Function withdraws the ETH accumulated in the smart contract to the payees according to their shares.
     * Function can withdraw shares owed by one or more payees.
     * Payees addresses are to be wrote in an array form like this ["address1","address2","address3"].
     * Enter the array of payees in payees field.
     */
    function release(address[] calldata payees) public onlyOwner {
        for (uint256 i = 0; i < payees.length; i++) {
            _release(payable(payees[i]));
        }
    }

    /**
     * @notice Function withdraws the accumulated ERC20 tokens in the smart contract to the payees according to their shares.
     * Function can withdraw shares owed by one or more payees.
     * Enter the ERC20 token contract address in the token field and the payees addresses in an array form like this ["address1","address2","address3"] in the payees field.
     */
    function releaseERC20(IERC20 token, address[] calldata payees) public onlyOwner {
        for (uint256 i = 0; i < payees.length; i++) {
            _releaseERC20(token, payees[i]);
        }
    }

    // READ CONTRACT FUNCTIONS //
    // GETTER PUBLIC FUNCTIONS //

    function totalShares() public view returns (uint256) {
        return _totalShares;
    }

    function totalReleased() public view returns (uint256) {
        return _totalReleased;
    }

    function totalReleasedERC20(IERC20 token) public view returns (uint256) {
        return _erc20TotalReleased[token];
    }

    function shares(address account) public view returns (uint256) {
        return _shares[account];
    }

    function released(address account) public view returns (uint256) {
        return _released[account];
    }

    function releasedERC20(IERC20 token, address account) public view returns (uint256) {
        return _erc20Released[token][account];
    }

    function payee(uint256 index) public view returns (address) {
        return _payees[index];
    }

    function releasable(address account) public view returns (uint256) {
        uint256 totalReceived = address(this).balance + totalReleased();
        return _pendingPayment(account, totalReceived, released(account));
    }

    function releasableERC20(IERC20 token, address account) public view returns (uint256) {
        uint256 totalReceived = token.balanceOf(address(this)) + totalReleasedERC20(token);
        return _pendingPayment(account, totalReceived, releasedERC20(token, account));
    }

    // INTERNAL FUNCTIONS //
    
    function _addPayee(address account, uint256 shares_) internal {
        require(account != address(0), "PaymentSplitter: account is the zero address");
        require(shares_ > 0, "PaymentSplitter: shares are 0");
        require(_shares[account] == 0, "PaymentSplitter: account already has shares");
        _payees.push(account);
        _shares[account] = shares_;
        _totalShares = _totalShares + shares_;
        emit PayeeAdded(account, shares_);
    }
    
    function _removePayee(address account, uint256 shares_) internal {
        require(_shares[account] == shares_, "PaymentSplitter: shares are incorrect");
        require(_payees[0] == account, "PaymentSplitter: payee address is incorrect");
        _payees[0] = _payees[_payees.length - 1];
        _payees.pop();
        delete _shares[account];
        _totalShares = _totalShares - shares_;
        emit PayeeRemoved(account, shares_);
    }

    function _release(address payable account) internal {
        require(_shares[account] > 0, "PaymentSplitter: account has no shares");
        uint256 payment = releasable(account);
        require(payment != 0, "PaymentSplitter: account is not due payment");
        _released[account] += payment;
        _totalReleased += payment;
        Address.sendValue(account, payment);
        emit PaymentReleased(account, payment);
    }

    function _releaseERC20(IERC20 token, address account) internal {
        require(_shares[account] > 0, "PaymentSplitter: account has no shares");
        uint256 payment = releasableERC20(token, account);
        require(payment != 0, "PaymentSplitter: account is not due payment");
        _erc20Released[token][account] += payment;
        _erc20TotalReleased[token] += payment;
        SafeERC20.safeTransfer(token, account, payment);
        emit ERC20PaymentReleased(token, account, payment);
    }

    // PRIVATE FUNCTIONS //

    function _pendingPayment(address account, uint256 totalReceived, uint256 alreadyReleased) private view returns (uint256) {
        return (totalReceived * _shares[account]) / _totalShares - alreadyReleased;
    }
}
