// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC1155Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {CraftingBase} from "./CraftingBase.t.sol";
import {CraftingV1} from "../src/CraftingV1.sol";
import {PickyReceiver} from "./mocks/PickyReceiver.sol";

contract CraftingV1Test is CraftingBase {
    CraftingV1 internal game;

    function setUp() public {
        game = _deployV1();
    }

    // ---------------------------------------------------------------- issue

    function test_Issue_OwnerIssuesResources() public {
        _issue(alice, 7, 5);
        assertEq(game.balanceOf(alice, WOOD), 7);
        assertEq(game.balanceOf(alice, ORE), 5);
    }

    function test_Issue_RevertsForNonOwner() public {
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, stranger));
        vm.prank(stranger);
        game.issue(stranger, WOOD, 1);
    }

    function test_Issue_RevertsForProxyAdminOwner() public {
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, adminOwner));
        vm.prank(adminOwner);
        game.issue(adminOwner, WOOD, 1);
    }

    function test_Issue_RevertsForSword() public {
        vm.expectRevert(abi.encodeWithSelector(CraftingV1.NotIssuable.selector, SWORD));
        vm.prank(gameOwner);
        game.issue(alice, SWORD, 1);
    }

    function test_Issue_RevertsForUnknownId() public {
        vm.startPrank(gameOwner);
        vm.expectRevert(abi.encodeWithSelector(CraftingV1.NotIssuable.selector, 0));
        game.issue(alice, 0, 1);
        vm.expectRevert(abi.encodeWithSelector(CraftingV1.NotIssuable.selector, 4));
        game.issue(alice, 4, 1);
        vm.stopPrank();
    }

    function test_Issue_RevertsForZeroRecipient() public {
        vm.expectRevert(CraftingV1.ZeroAddress.selector);
        vm.prank(gameOwner);
        game.issue(address(0), WOOD, 1);
    }

    function test_Issue_RevertsForZeroAmount() public {
        vm.expectRevert(CraftingV1.ZeroAmount.selector);
        vm.prank(gameOwner);
        game.issue(alice, ORE, 0);
    }

    function test_NoPublicMint() public {
        (bool ok,) = proxy.call(abi.encodeWithSignature("mint(address,uint256,uint256,bytes)", alice, SWORD, 1, ""));
        assertFalse(ok);
        uint256[] memory ids = new uint256[](1);
        uint256[] memory amounts = new uint256[](1);
        (ok,) = proxy.call(
            abi.encodeWithSignature("mintBatch(address,uint256[],uint256[],bytes)", alice, ids, amounts, "")
        );
        assertFalse(ok);
    }

    // ---------------------------------------------------------------- craft

    function test_Craft_Success() public {
        _issue(alice, 10, 7);

        vm.expectEmit(true, false, false, true, proxy);
        emit CraftingV1.Crafted(alice, 3);
        vm.prank(alice);
        game.craft(3);

        assertEq(game.balanceOf(alice, WOOD), 1);
        assertEq(game.balanceOf(alice, ORE), 1);
        assertEq(game.balanceOf(alice, SWORD), 3);
        assertEq(game.totalCrafted(), 3);
    }

    function test_Craft_CounterIsGlobal() public {
        _issue(alice, 3, 2);
        _issue(bob, 6, 4);
        vm.prank(alice);
        game.craft(1);
        vm.prank(bob);
        game.craft(2);
        assertEq(game.totalCrafted(), 3);
    }

    function test_Craft_RevertsOnZero() public {
        _issue(alice, 3, 2);
        vm.expectRevert(CraftingV1.ZeroAmount.selector);
        vm.prank(alice);
        game.craft(0);
    }

    function test_Craft_RevertsOnWoodShortage() public {
        _issue(alice, 5, 4); // для 2 мечей нужно 6 дерева
        vm.expectRevert(abi.encodeWithSelector(IERC1155Errors.ERC1155InsufficientBalance.selector, alice, 5, 6, WOOD));
        vm.prank(alice);
        game.craft(2);
        _assertUntouched(alice, 5, 4);
    }

    function test_Craft_RevertsOnOreShortage() public {
        _issue(alice, 6, 3); // для 2 мечей нужно 4 руды
        vm.expectRevert(abi.encodeWithSelector(IERC1155Errors.ERC1155InsufficientBalance.selector, alice, 3, 4, ORE));
        vm.prank(alice);
        game.craft(2);
        _assertUntouched(alice, 6, 3);
    }

    function test_Craft_RevertsWithoutResources() public {
        vm.expectRevert(abi.encodeWithSelector(IERC1155Errors.ERC1155InsufficientBalance.selector, alice, 0, 3, WOOD));
        vm.prank(alice);
        game.craft(1);
        _assertUntouched(alice, 0, 0);
    }

    function test_Craft_UsesOnlyCallerItems() public {
        _issue(alice, 3, 2);
        vm.prank(alice);
        game.setApprovalForAll(bob, true);

        // bob — оператор alice, но craft всё равно списывает ресурсы только у самого bob.
        vm.expectRevert(abi.encodeWithSelector(IERC1155Errors.ERC1155InsufficientBalance.selector, bob, 0, 3, WOOD));
        vm.prank(bob);
        game.craft(1);
        _assertUntouched(alice, 3, 2);
    }

    function test_Craft_BurnsAndCountsBeforeMint() public {
        PickyReceiver player = new PickyReceiver(proxy);
        _issue(address(player), 6, 4);

        player.craft(2);

        assertTrue(player.sawSword());
        assertEq(player.woodSeenOnSword(), 0);
        assertEq(player.oreSeenOnSword(), 0);
        assertEq(player.totalCraftedSeenOnSword(), 2);
    }

    /// Получатель сначала принимает ресурсы, затем отклоняет меч — всё откатывается.
    function test_Craft_ReceiverRejectsSword_RevertsEverything() public {
        // Немного истории, чтобы totalCrafted был ненулевым.
        _issue(alice, 3, 2);
        vm.prank(alice);
        game.craft(1);

        PickyReceiver player = new PickyReceiver(proxy);
        _issue(address(player), 9, 6); // ресурсы приняты
        assertEq(game.balanceOf(address(player), WOOD), 9);
        assertEq(game.balanceOf(address(player), ORE), 6);

        player.setReject(SWORD, true);
        vm.expectRevert(abi.encodeWithSelector(IERC1155Errors.ERC1155InvalidReceiver.selector, address(player)));
        player.craft(3);

        assertEq(game.balanceOf(address(player), WOOD), 9);
        assertEq(game.balanceOf(address(player), ORE), 6);
        assertEq(game.balanceOf(address(player), SWORD), 0);
        assertEq(game.totalCrafted(), 1);
    }

    // ------------------------------------------------- standard ERC-1155 flow

    function test_TransfersAndOperatorsWork() public {
        _issue(alice, 6, 4);
        vm.prank(alice);
        game.craft(2);

        vm.prank(alice);
        game.safeTransferFrom(alice, bob, SWORD, 1, "");
        assertEq(game.balanceOf(bob, SWORD), 1);

        vm.prank(alice);
        game.setApprovalForAll(operator, true);
        assertTrue(game.isApprovedForAll(alice, operator));

        vm.prank(operator);
        game.safeTransferFrom(alice, bob, SWORD, 1, "");
        assertEq(game.balanceOf(alice, SWORD), 0);
        assertEq(game.balanceOf(bob, SWORD), 2);

        // Передачи не меняют счётчик.
        assertEq(game.totalCrafted(), 2);

        vm.expectRevert(abi.encodeWithSelector(IERC1155Errors.ERC1155MissingApprovalForAll.selector, stranger, bob));
        vm.prank(stranger);
        game.safeTransferFrom(bob, stranger, SWORD, 1, "");
    }

    function _assertUntouched(address player, uint256 wood, uint256 ore) private view {
        assertEq(game.balanceOf(player, WOOD), wood);
        assertEq(game.balanceOf(player, ORE), ore);
        assertEq(game.balanceOf(player, SWORD), 0);
        assertEq(game.totalCrafted(), 0);
    }
}
