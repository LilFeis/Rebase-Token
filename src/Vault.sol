//SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {IRebaseToken} from "./interfaces/IRebaseToken.sol";

contract Vault {
    //we need to pass the token address to the constructor 
    //create a deposit function that mint tokens to the user equal to the amount of ETH
    //create a redeem function that burns tokens and sends the user their deposit back (ETH)
    //create a way to add rewards to the vault
    IRebaseToken private immutable i_rebaseToken;

    event Deposit(address indexed user, uint256 amount);
    event Reddem(address indexed user, uint256 amount);

    error Vault__RedeemFailed();
    
    constructor (IRebaseToken _rebaseToken) {
        i_rebaseToken = _rebaseToken;
    }

    receive() external payable {}

    /**
     * @notice This function allows users to deposit ETH into the vault and mint Rebase Tokens.
     * @dev The amount of ETH sent will be used to mint an equivalent amount of Rebase Tokens to the user.
     */
    function deposit() external payable {
        //1. we need to use the amount of ETH sent to the contract to mint tokens to the user
        i_rebaseToken.mint(msg.sender, msg.value, i_rebaseToken.getInterestRate());
        emit Deposit(msg.sender, msg.value);
    }

    /**
     * @notice This function allows users to redeem their Rebase Tokens for ETH.
     * @dev The amount of Rebase Tokens burned will be equal to the amount of ETH sent back to the user.
     * @param _amount The amount of Rebase Tokens to redeem.
     */
    function redeem(uint256 _amount) external {
        if (_amount == type(uint256).max) {
            _amount = i_rebaseToken.balanceOf(msg.sender); // If the amount is max, redeem all the tokens
        }
        //1. we need to burn the user's tokens
        //2. we need to send the user their deposit back (ETH)
        i_rebaseToken.burn(msg.sender, _amount);
        (bool success,) = payable(msg.sender).call{value: _amount}(""); // Send the user their deposit back
        if (!success) {
            revert Vault__RedeemFailed();
        }
        emit Reddem(msg.sender, _amount);
    }

    /**
     * @notice This function returns the address of the Rebase Token contract.
     * @return The address of the Rebase Token contract.
     */
    function getRebaseTokenAddress() external view returns (address) {
        return address(i_rebaseToken);
    }

}