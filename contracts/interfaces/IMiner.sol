// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ISignatureTransfer} from "./ISignatureTransfer.sol";
interface IMINER {

    struct mineBase {
        uint256 baseProduction;
        uint256 baseCost;
    }

    struct seasonData {
        uint256 totalSeassonGems;
        uint256 totalSeassonPrizes;
    }

    struct mine {
        uint256 workers;
        uint256 space;
        uint256 production;
    }

    struct user {
        uint256 gems; // vuela
        uint32 lastClaim; // actualiza
        uint32 lastSeassonClaim; // actualiza
        uint32 bonus; // actualiza
        mine[] mines; // delete
        uint32 nonce; // nothing
        string name; // nothing
        bool player; // nothing
        mapping(uint256 seasson => uint256) gemsPerSeason; // actualiza
    }

    function totalGems() external view returns (uint256);
    function initialGems() external view returns (uint256);
    function expandBonus() external view returns (uint256);
    function maxExpandLevel() external view returns (uint256);
    function expandPrice() external view returns (uint256);
    function curveMultiplier() external view returns (uint256);
    function seasson() external view returns (uint256);
    function claimeablePrizeDateLimit() external view returns (uint256);
    function claimeablePrize() external view returns (bool);
    function currency() external view returns (IERC20);

    // mapping(address => user) public users;
    function users(address) external view  returns (
        uint256 gems,
        uint32 lastClaim,
        uint32 lastSeassonClaim,
        uint32 bonus,
        uint32 nonce,
        string memory name,
        bool player
    );

    //mapping(uint256 => mineBase) public mineBaseInfo;
    function mineBaseInfo(uint256) external view  returns(
        uint256 baseProduction,
        uint256 baseCost
    );
    function seassonsPrizes(uint256) external view  returns(
        uint256 totalSeassonGems,
        uint256 totalSeassonPrizes
    );

    /******************************/
    /***   WRITE  FUNCTIONS    ***/
    /****************************/

    /**
    * @notice Initializes a new player with a given name.
    * @dev Grants the initial amount of gems, sets the player's name, and creates the first mine.
    * @param name The name of the player being registered.
    * @custom:require The caller must not already be registered as a player.
    */
    function start(string memory name) external;

    /**
    * @notice Unlocks a new mine level (deep) for the caller.
    * @dev Deducts gems for unlocking the mine and sets its initial workers, space, and production.
    * @param deep The level of the mine to unlock.
    * @custom:require `deep` must be greater than 0 and equal to the next mine to unlock.
    * @custom:require The player must have unlocked the previous mine and have enough gems.
    */
    function unlockDeep(uint256 deep) external;

    /**
    * @notice Updates the specified mine by adding one worker.
    * @dev Deducts the cost of adding a worker from the caller's gems and updates the mine's production.
    * @param deep The level of the mine to update.
    * @custom:require The specified mine must exist and belong to the caller.
    * @custom:require The player must have enough gems to cover the update cost.
    */
    function updateMiner(uint256 deep) external;


    /**
    * @notice Expands the space of a specified mine level by a fixed bonus.
    * @dev Uses a Permit2 transfer to pay the expansion cost and validates the signature and transfer details.
    * @param deep The level of the mine to expand.
    * @param permit The Permit2 transfer data structure.
    * @param transferDetails Details of the ERC20 transfer.
    * @param signature The caller's signature for the Permit2 transfer.
    * @custom:require The mine must exist and belong to the caller.
    * @custom:require The mine's space must not have reached the maximum expansion level.
    * @custom:require The signature, nonce, and transfer details must be valid.
    */
    function expand(
        uint256 deep,
        ISignatureTransfer.PermitTransferFrom memory permit,
        ISignatureTransfer.SignatureTransferDetails calldata transferDetails,
        bytes calldata signature
    ) external;


    /**
    * @notice Claims accumulated gems from all mines for a specified user.
    * @dev Calculates the production since the last claim and updates the user's gem balance.
    * @param userAddress The address of the user claiming gems.
    * @custom:require The user must be registered as a player and in the current season.
    */
    function claim(address userAddress) external;
    /******************************/
    /***   READ  FUNCTIONS    ***/
    /****************************/

    /**
    * @notice Calculates the price to update a specified mine with a given number of workers.
    * @dev Uses the base cost of the mine and applies the curve multiplier based on the number of workers.
    * @param deep The level of the mine.
    * @param workers The number of workers in the mine.
    * @return The calculated update price in gems.
    */
    function getUpdatePrice(uint256 deep, uint256 workers) external view returns (uint256);

    /**
    * @notice Calculates the production rate of a specified mine based on its workers.
    * @dev Uses the base production of the mine and applies the curve multiplier based on the number of workers.
    * @param deep The level of the mine.
    * @param workers The number of workers in the mine.
    * @return The calculated production rate of the mine.
    */
    function getMineProduction(uint256 deep, uint256 workers) external view returns (uint256);

    /**
    * @notice Retrieves the list of mines owned by a specified user.
    * @param _user The address of the user.
    * @return An array of mines belonging to the user.
    */
    function getUserMines(address _user) external view returns (mine[] memory);    

    /**
    * @notice Calculates the total production rate per time unit for all of a user's mines.
    * @param userAddress The address of the user.
    * @return The total production rate across all mines.
    */
    function getUserProductionPerTime(address userAddress) external view returns (uint256);

    /**
    * @notice Calculates the total accumulated production for all of a user's mines since their last claim.
    * @param userAddress The address of the user.
    * @return The total accumulated production in gems.
    * @custom:require The user must be registered as a player.
    */
    function getUserTotalProduction(address userAddress) external view returns (uint256);
}