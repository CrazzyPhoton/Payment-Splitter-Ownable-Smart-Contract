// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol"; 
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract PaymentSplitter is Context, Ownable {

    /// @notice Address array of payees.
    address[] private _payees;

    /// @notice Contract addresses array for all the types of ERC20 tokens withdrawn from the smart contract.
    IERC20[] private _erc20TokensWithdrawn;
    
    
    /// @notice Event emitted by the smart contract when a payee is added.
    event PayeeAdded(address account, uint256 shares);
    
    /// @notice Event emitted by the smart contract when a payee is removed.
    event PayeeRemoved(address account, uint256 shares);

    /// @notice Event emitted by the smart contract when ETH is withdrawn to a payee.
    event PaymentReleased(address to, uint256 amount);

    /// @notice Event emitted by the smart contract when ERC20 tokens are being withdrawn to a payee.
    event ERC20PaymentReleased(IERC20 indexed token, address to, uint256 amount);

    /// @notice Event emitted by the smart contract when the smart contract receives ETH.
    event PaymentReceived(address from, uint256 amount);

    
    /// @notice Mapping for shares of the payees.
    mapping(address => uint256) private _shares;

    /// @notice Mapping for amount of ETH withdrawn to a payee from the smart contract.
    mapping(address => uint256) private _released;

    /// @notice Mapping for total amount of ERC20 tokens withdrawn from the smart contract.
    mapping(IERC20 => uint256) private _erc20TotalReleased;

    /// @notice Mapping for amount of ERC20 tokens withdrawn to a payee from the smart contract.
    mapping(IERC20 => mapping(address => uint256)) private _erc20Released;

    /// @notice Mapping for whether a type of ERC20 token has been withdrawn from the smart contract.
    mapping(IERC20 => bool) private erc20TokenWithdrawn;


    /// @notice Uint256 for total share count.
    uint256 private _totalShares;
    
    /// @notice Uint256 for total ETH withdrawn from the smart contract.
    uint256 private _totalReleased;

    // EXTERNAL FUNCTIONS //

    /// @notice External function which is called when receiving ETH to the smart contract.
    receive() external payable virtual {
        emit PaymentReceived(_msgSender(), msg.value);
    }

    // WRITE CONTRACT FUNCTIONS, SMART CONTRACT OWNER ONLY FUNCTIONS //

    /**
     * @notice Smart contract owner only function.
     * Function adds new payees and their shares.
     * Individual share must be an integer.
     * Sum of all shares must be a power of 10 which is 100,1000,10000,... such that shares are distributed properly according to the expected share percentage.
     * Enter the payees addresses in an array form in the 'payees (address[])' field like this ["address1","address2","address3"] .
     * Enter the shares in an array form in the 'shares_ (uint256[])' field like this [share1,share2,share3] .
     * Such that address1 will receive share1, address2 will receive share2 and address3 will receive share3.
     * After filling out all the fields click on write to execute the function.
     * If you want to add more payees afterwards you will have to remove all the existing payees first, use the removeAllPayees function for this.
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
     * @notice Smart contract owner only function.
     * Function removes all the existing payees along with their shares.
     * Click on write to execute the function.
     */
    function removeAllPayees() public onlyOwner {
        require(_payees.length > 0, "PaymentSplitter: payees don't exist");
        uint256 numberOfExistingPayees = _payees.length;
        for (uint256 i = 0; i < numberOfExistingPayees; i++) {
            _totalShares = _totalShares - _shares[_payees[i]];
            emit PayeeRemoved(_payees[i], _shares[_payees[i]]);
            delete _shares[_payees[i]];
            _released[_payees[i]] = 0;
        }
        _totalReleased = 0;
        if (_erc20TokensWithdrawn.length > 0) {
           for (uint256 i = 0; i < _erc20TokensWithdrawn.length; i++) {
               for (uint256 j = 0; j < numberOfExistingPayees; j++) {
                   _erc20Released[_erc20TokensWithdrawn[i]][_payees[j]] = 0;
                }
                _erc20TotalReleased[_erc20TokensWithdrawn[i]] = 0;
            }
        }
        for (uint256 i = 0; i < numberOfExistingPayees; i++) {
            _payees[0] = _payees[_payees.length - 1];
            _payees.pop();
        }
    }

    /**
     * @notice Smart contract owner only function.
     * Function withdraws the ETH accumulated in the smart contract to the payees according to their shares.
     * Function can withdraw shares owed by one or more payees.
     * Enter the payees addresses in an array form in the 'payees (address[])' field like this ["address1","address2","address3"].
     * After filling out the field click on write to execute the function.
     */
    function release(address[] calldata payees) public onlyOwner {
        for (uint256 i = 0; i < payees.length; i++) {
            _release(payable(payees[i]));
        }
    }

    /** 
     * @notice Smart contract owner only function.
     * Function withdraws the ETH accumulated in the smart contract to all the payees according to their shares.
     * Click on write to execute the function.
     */
    function releaseForAll() public onlyOwner {
        require(_payees.length > 0, "PaymentSplitter: payees don't exist");
        for (uint256 i = 0; i < _payees.length; i++) {
            _release(payable(_payees[i]));
        }
    }

    /**
     * @notice Smart contract owner only function.
     * Function withdraws the accumulated ERC20 tokens in the smart contract to the payees according to their shares.
     * Function can withdraw shares owed by one or more payees.
     * Enter the ERC20 token contract address in the 'token (address)' field and the payees addresses in an array form like this ["address1","address2","address3"] in the 'payees (address[])' field.
     * After filling out all the fields click on write to execute the function.
     */
    function releaseERC20(IERC20 token, address[] calldata payees) public onlyOwner {
        for (uint256 i = 0; i < payees.length; i++) {
            _releaseERC20(token, payees[i]);
        }
        if (erc20TokenWithdrawn[token] == false) {
           _erc20TokensWithdrawn.push(token);
           erc20TokenWithdrawn[token] == true;
        }
    }

    /** 
     * @notice Smart contract owner only function.
     * Function withdraws the accumulated ERC20 tokens in the smart contract to all the payees according to their shares.
     * Enter the ERC20 token contract address in the 'token (address)' field.
     * After filling out the field click on write to execute the function.
     */
    function releaseERC20ForAll(IERC20 token) public onlyOwner {
        require(_payees.length > 0, "PaymentSplitter: payees don't exist");
        for (uint256 i = 0; i < _payees.length; i++) {
            _releaseERC20(token, _payees[i]);
        }
        if (erc20TokenWithdrawn[token] == false) {
           _erc20TokensWithdrawn.push(token);
           erc20TokenWithdrawn[token] == true;
        }
    }

    // READ CONTRACT FUNCTIONS, GETTER FUNCTIONS //

    /** 
     * @notice Function queries and returns the payee at a particular index or position in the payees array.
     * The first payee in the payees array would be at index 0 and so on.
     * Enter the index in the 'index (uint256)' field.
     * After filling out the field click on query to execute the function.
     */
    function payee(uint256 index) public view returns (address) {
        return _payees[index];
    }

    /** 
     * @notice Function queries and returns the amount of shares associated with a payee address.
     * Enter the payee's address in the 'account (address)' field.
     * After filling out the field click on query to execute the function.
     */
    function shares(address account) public view returns (uint256) {
        return _shares[account];
    }

    /** 
     * @notice Function queries and returns the total share count of existing payees.
     * Click on query to execute the function.
     */
    function totalShares() public view returns (uint256) {
        return _totalShares;
    }

    /** 
     * @notice Function queries and returns the amount of ETH withdrawn for a payee address from the smart contract.
     * Enter the payee's address in the 'account (address)' field.
     * After filling out the field click on query to execute the function.
     */
    function released(address account) public view returns (uint256) {
        return _released[account];
    }

    /** 
     * @notice Function queries and returns the amount of ERC20 tokens withdrawn for a payee address from the smart contract.
     * Enter the ERC20 token contract address in the 'token (address)' field.
     * Enter the payee's address in the 'account (address)' field.
     * After filling out all the fields click on query to execute the function.
     */
    function releasedERC20(IERC20 token, address account) public view returns (uint256) {
        return _erc20Released[token][account];
    }

    /** 
     * @notice Function queries and returns the total amount ETH withdrawn from the smart contract for existing payees.
     * Click on query to execute the function.
     */
    function totalReleased() public view returns (uint256) {
        return _totalReleased;
    }

    /**
     * @notice Function queries and returns the total amount ERC20 tokens withdrawn from the smart contract for existing payees.
     * Enter the ERC20 token contract address in the 'token (address)' field.
     * After filling out the field click on query to execute the function.
     */
    function totalReleasedERC20(IERC20 token) public view returns (uint256) {
        return _erc20TotalReleased[token];
    }

    /** 
     * @notice Function queries and returns the amount of ETH which is yet to be withdrawn for a payee address from the smart contract.
     * Enter the payee's address in the 'account (address)' field.
     * After filling out the field click on query to execute the function.
     */
    function releasable(address account) public view returns (uint256) {
        uint256 totalReceived = address(this).balance + totalReleased();
        return _pendingPayment(account, totalReceived, released(account));
    }

    /** 
     * @notice Function queries and returns the amount of ERC20 tokens yet to be withdrawn for a payee address from the smart contract.
     * Enter the ERC20 token contract address in the 'token (address)' field.
     * Enter the payee's address in the 'account (address)' field.
     * After filling out all the fields click on query to execute the function.
     */
    function releasableERC20(IERC20 token, address account) public view returns (uint256) {
        uint256 totalReceived = token.balanceOf(address(this)) + totalReleasedERC20(token);
        return _pendingPayment(account, totalReceived, releasedERC20(token, account));
    }

    /**
     * @notice Function queries and returns the existing payees.
     * Click on query to execute the function.
     */
    function existingPayees() public view returns (address[] memory _existingPayees) {
        require(_payees.length > 0, "PaymentSplitter: payees don't exist");
        _existingPayees = new address[](_payees.length);
        for (uint256 i = 0; i < _payees.length; i++) {
            _existingPayees[i] = _payees[i];
        }
        return _existingPayees;
    }

    /**
     * @notice Function queries and returns the shares of all the existing payees.
     * Click on query to execute the function.
     */
    function sharesOfExistingPayees() public view returns (uint256[] memory _sharesOfExistingPayees) {
        require(_payees.length > 0, "PaymentSplitter: payees don't exist");
        _sharesOfExistingPayees = new uint256[](_payees.length);
        for (uint256 i = 0; i < _payees.length; i++) {
            _sharesOfExistingPayees[i] = _shares[_payees[i]];
        }
        return _sharesOfExistingPayees;
    }

    /**
     * @notice Function queries and returns the contract addresses of all the types of ERC20 tokens withdrawn from the smart contract.
     * Click on query to execute the function.
     */
    function withdrawnERC20Tokens() public view returns (IERC20[] memory erc20TokenAddresses) {
        require(_erc20TokensWithdrawn.length > 0, "PaymentSplitter: no erc20 tokens withdrawn");
        erc20TokenAddresses = new IERC20[](_erc20TokensWithdrawn.length);
        for (uint256 i = 0; i < _erc20TokensWithdrawn.length; i++) {
            erc20TokenAddresses[i] = _erc20TokensWithdrawn[i];
        }
        return erc20TokenAddresses;
    }

    // INTERNAL FUNCTIONS //
    
    /// @notice Internal function which is called when the payees are being added to the smart contract.
    function _addPayee(address account, uint256 shares_) internal {
        require(account != address(0), "PaymentSplitter: account is the zero address");
        require(shares_ > 0, "PaymentSplitter: shares are 0");
        require(_shares[account] == 0, "PaymentSplitter: account already has shares");
        _payees.push(account);
        _shares[account] = shares_;
        _totalShares = _totalShares + shares_;
        emit PayeeAdded(account, shares_);
    }

    /// @notice Internal function which is called when ETH is being withdrawn to the payees according to their shares. 
    function _release(address payable account) internal {
        require(_shares[account] > 0, "PaymentSplitter: account has no shares");
        uint256 payment = releasable(account);
        if (payment != 0) {
           _totalReleased += payment;
           unchecked {_released[account] += payment;}
           Address.sendValue(account, payment);
           emit PaymentReleased(account, payment);
        }
    }

    /// @notice Internal function which is called when ERC20 tokens are being withdrawn to the payees according to their shares.
    function _releaseERC20(IERC20 token, address account) internal {
        require(_shares[account] > 0, "PaymentSplitter: account has no shares");
        uint256 payment = releasableERC20(token, account);
        if (payment != 0) {
           _erc20TotalReleased[token] += payment;
           unchecked {_erc20Released[token][account] += payment;}
           SafeERC20.safeTransfer(token, account, payment);
           emit ERC20PaymentReleased(token, account, payment);
        }
    }

    /// @notice Internal function which is called when ETH and ERC20 tokens are being withdrawn to the payees according to their shares.
    function _pendingPayment(address account, uint256 totalReceived, uint256 alreadyReleased) internal view returns (uint256) {
        return (totalReceived * _shares[account]) / _totalShares - alreadyReleased;
    }
}
