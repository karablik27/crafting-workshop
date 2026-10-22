// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {CraftingV1} from "./CraftingV1.sol";

/**
 * @title CraftingV2
 * @notice Вторая версия мастерской: добавлен разбор мечей (1 меч -> 1 руда).
 * @dev Наследует V1 без изменения его хранилища. Новый счётчик лежит в отдельном
 *      пространстве имён ERC-7201, поэтому после обновления он равен нулю, а все
 *      данные V1 (владелец, балансы, разрешения, totalCrafted) остаются на месте.
 *
 * @custom:oz-upgrades-from src/CraftingV1.sol:CraftingV1
 */
contract CraftingV2 is CraftingV1 {
    /// @custom:storage-location erc7201:crafting.storage.CraftingV2
    struct CraftingV2Storage {
        uint256 totalSalvaged;
    }

    // keccak256(abi.encode(uint256(keccak256("crafting.storage.CraftingV2")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant CRAFTING_V2_STORAGE_LOCATION =
        0x3f845d46beeb00e3aef26e6fe83c8608247ff83215f07b5501fa5ccba74d3600;

    event Salvaged(address indexed player, uint256 amount);

    /**
     * @notice Сжечь у вызывающего n мечей и выдать ему n руды.
     * @dev Checks-Effects-Interactions: сжигание и счётчик — до выпуска руды.
     */
    function salvage(uint256 n) external {
        if (n == 0) revert ZeroAmount();
        address player = _msgSender();

        // Откатывается (ERC1155InsufficientBalance), если мечей не хватает.
        _burn(player, SWORD, n);

        _getCraftingV2Storage().totalSalvaged += n;
        // Сжигание не вызывает получателя (to == address(0)), внешний вызов будет только в _mint ниже.
        // forge-lint: disable-next-line(reentrancy-events)
        emit Salvaged(player, n);

        _mint(player, ORE, n, "");
    }

    /// @notice Сколько мечей разобрано за всё время.
    function totalSalvaged() external view returns (uint256) {
        return _getCraftingV2Storage().totalSalvaged;
    }

    function _getCraftingV2Storage() private pure returns (CraftingV2Storage storage $) {
        assembly {
            $.slot := CRAFTING_V2_STORAGE_LOCATION
        }
    }
}
