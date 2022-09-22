// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract PaymentSplitterModified is Context, Ownable {
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

    function release(address payable account) public onlyOwner {
        require(_shares[account] > 0, "PaymentSplitter: account has no shares");
        uint256 payment = releasable(account);
        require(payment != 0, "PaymentSplitter: account is not due payment");
        _released[account] += payment;
        _totalReleased += payment;
        Address.sendValue(account, payment);
        emit PaymentReleased(account, payment);
    }

    function releaseERC20(IERC20 token, address account) public onlyOwner {
        require(_shares[account] > 0, "PaymentSplitter: account has no shares");
        uint256 payment = releasableERC20(token, account);
        require(payment != 0, "PaymentSplitter: account is not due payment");
        _erc20Released[token][account] += payment;
        _erc20TotalReleased[token] += payment;
        SafeERC20.safeTransfer(token, account, payment);
        emit ERC20PaymentReleased(token, account, payment);
    }

    function addNewPayees(address[] calldata payees, uint256[] calldata shares_) public onlyOwner {
        require(payees.length == shares_.length, "PaymentSplitter: payees and shares length mismatch");
        require(payees.length > 0, "PaymentSplitter: no payees");
        require(_payees.length == 0, "PaymentSplitter: please remove all the existing payees before adding new payees");
        for (uint256 i = 0; i < payees.length; i++) {
            _addPayee(payees[i], shares_[i]);
        }
    }

    function removeAllPayees(address[] calldata payees, uint256[] calldata shares_) public onlyOwner {
        require(_payees.length > 0, "PaymentSplitter: payees don't exist");
        require(_payees.length == payees.length, "Payment Splitter: payees and exisitng payees length mismatch");
        require(payees.length == shares_.length, "PaymentSplitter: payees and shares length mismatch");
        for (uint256 i = 0; i < payees.length; i++) {
            _removePayee(payees[i], shares_[i]);
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

    function totalReleased(IERC20 token) public view returns (uint256) {
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
        uint256 totalReceived = token.balanceOf(address(this)) + totalReleased(token);
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
        require(_shares[account] == shares_, "Payment Splitter: shares are incorrect");
        require(_payees[0] == account, "Payment Splitter: payee address is incorrect");
        _payees[0] = _payees[_payees.length - 1];
        _payees.pop();
        delete _shares[account];
        _totalShares = _totalShares - shares_;
        emit PayeeRemoved(account, shares_);
    }

    // PRIVATE FUNCTIONS //

    function _pendingPayment(address account, uint256 totalReceived, uint256 alreadyReleased) private view returns (uint256) {
        return (totalReceived * _shares[account]) / _totalShares - alreadyReleased;
    }
}
