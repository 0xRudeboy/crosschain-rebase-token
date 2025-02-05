// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {RebaseToken} from "src/RebaseToken.sol";
import {Vault} from "src/Vault.sol";
import {IRebaseToken} from "src/interfaces/IRebaseToken.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

contract RebaseTokenTest is Test {
    RebaseToken private rebaseToken;
    Vault private vault;

    bytes32 private constant MINT_AND_BURN_ROLE = keccak256("MINT_AND_BURN_ROLE");

    address public owner = makeAddr("OWNER");
    address public user = makeAddr("USER");

    function setUp() public {
        vm.startPrank(owner);
        rebaseToken = new RebaseToken();
        vault = new Vault(IRebaseToken(address(rebaseToken)));
        rebaseToken.grantMintAndBurnRole(address(vault));
        vm.stopPrank();
    }

    function addRewardsToVault(uint256 rewardAmount) public {
        (bool success,) = payable(address(vault)).call{value: rewardAmount}("");
        require(success, "Failed to send test ETH to vault");
    }

    function testDepositLinear(uint256 randomFuzzAmount) public {
        // here we could use vm.assume however this will completely discard the fuzz run if the condition is not met
        // vm.assume(randomFuzzAmount > 1e5);

        // rather use bounding the randomFuzzAmount to be between 1e5 and type(uint96).max without discarding the fuzz run for max trials
        randomFuzzAmount = bound(randomFuzzAmount, 1e5, type(uint96).max);

        // 1. deposit
        vm.startPrank(user);
        vm.deal(user, randomFuzzAmount);
        vault.deposit{value: randomFuzzAmount}();
        vm.stopPrank();

        // 2. check our rebase token balance
        uint256 startBalance = rebaseToken.balanceOf(user);
        assertEq(startBalance, randomFuzzAmount);
        console2.log("startBalance", startBalance);

        // 3. warp the time and check the balance again
        vm.warp(block.timestamp + 1 hours);
        uint256 middleBalance = rebaseToken.balanceOf(user);
        assertGt(middleBalance, startBalance);
        console2.log("middleBalance", middleBalance);

        // 4. warp the time again by the same amount of internal and check the balance again
        vm.warp(block.timestamp + 1 hours);
        uint256 endBalance = rebaseToken.balanceOf(user);
        assertGt(endBalance, middleBalance);
        console2.log("endBalance", endBalance);

        // Here the precision factor is creating a 1 wei difference in the balances so we use assertApproxEqAbs to assertEq with a tolerance of 1 wei
        assertApproxEqAbs(endBalance - middleBalance, middleBalance - startBalance, 1);
    }

    function testRedeemStraightAway(uint256 randomFuzzAmount) public {
        randomFuzzAmount = bound(randomFuzzAmount, 1e5, type(uint96).max);
        vm.deal(user, randomFuzzAmount);

        vm.startPrank(user);
        vault.deposit{value: randomFuzzAmount}();
        assertEq(rebaseToken.balanceOf(user), randomFuzzAmount);

        vault.redeem(type(uint256).max);
        assertEq(rebaseToken.balanceOf(user), 0);
        assertEq(address(user).balance, randomFuzzAmount);
        vm.stopPrank();
    }

    function testRedeemAfterTimePassed(uint256 randomFuzzAmount, uint256 randomFuzzTimePassed) public {
        randomFuzzAmount = bound(randomFuzzAmount, 1e5, type(uint96).max);
        randomFuzzTimePassed = bound(randomFuzzTimePassed, 1000, type(uint96).max); // maximum time of 2.5 * 10^21 years!!!
        vm.deal(user, randomFuzzAmount);

        // 1. deposit funds into the vault
        vm.prank(user);
        vault.deposit{value: randomFuzzAmount}();
        assertEq(rebaseToken.balanceOf(user), randomFuzzAmount);

        // 2. warp the time
        vm.warp(block.timestamp + randomFuzzTimePassed);
        uint256 balanceAfterSomeTime = rebaseToken.balanceOf(user);

        // 2. (b) add the rewards to the vault
        vm.deal(owner, balanceAfterSomeTime - randomFuzzAmount);
        vm.prank(owner);
        addRewardsToVault(balanceAfterSomeTime - randomFuzzAmount);

        // 3. redeem the tokens
        vm.prank(user);
        vault.redeem(type(uint256).max);

        uint256 ethBalance = address(user).balance;
        assertEq(ethBalance, balanceAfterSomeTime);
        assertGt(ethBalance, randomFuzzAmount);
    }

    function testTransfer(uint256 randomFuzzAmount, uint256 randomFuzzAmountToSend) public {
        randomFuzzAmount = bound(randomFuzzAmount, 1e5 + 1e5, type(uint96).max);
        randomFuzzAmountToSend = bound(randomFuzzAmountToSend, 1e5, randomFuzzAmount - 1e5);

        // 1. deposit
        vm.deal(user, randomFuzzAmount);
        vm.prank(user);
        vault.deposit{value: randomFuzzAmount}();

        address user2 = makeAddr("USER2");
        uint256 userBalance = rebaseToken.balanceOf(user);
        uint256 user2Balance = rebaseToken.balanceOf(user2);
        assertEq(userBalance, randomFuzzAmount);
        assertEq(user2Balance, 0);

        // owner reduces the interest rate
        vm.prank(owner);
        rebaseToken.setInterestRate(4e10);

        // 2. transfer
        vm.prank(user);
        rebaseToken.transfer(user2, randomFuzzAmountToSend);

        // 3. check the balances
        uint256 userBalanceAfterTransfer = rebaseToken.balanceOf(user);
        uint256 user2BalanceAfterTransfer = rebaseToken.balanceOf(user2);

        assertEq(userBalanceAfterTransfer, userBalance - randomFuzzAmountToSend);
        assertEq(user2BalanceAfterTransfer, randomFuzzAmountToSend);

        // 4. check the interest rate has been inherited (5e10 not 4e10)
        assertEq(rebaseToken.getUserInterestRate(user), 5e10);
        assertEq(rebaseToken.getUserInterestRate(user2), 5e10);
        assertEq(rebaseToken.getInterestRate(), 4e10);
    }

    function testCannotSetInterestRateIfNotTheOwner(uint256 randomFuzzInterestRate) public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        rebaseToken.setInterestRate(randomFuzzInterestRate);
    }

    function testCannotCallMintAndBurnIfRoleNotGranted() public {
        vm.startPrank(user);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, user, MINT_AND_BURN_ROLE)
        );
        rebaseToken.mint(user, 100, rebaseToken.getInterestRate());

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, user, MINT_AND_BURN_ROLE)
        );
        rebaseToken.burn(user, 100);
        vm.stopPrank();
    }

    function testGetPrincipalAmount(uint256 randomFuzzAmount) public {
        randomFuzzAmount = bound(randomFuzzAmount, 1e5, type(uint96).max);

        vm.deal(user, randomFuzzAmount);
        vm.prank(user);
        vault.deposit{value: randomFuzzAmount}();
        assertEq(rebaseToken.principalBalanceOf(user), randomFuzzAmount);

        vm.warp(block.timestamp + 1 hours);
        assertEq(rebaseToken.principalBalanceOf(user), randomFuzzAmount);
    }

    function testGetRebaseTokenAddress() public view {
        assertEq(vault.getRebaseTokenAddress(), address(rebaseToken));
    }

    function testInterestRateCanOnlyDecrease(uint256 randomFuzzInterestRate) public {
        uint256 initialInterestRate = rebaseToken.getInterestRate();
        randomFuzzInterestRate = bound(randomFuzzInterestRate, initialInterestRate, type(uint256).max);

        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                RebaseToken.RebaseToken__InterestRateCannotIncrease.selector,
                initialInterestRate,
                randomFuzzInterestRate
            )
        );
        rebaseToken.setInterestRate(randomFuzzInterestRate);
        assertEq(rebaseToken.getInterestRate(), initialInterestRate);
    }
}
