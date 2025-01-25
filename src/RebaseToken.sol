// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title RebaseToken
 * @author 0xRudeboy
 * @notice This is a cross-chain rebase token that incentivises users to deposit into a vault and gain interest in rewards.
 * @notice The interest rate in the smart contract can only decrease.
 * @notice Each user will have their own interest rate set by the protocols global interest rate at the time of deposit.
 */
contract RebaseToken is ERC20 {
    error RebaseToken__InterestRateCannotIncrease(uint256 oldInterestRate, uint256 newInterestRate);

    uint256 private constant PRECISION_FACTOR = 1e18;
    uint256 private s_interestRate = 5e10;
    mapping(address user => uint256 interestRate) private s_userInterestRate;
    mapping(address user => uint256 lastUpdatedTimestamp) private s_userLastUpdatedTimestamp;

    event InterestRateSet(uint256 newInterestRate);

    constructor() ERC20("RebaseToken", "RBT") {}

    /**
     * @notice Set the interest rate for the protocol.
     * @param _newInterestRate The new interest rate for the protocol.
     * @dev The interest rate can only decrease.
     */
    function setInterestRate(uint256 _newInterestRate) external {
        if (_newInterestRate > s_interestRate) {
            revert RebaseToken__InterestRateCannotIncrease(s_interestRate, _newInterestRate);
        }
        s_interestRate = _newInterestRate;
        emit InterestRateSet(s_interestRate);
    }

    /**
     * @notice Mint the user tokens when they deposit into the vault.
     * @param _to The address of the user to mint the tokens to.
     * @param _amount The amount of tokens to mint.
     */
    function mint(address _to, uint256 _amount) external {
        _mintAccruedInterest(_to);
        s_userInterestRate[_to] = s_interestRate;
        _mint(_to, _amount);
    }

    /**
     * @notice Get the balance of a user including any accrued interest accumulated since the last update.
     * (principal balance + some interest that has accrued)
     * @param _user The address of the user to get the balance of.
     * @return The balance of the user including any accrued interest.
     */
    function balanceOf(address _user) public view override returns (uint256) {
        // 1. get current principal balance (num of tokens actually minted to user aka: balance inside the ERC20 _balances mapping)
        // 2. multiply the principal balance by the interest that has accumulated in the time since the balance was last updated

        return super.balanceOf(_user) * _calculateUserAccumulatedInterestSinceLastUpdate(_user) / PRECISION_FACTOR;
    }

    /**
     * @notice Calculate the amount of interest that has accumulated since the last update.
     * @param _user The address of the user to calculate the accumulated interest for.
     * @return linearInterest The amount of interest that has accumulated since the last update.
     */
    function _calculateUserAccumulatedInterestSinceLastUpdate(address _user)
        internal
        view
        returns (uint256 linearInterest)
    {
        // calculate the interest that has accumulated since the last update
        // this is going to be linear growth with time
        // 1. calculate the time since last update

        // 2. calculate the amount of linear growth

        // 3. return the amount of linear growth
        // (principal amount) + principal amount * user interest rate * time elapsed
        // deoisut: 10 tokens
        // interest rate: 0.5 tokens per second
        // time elapsed: 2 seconds
        // 10 + (10 * 0.5 * 2)

        uint256 timeElapsed = block.timestamp - s_userLastUpdatedTimestamp[_user];
        linearInterest = PRECISION_FACTOR + (s_userInterestRate[_user] * timeElapsed);
    }

    function _mintAccruedInterest(address _user) internal {
        // 1. find their current balance of rebase tokens that have been minted to the user -> principal balance
        // 2. calculate their current balance including any interest -> balanceOf (any rebase tokens minted to them + pending rebase tokens needed to be minted)
        // 3. calculate the amount of rebase tokens to mint -> (2 - 1)
        // 4. _mint the rebase tokens to the user
        // 5. set users last updated timestamp

        s_userLastUpdatedTimestamp[_user] = block.timestamp;
    }

    function burn(address _to, uint256 _amount) external {
        _burn(_to, _amount);
    }

    /**
     * @notice Get the interest rate for a user.
     * @param _user The address of the user.
     * @return The interest rate for the user.
     */
    function getUserInterestRate(address _user) external view returns (uint256) {
        return s_userInterestRate[_user];
    }
}
