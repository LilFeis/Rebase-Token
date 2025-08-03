//SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol"; 
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";


/**
 * @title RebaseToken
 * @author Victor Carilla
 * @notice This is going to be a cross-chain rebase token that incentivises users to deposit into a vault 
 * and gain interest in rewards.
 * @notice The interest reate in the smart contract can only decrease.
 * @notice Each user will have their own interest rate that is the global interest rate at the time of deposit.
 */
contract RebaseToken is ERC20, Ownable, AccessControl {
     /////////////////////
    // Errors
    /////////////////////
    error RebaseToken__InterestRateCanOnlyDecrease(uint256 currentInterestRate, uint256 newInterestRate);

    /////////////////////
    // State Variables
    /////////////////////
    uint256 private constant PRECISION_FACTOR = 1e18; 
    bytes32 private constant MINT_AND_BURN_ROLE = keccak256("MINT_AND_BURN_ROLE");

    uint256 private s_interestRate = 5e10; // 10^-8 = 1/10^8
    mapping (address => uint256) private s_userInterestRates;
    mapping (address => uint256) private s_userLastUpdatedTimestamp;  


    /////////////////////
    // Events
    /////////////////////
    event InterestRateSet(uint256 newInterestRate);

    /////////////////////
    // Constructor
    /////////////////////
    constructor () ERC20("Rebase Token", "RBT") Ownable(msg.sender) {}

    /////////////////////
    // Functions
    /////////////////////

    function grantMintAndBurnRole(address _account) external onlyOwner {
        _grantRole(MINT_AND_BURN_ROLE, _account);
    }

    /**
     * @param _newInterestRate The new interest rate to set for the token.
     * @notice This function allows to set a new interest rate for the token.
     * @dev The interest rate can only be decreased, not increased.
     */
    function setInterestRate(uint256 _newInterestRate) external onlyOwner {
        // Set the interest rate  
        if (_newInterestRate >= s_interestRate) {
            revert RebaseToken__InterestRateCanOnlyDecrease(s_interestRate, _newInterestRate);
        }
        s_interestRate = _newInterestRate;
        emit InterestRateSet(_newInterestRate);
    }

    /**
     * @notice Mint the user tokens when they deposit into the vault.
     * @param _to The address of the user to mint tokens for.
     * @param _amount The amount of tokens minted to the user.
     */
    function mint(address _to, uint256 _amount, uint256 _interestRate) external onlyRole(MINT_AND_BURN_ROLE) {
        _mintAccruedInterest(_to);
        s_userInterestRates[_to] = _interestRate; // Set the user's interest rate to the current interest rate
        _mint(_to, _amount);
    }

    /**
     * @notice Burn the user tokens when they withdraw from the vault.
     * @param _from The address of the user to burn tokens from.
     * @param _amount The amount of tokens to burn from the user.
     */
    function burn(address _from, uint256 _amount) external onlyRole(MINT_AND_BURN_ROLE) {
        // if(_amount == type(uint256).max) {
        //     _amount = super.balanceOf(_from); // If the amount is max, burn all the tokens 
        //                                         // balanceOf() calculate the actual amount+interest so there is no delay(dust)
        //                                         //common pattern to use in DeFi protocols
        // }
        _mintAccruedInterest(_from);
        _burn(_from, _amount);
    }

    /**
     * @notice Mint the accrued interest to the user since the last time they interacted with the protocol (mint, burn, transfer,...)
     * @param _user The user to mint the accrued interest to.
     */
    function _mintAccruedInterest(address _user) internal {
        // (1)find their currest balance of rebase tokens that have been minted to the user --> principal balance
        uint256 previousBalance = super.balanceOf(_user);
        // (2)calculate their current balance including any interest --> balanceOf()
        uint256 currentBalance = balanceOf(_user);
        // (3) --> (2) - (1) calculate the number of tokens that need to be minted to the user
        uint256 balanceIncrease = currentBalance - previousBalance;
        // set the users last timestamp
        s_userLastUpdatedTimestamp[_user] = block.timestamp;   
        // call _mint to mint the tokens to the user
        _mint(_user, balanceIncrease); // here we already emiting an event

    }

    /**
     * @notice Calculate the balance of the user including accumulated interest.
     * (principal balance + interest accrued)
     * @param _user The address of the user to calculate the balance for.
     * @return The balance of the user including accumulated interest.
     */
    function balanceOf(address _user) public view override returns (uint256) {
        //get the current balance of the user (the numbers of the tokens that have actually been minted to the user)
        //multiply the principal balance by the interest rate 
        return super.balanceOf(_user) * _calculateUserAccumulatedInterest(_user) / PRECISION_FACTOR;
    }

    function transfer(address _recipient, uint256 _amount) public override returns (bool) {
        _mintAccruedInterest(msg.sender); // Mint accrued interest to the sender before transferring
        _mintAccruedInterest(_recipient); // Mint accrued interest to the recipient before transferring
        if (_amount == type(uint256).max) {
            _amount = super.balanceOf(msg.sender); // If the amount is max, transfer all the tokens
        }
        if (balanceOf(_recipient) == 0) {
            s_userInterestRates[_recipient] = s_userInterestRates[msg.sender]; // Set the recipient's interest rate to the current interest rate
        }
        return super.transfer(_recipient, _amount); // Call the parent transfer function
    }

    function transferFrom(address _sender, address _recipient, uint256 _amount) public override returns (bool) {
        _mintAccruedInterest(_sender); // Mint accrued interest to the sender before transferring
        _mintAccruedInterest(_recipient); // Mint accrued interest to the recipient before transferring
        if (_amount == type(uint256).max) {
            _amount = super.balanceOf(_sender); // If the amount is max, transfer all the tokens
        }
        if (balanceOf(_recipient) == 0) {
            s_userInterestRates[_recipient] = s_userInterestRates[_sender]; // Set the recipient's interest rate to the current interest rate
        }
        return super.transferFrom(_sender, _recipient, _amount); // Call the parent transferFrom function
    }

    /**
     * @notice Get the principal balance of the user, without interest.
     * @param _user The address of the user to get the principal balance for.
     * @return The principal balance of the user, without interest.
     */
    function principalBalanceOf(address _user) external view returns (uint256) {
        // This function returns the principal balance of the user, without interest
        return super.balanceOf(_user);
    }

    /**
     * @notice Calculate the accumulated interest for a user.
     * @param _user The address of the user to calculate the accumulated interest for.
     * @return linearInterest The accumulated interest for the user.
     */
    function _calculateUserAccumulatedInterest(address _user) 
        internal
        view 
        returns (uint256 linearInterest) 
    {
        // we need to calculate the interest accrued since the last time the user was updated
        // this is goingt to be the linear growth with time
        // 1. calculate the time since the last update
        // 2. calculate the amount of linear growth
        // Example:
        // deposit -> 10 tokens
        // interest rate -> 0.5 per second
        // time elapsed -> 2 seconds
        // 10 + (10*0.5 * 2) = 10 + 10 = 20 tokens
        // pa + pa*ir*sec => pa(1e18 + ir*sec)
        // INTERES LINEAL, NO COMPUESTO
        uint256 timeElapsed = block.timestamp - s_userLastUpdatedTimestamp[_user];
        linearInterest = PRECISION_FACTOR + (s_userInterestRates[_user] * timeElapsed);
    } 

    /**
     * @dev returns the global interest rate of the token for future depositors
     * @return s_interestRate
     *
     */
    function getInterestRate() external view returns (uint256) {
        return s_interestRate;
    }

    /**
     * @notice Get the interest rate for the user _user.
     * @param _user The address of the user to get the interest rate for.
     * @return The interest rate for the user _user.
     */
    function getUserInterestRate(address _user) external view returns (uint256) {
        return s_userInterestRates[_user];
    }
}

