// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.0 <0.9.0;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {PeerTokenHydration} from "src/PeerTokenHydration.sol";
import {PeerTokenLite} from "src/PeerTokenLite.sol";

contract PeerTokenHydrationTest is Test {
    PeerTokenHydration internal token;

    address internal minter = makeAddr("minter");
    address internal owner = makeAddr("owner");
    address internal alice = makeAddr("alice");

    function setUp() public {
        token = new PeerTokenHydration("Hydration", "HDX", minter, owner);
    }

    /// @dev The reason this contract exists: HDX is 12 decimals on Hydration,
    /// and NttManager reads this value by staticcall to register peer decimals.
    function test_decimalsIs12() public {
        assertEq(token.decimals(), 12);
    }

    function test_constructorSetsMetadataAndRoles() public {
        assertEq(token.name(), "Hydration");
        assertEq(token.symbol(), "HDX");
        assertEq(token.minter(), minter);
        assertEq(token.owner(), owner);
        assertEq(token.totalSupply(), 0);
    }

    function test_minterCanMint() public {
        vm.prank(minter);
        token.mint(alice, 1_000e12);

        assertEq(token.balanceOf(alice), 1_000e12);
        assertEq(token.totalSupply(), 1_000e12);
    }

    function test_nonMinterCannotMint() public {
        vm.expectRevert(abi.encodeWithSelector(PeerTokenLite.CallerNotMinter.selector, alice));
        vm.prank(alice);
        token.mint(alice, 1e12);
    }

    /// @dev The handover performed after `ntt add-chain` deploys the NttManager.
    function test_ownerCanTransferMinterToManager() public {
        address nttManager = makeAddr("nttManager");

        vm.prank(owner);
        token.setMinter(nttManager);
        assertEq(token.minter(), nttManager);

        vm.prank(nttManager);
        token.mint(alice, 5e12);
        assertEq(token.balanceOf(alice), 5e12);

        // the previous minter loses the ability to mint
        vm.expectRevert(abi.encodeWithSelector(PeerTokenLite.CallerNotMinter.selector, minter));
        vm.prank(minter);
        token.mint(alice, 1e12);
    }

    function test_nonOwnerCannotSetMinter() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        vm.prank(alice);
        token.setMinter(alice);
    }

    function test_setMinterRejectsZeroAddress() public {
        vm.expectRevert(PeerTokenLite.InvalidMinterZeroAddress.selector);
        vm.prank(owner);
        token.setMinter(address(0));
    }

    /// @dev Burn is what NttManager calls on the outbound leg in burning mode.
    function test_holderCanBurn() public {
        vm.prank(minter);
        token.mint(alice, 10e12);

        vm.prank(alice);
        token.burn(4e12);

        assertEq(token.balanceOf(alice), 6e12);
        assertEq(token.totalSupply(), 6e12);
    }

    function testFuzz_decimalsIndependentOfSupply(uint128 amount) public {
        vm.prank(minter);
        token.mint(alice, amount);

        assertEq(token.decimals(), 12);
    }
}
