// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC1155Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {CraftingBase} from "./CraftingBase.t.sol";
import {CraftingV1} from "../src/CraftingV1.sol";
import {CraftingV2} from "../src/CraftingV2.sol";
import {PickyReceiver} from "./mocks/PickyReceiver.sol";

contract CraftingV2Test is CraftingBase {
    CraftingV2 internal game;

    function setUp() public {
        _deployV1();
        game = _upgradeToV2();
    }

    function test_Salvage_Success() public {
        _issue(alice, 6, 4);
        vm.prank(alice);
        game.craft(2);

        vm.expectEmit(true, false, false, true, proxy);
        emit CraftingV2.Salvaged(alice, 2);
        vm.prank(alice);
        game.salvage(2);

        assertEq(game.balanceOf(alice, SWORD), 0);
        assertEq(game.balanceOf(alice, ORE), 2);
        assertEq(game.balanceOf(alice, WOOD), 0);
        assertEq(game.totalCrafted(), 2);
        assertEq(game.totalSalvaged(), 2);
    }

    function test_Salvage_RevertsWithoutSwords() public {
        vm.expectRevert(abi.encodeWithSelector(IERC1155Errors.ERC1155InsufficientBalance.selector, alice, 0, 1, SWORD));
        vm.prank(alice);
        game.salvage(1);
        assertEq(game.balanceOf(alice, ORE), 0);
        assertEq(game.totalSalvaged(), 0);
    }

    function test_Salvage_RevertsWhenNotEnoughSwords() public {
        _issue(alice, 3, 2);
        vm.prank(alice);
        game.craft(1);

        vm.expectRevert(abi.encodeWithSelector(IERC1155Errors.ERC1155InsufficientBalance.selector, alice, 1, 2, SWORD));
        vm.prank(alice);
        game.salvage(2);
        assertEq(game.balanceOf(alice, SWORD), 1);
        assertEq(game.totalSalvaged(), 0);
    }

    function test_Salvage_RevertsOnZero() public {
        vm.expectRevert(CraftingV1.ZeroAmount.selector);
        vm.prank(alice);
        game.salvage(0);
    }

    function test_Salvage_UsesOnlyCallerItems() public {
        _issue(alice, 3, 2);
        vm.startPrank(alice);
        game.craft(1);
        game.setApprovalForAll(operator, true);
        vm.stopPrank();

        vm.expectRevert(
            abi.encodeWithSelector(IERC1155Errors.ERC1155InsufficientBalance.selector, operator, 0, 1, SWORD)
        );
        vm.prank(operator);
        game.salvage(1);
        assertEq(game.balanceOf(alice, SWORD), 1);
    }

    function test_Salvage_ReceiverRejectsOre_RevertsEverything() public {
        PickyReceiver player = new PickyReceiver(proxy);
        _issue(address(player), 6, 4);
        player.craft(2);
        assertEq(game.balanceOf(address(player), SWORD), 2);

        player.setReject(ORE, true);
        vm.expectRevert(abi.encodeWithSelector(IERC1155Errors.ERC1155InvalidReceiver.selector, address(player)));
        player.salvage(1);

        assertEq(game.balanceOf(address(player), SWORD), 2);
        assertEq(game.balanceOf(address(player), ORE), 0);
        assertEq(game.totalCrafted(), 2);
        assertEq(game.totalSalvaged(), 0);
    }

    function test_Craft_ReceiverRejectsSword_RevertsEverythingAfterUpgrade() public {
        PickyReceiver player = new PickyReceiver(proxy);
        _issue(address(player), 3, 2);
        player.setReject(SWORD, true);

        vm.expectRevert(abi.encodeWithSelector(IERC1155Errors.ERC1155InvalidReceiver.selector, address(player)));
        player.craft(1);

        assertEq(game.balanceOf(address(player), WOOD), 3);
        assertEq(game.balanceOf(address(player), ORE), 2);
        assertEq(game.totalCrafted(), 0);
    }

    function test_TransfersDoNotChangeCounters() public {
        _issue(alice, 6, 4);
        vm.prank(alice);
        game.craft(2);

        vm.prank(alice);
        game.safeTransferFrom(alice, bob, SWORD, 2, "");
        vm.prank(bob);
        game.safeTransferFrom(bob, alice, SWORD, 1, "");

        assertEq(game.totalCrafted(), 2);
        assertEq(game.totalSalvaged(), 0);
    }

    /// Для 1 <= n <= 1000: новый игрок получает 3n дерева и 2n руды, делает craft(n)
    /// и salvage(n) — у него остаётся только n руды, каждый счётчик вырос на n.
    function testFuzz_CraftThenSalvage(uint256 n) public {
        n = bound(n, 1, 1000);
        address player = makeAddr(string.concat("player-", vm.toString(n)));
        assertEq(player.code.length, 0);
        assertEq(game.balanceOf(player, WOOD) + game.balanceOf(player, ORE) + game.balanceOf(player, SWORD), 0);

        uint256 craftedBefore = game.totalCrafted();
        uint256 salvagedBefore = game.totalSalvaged();

        _issue(player, 3 * n, 2 * n);
        vm.startPrank(player);
        game.craft(n);
        game.salvage(n);
        vm.stopPrank();

        assertEq(game.balanceOf(player, WOOD), 0);
        assertEq(game.balanceOf(player, ORE), n);
        assertEq(game.balanceOf(player, SWORD), 0);
        assertEq(game.totalCrafted(), craftedBefore + n);
        assertEq(game.totalSalvaged(), salvagedBefore + n);
    }
}
