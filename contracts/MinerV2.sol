// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ISignatureTransfer} from "./interfaces/ISignatureTransfer.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract MinerV2 is Ownable {
    using SafeMath for uint256;

    // Constants
    uint256 public constant MAX_FLOOR_EXPANSIONS = 5;
    uint256 public constant DEFAULT_STORAGE_TIME = 1 days;
    uint256 public constant STORAGE_EXPANSION_COST = 1 ether;
    uint256 public constant DEFAULT_HOUSE_PERCENTAGE = 40;  // 40% goes to house

    // Game State
    struct Floor {
        uint256 level;          // Current level of the floor
        uint256 expansions;     // Number of expansions purchased
        uint256 production;     // Current production rate
        uint256 lastUpdate;     // Last time production was updated
    }

    struct Player {
        uint256 points;         // Current points
        uint256 totalPoints;    // Total points earned
        uint256 storageTime;    // Maximum storage time
        uint256 lastClaim;      // Last claim timestamp
        uint256 seasonPoints;   // Points earned in current season
        mapping(uint256 => bool) migrated; // Whether player migrated in each season
        mapping(uint256 => uint256) seasonHistory; // Points per season
        Floor[] floors;         // Player's floors
    }

    struct Season {
        uint256 startTime;
        uint256 duration;       // Duration of the season in seconds
        uint256 totalPoints;    // Total points in this season
        uint256 totalVolume;    // Total volume of payments
        uint256 houseVolume;    // Total volume sent to house
        uint256 seasonReward;   // Total reward for this season
        uint256 claimedRewards; // Total rewards claimed by players
    }

    // State Variables
    IERC20 public currency;
    ISignatureTransfer public permit2;
    address public houseWallet;
    uint256 public currentSeason;
    uint256 public baseProductionRate = 1;
    uint256 public baseUpgradeCost = 100;
    uint256 public upgradeCostMultiplier = 120; // 1.2x per level
    uint256 public productionMultiplier = 110;  // 1.1x per level
    uint256 public defaultSeasonDuration = 30 days; // Default season duration
    uint256 public housePercentage = DEFAULT_HOUSE_PERCENTAGE;

    mapping(address => Player) public players;
    mapping(uint256 => Season) public seasons;
    mapping(uint256 => uint256) public floorBaseCosts;

    // Events
    event SeasonStarted(uint256 seasonId, uint256 startTime, uint256 duration);
    event SeasonEnded(uint256 seasonId, uint256 totalPoints, uint256 totalVolume);
    event PlayerMigrated(address player, uint256 seasonId, uint256 reward);
    event FloorUpgraded(address player, uint256 floorId, uint256 newLevel);
    event FloorExpanded(address player, uint256 floorId, uint256 newExpansions);
    event PointsClaimed(address player, uint256 amount);
    event HousePercentageUpdated(uint256 newPercentage);

    constructor(
        address _currency, 
        address _permit2,
        address _houseWallet
    ) Ownable(msg.sender) {
        currency = IERC20(_currency);
        permit2 = ISignatureTransfer(_permit2);
        houseWallet = _houseWallet;
    }

    // View Functions
    function isSeasonActive(uint256 seasonId) public view returns (bool) {
        Season storage season = seasons[seasonId];
        if (season.startTime == 0) return false;
        return block.timestamp < season.startTime + season.duration;
    }

    function getCurrentSeason() public view returns (uint256) {
        if (currentSeason == 0) return 0;
        
        // If current season has ended, return next season
        if (!isSeasonActive(currentSeason)) {
            return currentSeason + 1;
        }
        
        return currentSeason;
    }

    // Player Actions
    function startGame() external {
        Player storage player = players[msg.sender];
        require(player.floors.length == 0, "Already started");
        
        player.storageTime = DEFAULT_STORAGE_TIME;
        player.lastClaim = block.timestamp;
        player.migrated[currentSeason] = false;
        
        // Initialize first floor
        Floor memory firstFloor;
        firstFloor.level = 1;
        firstFloor.production = baseProductionRate;
        firstFloor.lastUpdate = block.timestamp;
        player.floors.push(firstFloor);
    }

    function upgradeFloor(uint256 floorId) external {
        Player storage player = players[msg.sender];
        require(floorId < player.floors.length, "Invalid floor");
        
        Floor storage floor = player.floors[floorId];
        uint256 upgradeCost = calculateUpgradeCost(floor.level);
        
        require(player.points >= upgradeCost, "Insufficient points");
        
        player.points -= upgradeCost;
        floor.level++;
        floor.production = calculateProduction(floor.level, floor.expansions);
        
        emit FloorUpgraded(msg.sender, floorId, floor.level);
    }

    function expandFloor(
        uint256 floorId,
        ISignatureTransfer.PermitTransferFrom memory permit,
        ISignatureTransfer.SignatureTransferDetails calldata transferDetails,
        bytes calldata signature
    ) external {
        Player storage player = players[msg.sender];
        require(floorId < player.floors.length, "Invalid floor");
        
        Floor storage floor = player.floors[floorId];
        require(floor.expansions < MAX_FLOOR_EXPANSIONS, "Max expansions reached");
        
        // Handle currency payment
        require(transferDetails.requestedAmount >= STORAGE_EXPANSION_COST, "Insufficient payment");
        _processCurrencyPayment(permit, transferDetails, signature);
        
        floor.expansions++;
        floor.production = calculateProduction(floor.level, floor.expansions);
        
        emit FloorExpanded(msg.sender, floorId, floor.expansions);
    }

    function claimPoints() external {
        Player storage player = players[msg.sender];
        require(player.floors.length > 0, "Not started");
        
        // Ensure we're in the current season
        _ensureCurrentSeason();
        
        uint256 timeSinceLastClaim = block.timestamp - player.lastClaim;
        uint256 maxStorageTime = player.storageTime;
        
        if (timeSinceLastClaim > maxStorageTime) {
            timeSinceLastClaim = maxStorageTime;
        }
        
        uint256 pointsToClaim = calculatePointsToClaim(msg.sender, timeSinceLastClaim);
        
        player.points += pointsToClaim;
        player.totalPoints += pointsToClaim;
        player.seasonPoints += pointsToClaim;
        player.lastClaim = block.timestamp;
        
        // Update season total points
        seasons[currentSeason].totalPoints += pointsToClaim;
        
        emit PointsClaimed(msg.sender, pointsToClaim);
    }

    function migrateToNewSeason(bool acceptDeal) external {
        Player storage player = players[msg.sender];
        require(!player.migrated[currentSeason], "Already migrated in current season");
        
        uint256 nextSeason = getCurrentSeason();
        require(nextSeason > currentSeason, "No new season available");
        
        // Ensure the new season is started
        _ensureCurrentSeason();
        
        uint256 reward = calculateSeasonReward(msg.sender);
        
        if (acceptDeal) {
            // Player accepts the deal - reset account and receive reward
            player.points = 0;
            player.seasonPoints = 0;
            player.migrated[currentSeason] = true;
            delete player.floors;
            
            // Start fresh with one floor
            Floor memory firstFloor;
            firstFloor.level = 1;
            firstFloor.production = baseProductionRate;
            firstFloor.lastUpdate = block.timestamp;
            player.floors.push(firstFloor);
            
            // Update season claimed rewards
            seasons[currentSeason - 1].claimedRewards += reward;
            
            // Transfer reward
            currency.transfer(msg.sender, reward);
        } else {
            // Player rejects the deal - keep progress and add reward to new season
            player.migrated[currentSeason] = true;
            
            // Add player's points to the new season
            seasons[currentSeason].totalPoints += player.seasonPoints;
            
            // Add unclaimed reward to the new season's reward pool
            seasons[currentSeason].seasonReward += reward;
        }
        
        // Update player's season history
        player.seasonHistory[currentSeason - 1] = player.seasonPoints;
        
        emit PlayerMigrated(msg.sender, currentSeason, reward);
    }

    // Owner Functions
    function startFirstSeason(uint256 duration) external onlyOwner {
        require(currentSeason == 0, "First season already started");
        require(duration > 0, "Invalid duration");
        
        defaultSeasonDuration = duration;
        _startNewSeason(duration);
    }

    function setDefaultSeasonDuration(uint256 duration) external onlyOwner {
        require(duration > 0, "Invalid duration");
        defaultSeasonDuration = duration;
    }

    function setHouseWallet(address _houseWallet) external onlyOwner {
        require(_houseWallet != address(0), "Invalid address");
        houseWallet = _houseWallet;
    }

    function setHousePercentage(uint256 _housePercentage) external onlyOwner {
        require(_housePercentage <= 100, "Invalid percentage");
        housePercentage = _housePercentage;
        emit HousePercentageUpdated(_housePercentage);
    }

    // Internal Functions
    function _startNewSeason(uint256 duration) internal {
        currentSeason++;
        
        // Calculate and store the reward from previous season
        if (currentSeason > 1) {
            uint256 previousSeasonReward = currency.balanceOf(address(this)) - seasons[currentSeason - 1].houseVolume;
            seasons[currentSeason - 1].seasonReward = previousSeasonReward;
        }
        
        seasons[currentSeason] = Season({
            startTime: block.timestamp,
            duration: duration,
            totalPoints: 0,
            totalVolume: 0,
            houseVolume: 0,
            seasonReward: 0,
            claimedRewards: 0
        });
        
        emit SeasonStarted(currentSeason, block.timestamp, duration);
    }

    function _ensureCurrentSeason() internal {
        uint256 nextSeason = getCurrentSeason();
        if (nextSeason > currentSeason) {
            _startNewSeason(defaultSeasonDuration);
        }
    }

    function _processCurrencyPayment(
        ISignatureTransfer.PermitTransferFrom memory permit,
        ISignatureTransfer.SignatureTransferDetails calldata transferDetails,
        bytes calldata signature
    ) internal {
        require(permit.permitted.token == address(currency), "Invalid token");
        permit2.permitTransferFrom(permit, transferDetails, msg.sender, signature);
        
        uint256 amount = transferDetails.requestedAmount;
        uint256 houseAmount = (amount * housePercentage) / 100;
        
        // Update season volume
        seasons[currentSeason].totalVolume += amount;
        seasons[currentSeason].houseVolume += houseAmount;
        
        // Transfer house percentage immediately
        currency.transfer(houseWallet, houseAmount);
    }

    // View Functions
    function calculateUpgradeCost(uint256 level) public view returns (uint256) {
        return baseUpgradeCost * (upgradeCostMultiplier ** level) / 100;
    }

    function calculateProduction(uint256 level, uint256 expansions) public view returns (uint256) {
        return baseProductionRate * (productionMultiplier ** level) / 100 * (expansions + 1);
    }

    function calculatePointsToClaim(address playerAddress, uint256 time) public view returns (uint256) {
        Player storage player = players[playerAddress];
        uint256 totalProduction = 0;
        
        for (uint256 i = 0; i < player.floors.length; i++) {
            totalProduction += player.floors[i].production;
        }
        
        return totalProduction * time;
    }

    function calculateSeasonReward(address playerAddress) public view returns (uint256) {
        Player storage player = players[playerAddress];
        Season storage season = seasons[currentSeason - 1]; // Previous season's reward
        
        if (season.totalPoints == 0) return 0;
        
        uint256 playerShare = (player.seasonPoints * 1e18) / season.totalPoints;
        return (season.seasonReward * playerShare) / 1e18;
    }

    function getPlayerFloors(address playerAddress) external view returns (Floor[] memory) {
        return players[playerAddress].floors;
    }

    function getSeasonInfo(uint256 seasonId) external view returns (Season memory) {
        return seasons[seasonId];
    }
} 