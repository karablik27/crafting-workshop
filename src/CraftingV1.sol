// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ERC1155Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/**
 * @title CraftingV1
 * @notice Мастерская игровых предметов (ERC-1155): владелец игры выдаёт ресурсы,
 *         игроки крафтят из них мечи. Развёртывается за Transparent Proxy.
 *
 *         id 1 — дерево, id 2 — руда, id 3 — меч.
 *         Рецепт: 3 дерева + 2 руды = 1 меч.
 *
 * @dev Собственные данные хранятся в пространстве имён ERC-7201, поэтому они не
 *      пересекаются со слотами родительских контрактов OpenZeppelin и с данными
 *      будущих версий.
 */
contract CraftingV1 is Initializable, ERC1155Upgradeable, OwnableUpgradeable {
    uint256 public constant WOOD = 1;
    uint256 public constant ORE = 2;
    uint256 public constant SWORD = 3;

    uint256 public constant WOOD_PER_SWORD = 3;
    uint256 public constant ORE_PER_SWORD = 2;

    string private constant BASE_URI = "https://game.example/api/item/{id}.json";

    /// @custom:storage-location erc7201:crafting.storage.CraftingV1
    struct CraftingV1Storage {
        uint256 totalCrafted;
    }

    // keccak256(abi.encode(uint256(keccak256("crafting.storage.CraftingV1")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant CRAFTING_V1_STORAGE_LOCATION =
        0xd41a5ef3529b507575d2519463a3f53ccd38ba26d01427a4aacfe4d3cdc41b00;

    event Crafted(address indexed player, uint256 amount);

    error ZeroAmount();
    error ZeroAddress();
    error NotIssuable(uint256 id);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        // Реализацию нельзя инициализировать напрямую — только через прокси.
        _disableInitializers();
    }

    function initialize(address initialOwner) public initializer {
        __ERC1155_init(BASE_URI);
        __Ownable_init(initialOwner);
    }

    /**
     * @notice Выдать ресурсы игроку. Только владелец игры, только дерево или руда.
     *         Мечи через issue не выпускаются — только через craft.
     */
    function issue(address to, uint256 id, uint256 amount) external onlyOwner {
        if (id != WOOD && id != ORE) revert NotIssuable(id);
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        _mint(to, id, amount, "");
    }

    /**
     * @notice Сжечь у вызывающего 3*n дерева и 2*n руды и выдать ему n мечей.
     * @dev Checks-Effects-Interactions: сжигание и счётчик — до выпуска меча,
     *      который вызывает onERC1155Received у получателя.
     */
    function craft(uint256 n) external {
        if (n == 0) revert ZeroAmount();
        address player = _msgSender();

        uint256[] memory ids = new uint256[](2);
        uint256[] memory amounts = new uint256[](2);
        ids[0] = WOOD;
        ids[1] = ORE;
        amounts[0] = WOOD_PER_SWORD * n;
        amounts[1] = ORE_PER_SWORD * n;
        // Откатывается целиком (ERC1155InsufficientBalance) при нехватке любого ресурса.
        _burnBatch(player, ids, amounts);

        _getCraftingV1Storage().totalCrafted += n;
        // Сжигание не вызывает получателя (to == address(0)), внешний вызов будет только в _mint ниже.
        // forge-lint: disable-next-line(reentrancy-events)
        emit Crafted(player, n);

        _mint(player, SWORD, n, "");
    }

    /// @notice Сколько мечей скрафтено за всё время (разбор это число не уменьшает).
    function totalCrafted() external view returns (uint256) {
        return _getCraftingV1Storage().totalCrafted;
    }

    function _getCraftingV1Storage() private pure returns (CraftingV1Storage storage $) {
        assembly {
            $.slot := CRAFTING_V1_STORAGE_LOCATION
        }
    }
}
