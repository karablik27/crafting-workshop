// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {CraftingV1} from "../../src/CraftingV1.sol";
import {CraftingV2} from "../../src/CraftingV2.sol";

/**
 * @dev Контракт-игрок, который принимает или отклоняет конкретные id токенов.
 *      Заодно в момент получения меча запоминает состояние игры, чтобы тест
 *      мог проверить порядок «сначала списания и счётчик, потом выпуск».
 */
contract PickyReceiver is IERC1155Receiver {
    address public immutable game;

    mapping(uint256 id => bool) public rejects;

    bool public sawSword;
    uint256 public woodSeenOnSword;
    uint256 public oreSeenOnSword;
    uint256 public totalCraftedSeenOnSword;

    constructor(address game_) {
        game = game_;
    }

    function setReject(uint256 id, bool value) external {
        rejects[id] = value;
    }

    function craft(uint256 n) external {
        CraftingV1(game).craft(n);
    }

    function salvage(uint256 n) external {
        CraftingV2(game).salvage(n);
    }

    function onERC1155Received(address, address, uint256 id, uint256, bytes calldata) external returns (bytes4) {
        if (rejects[id]) return bytes4(0);
        if (msg.sender == game && id == CraftingV1(game).SWORD()) {
            sawSword = true;
            woodSeenOnSword = CraftingV1(game).balanceOf(address(this), 1);
            oreSeenOnSword = CraftingV1(game).balanceOf(address(this), 2);
            totalCraftedSeenOnSword = CraftingV1(game).totalCrafted();
        }
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(address, address, uint256[] calldata ids, uint256[] calldata, bytes calldata)
        external
        view
        returns (bytes4)
    {
        for (uint256 i; i < ids.length; ++i) {
            if (rejects[ids[i]]) return bytes4(0);
        }
        return this.onERC1155BatchReceived.selector;
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IERC1155Receiver).interfaceId || interfaceId == type(IERC165).interfaceId;
    }
}
