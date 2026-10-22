// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Upgrades, Options} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {CraftingBase} from "./CraftingBase.t.sol";
import {CraftingV1} from "../src/CraftingV1.sol";
import {CraftingV2} from "../src/CraftingV2.sol";

contract UpgradeTest is CraftingBase {
    function setUp() public {
        _deployV1();
    }

    function test_DeploymentRoles() public view {
        assertEq(CraftingV1(proxy).owner(), gameOwner);
        assertEq(ProxyAdmin(Upgrades.getAdminAddress(proxy)).owner(), adminOwner);
        assertTrue(gameOwner != adminOwner);
    }

    /// Проверка совместимости хранилища V1 -> V2 средствами OpenZeppelin Upgrades
    /// (без unsafeSkipAllChecks / unsafeSkipStorageCheck).
    function test_ValidateUpgrade_V1ToV2() public {
        Options memory opts;
        opts.referenceContract = "CraftingV1.sol:CraftingV1";
        Upgrades.validateUpgrade("CraftingV2.sol:CraftingV2", opts);
    }

    /// Единый сценарий: V1 -> выпуск и крафт -> оператор -> обновление -> перевод меча -> разбор.
    function test_FullScenario_V1ToV2() public {
        CraftingV1 v1 = CraftingV1(proxy);
        address proxyBefore = proxy;
        address adminBefore = Upgrades.getAdminAddress(proxy);
        address implV1 = Upgrades.getImplementationAddress(proxy);

        // 1. Выпуск ресурсов и крафт в V1.
        _issue(alice, 9, 6);
        vm.prank(alice);
        v1.craft(2);
        assertEq(v1.balanceOf(alice, WOOD), 3);
        assertEq(v1.balanceOf(alice, ORE), 2);
        assertEq(v1.balanceOf(alice, SWORD), 2);
        assertEq(v1.totalCrafted(), 2);

        // 2. Разрешение оператору.
        vm.prank(alice);
        v1.setApprovalForAll(operator, true);

        // 3. Чужие обновления запрещены — даже владельцу игры.
        address implV2 = Upgrades.prepareUpgrade("CraftingV2.sol", _opts());
        ProxyAdmin admin = ProxyAdmin(adminBefore);
        _expectUpgradeReverts(admin, implV2, stranger);
        _expectUpgradeReverts(admin, implV2, gameOwner);
        // Вызов upgradeToAndCall напрямую на прокси от не-админа уходит в реализацию, где такой функции нет.
        vm.expectRevert();
        vm.prank(stranger);
        ITransparentUpgradeableProxy(proxy).upgradeToAndCall(implV2, "");
        assertEq(Upgrades.getImplementationAddress(proxy), implV1);

        // 4. Обновление владельцем ProxyAdmin.
        CraftingV2 game = _upgradeToV2();

        // 5. Сохранённые данные.
        assertEq(address(game), proxyBefore);
        assertEq(Upgrades.getAdminAddress(proxy), adminBefore);
        assertTrue(Upgrades.getImplementationAddress(proxy) != implV1);
        assertEq(game.owner(), gameOwner);
        assertEq(admin.owner(), adminOwner);
        assertEq(game.balanceOf(alice, WOOD), 3);
        assertEq(game.balanceOf(alice, ORE), 2);
        assertEq(game.balanceOf(alice, SWORD), 2);
        assertTrue(game.isApprovedForAll(alice, operator));
        assertEq(game.totalCrafted(), 2);
        assertEq(game.totalSalvaged(), 0);

        // 6. Оператор переводит меч новому держателю; счётчики не меняются.
        vm.prank(operator);
        game.safeTransferFrom(alice, bob, SWORD, 1, "");
        assertEq(game.balanceOf(alice, SWORD), 1);
        assertEq(game.balanceOf(bob, SWORD), 1);
        assertEq(game.totalCrafted(), 2);
        assertEq(game.totalSalvaged(), 0);

        // 7. Разбор новым держателем.
        vm.expectEmit(true, false, false, true, proxy);
        emit CraftingV2.Salvaged(bob, 1);
        vm.prank(bob);
        game.salvage(1);
        assertEq(game.balanceOf(bob, SWORD), 0);
        assertEq(game.balanceOf(bob, ORE), 1);
        assertEq(game.totalCrafted(), 2); // разбор не уменьшает totalCrafted
        assertEq(game.totalSalvaged(), 1);

        // 8. Функции V1 продолжают работать через прокси.
        vm.prank(alice);
        game.craft(1);
        assertEq(game.totalCrafted(), 3);

        // 9. Повторная инициализация запрещена.
        _assertInitializeBlocked(proxy);
        _assertInitializeBlocked(Upgrades.getImplementationAddress(proxy));
        _assertInitializeBlocked(implV1);
    }

    function test_Initialize_ProxyCannotBeReinitialized() public {
        _assertInitializeBlocked(proxy);
        _upgradeToV2();
        _assertInitializeBlocked(proxy);
        assertEq(CraftingV2(proxy).owner(), gameOwner);
    }

    function test_Initialize_ImplementationsCannotBeInitialized() public {
        _assertInitializeBlocked(Upgrades.getImplementationAddress(proxy));
        _upgradeToV2();
        _assertInitializeBlocked(Upgrades.getImplementationAddress(proxy));
    }

    function test_Upgrade_RevertsForStrangerAndGameOwner() public {
        address implV2 = Upgrades.prepareUpgrade("CraftingV2.sol", _opts());
        ProxyAdmin admin = ProxyAdmin(Upgrades.getAdminAddress(proxy));
        _expectUpgradeReverts(admin, implV2, stranger);
        _expectUpgradeReverts(admin, implV2, gameOwner);
    }

    // ------------------------------------------------------------- helpers

    function _opts() private pure returns (Options memory opts) {}

    function _expectUpgradeReverts(ProxyAdmin admin, address impl, address caller) private {
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, caller));
        vm.prank(caller);
        admin.upgradeAndCall(ITransparentUpgradeableProxy(proxy), impl, "");
    }

    function _assertInitializeBlocked(address target) private {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        vm.prank(stranger);
        CraftingV1(target).initialize(stranger);
    }
}
