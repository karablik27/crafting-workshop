// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {CraftingV1} from "../src/CraftingV1.sol";
import {CraftingV2} from "../src/CraftingV2.sol";

/// @dev Общая подготовка: прокси разворачивается через OpenZeppelin Upgrades,
///      все обращения к игре идут по адресу прокси.
abstract contract CraftingBase is Test {
    uint256 internal constant WOOD = 1;
    uint256 internal constant ORE = 2;
    uint256 internal constant SWORD = 3;

    // Владелец игры (Ownable в V1/V2) и владелец ProxyAdmin — разные адреса.
    address internal gameOwner = makeAddr("gameOwner");
    address internal adminOwner = makeAddr("adminOwner");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal operator = makeAddr("operator");
    address internal stranger = makeAddr("stranger");

    address internal proxy;

    function _deployV1() internal returns (CraftingV1) {
        proxy = Upgrades.deployTransparentProxy(
            "CraftingV1.sol", adminOwner, abi.encodeCall(CraftingV1.initialize, (gameOwner))
        );
        return CraftingV1(proxy);
    }

    function _upgradeToV2() internal returns (CraftingV2) {
        Upgrades.upgradeProxy(proxy, "CraftingV2.sol", "", adminOwner);
        return CraftingV2(proxy);
    }

    function _issue(address to, uint256 wood, uint256 ore) internal {
        vm.startPrank(gameOwner);
        if (wood > 0) CraftingV1(proxy).issue(to, WOOD, wood);
        if (ore > 0) CraftingV1(proxy).issue(to, ORE, ore);
        vm.stopPrank();
    }
}
