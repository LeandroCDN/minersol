// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.22;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ISignatureTransfer} from "./interfaces/ISignatureTransfer.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * - Claim pot and reset user  seasson => prize
 * - Block user
 * - top user
 * - Events
 * - update user bonus ($$$)
 * - wld to usd
 * - max time ($$$)
 * - claim * N ($$$) (0,1 wld - x7)
 */
contract Miner is Ownable {
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

    ISignatureTransfer public permit2 = ISignatureTransfer(0x000000000022D473030F116dDEE9F6B43aC78BA3);

    uint256 public totalGems;
    uint256 public initialGems = 20;
    uint256 public expandBonus = 2;
    uint256 public maxExpandLevel = 5;
    uint256 public expandPrice = 1 ether;
    uint256 public curveMultiplier = 115; // 1.15
    uint256 public seasson;
    uint256 public claimeablePrizeDateLimit;
    bool public claimeablePrize;
    IERC20 public currency;

    mapping(address => user) public users;
    mapping(uint256 => mineBase) public mineBaseInfo;
    mapping(uint256 seasson => seasonData) public seassonsPrizes;

    constructor() Ownable(msg.sender) {}

    /**
     * PUBLIC FUNCTIONS        *
     */
    function start(string memory name) public {
        user storage userData = users[msg.sender];
        require(!userData.player, "only non players");
        userData.player = true;
        userData.gems = initialGems;
        userData.name = name;
        userData.bonus = 100;
        userData.lastClaim = uint32(block.timestamp);
        userData.lastSeassonClaim = uint32(seasson);
        mine memory newMine;
        userData.mines.push(newMine);
    }

    function unlockDeep(uint256 deep) public {
        require(deep > 0, "no zero");
        user storage userData = users[msg.sender];
        require(userData.player, "only players");
        require(deep == userData.mines.length, "deep unlocked");

        if (deep != 1) {
            require(userData.mines[deep - 1].workers > 0, "Need previuos mine unlocked");
        }
        uint256 updatePrice = getUpdatePrice(deep, 0);
        require(userData.gems >= updatePrice, "no gems");
        userData.gems -= updatePrice;
        totalGems -= updatePrice;
        mine memory newMine;
        userData.mines.push(newMine);
        userData.mines[deep].workers = 1;

        userData.mines[deep].space = 1;
        userData.mines[deep].production = getMineProduction(deep, 1);
    }

    function updateMiner(uint256 deep) public {
        user storage userData = users[msg.sender];
        require(deep < userData.mines.length, "no mine here");
        require(userData.player, "only players");

        uint256 updatePrice = getUpdatePrice(deep, userData.mines[deep].workers);
        require(userData.gems >= updatePrice, "no gems");
        userData.gems -= updatePrice;
        totalGems -= updatePrice;
        claim(msg.sender);
        userData.mines[deep].workers += 1;
        userData.mines[deep].production = getMineProduction(deep, userData.mines[deep].workers += 1);
    }

    function expand(
        uint256 deep,
        ISignatureTransfer.PermitTransferFrom memory permit,
        ISignatureTransfer.SignatureTransferDetails calldata transferDetails,
        bytes calldata signature
    ) public {
        user storage userData = users[msg.sender];
        require(deep < userData.mines.length, "no mine here");
        require(userData.player, "only players");
        require(userData.mines[deep].space < maxExpandLevel, "Expand limit");
        require(transferDetails.requestedAmount >= expandPrice, "Permit amount fail");
        require(transferDetails.to >= address(this), "Permit to fail");
        require(permit.permitted.token == address(currency), "Permit to fail");
        require(permit.nonce == userData.nonce, "user nonce error");

        depositERC20(permit, transferDetails, signature, msg.sender);
        currency.transfer(owner(), (expandPrice * 40) / 100);
        userData.mines[deep].space += expandBonus;
        userData.nonce++;
    }

    function claim(address userAddress) public {
        user storage userData = users[userAddress];
        require(userData.player, "only  players");
        require(userData.lastSeassonClaim == seasson, "seasson error");

        mine[] memory userMines = userData.mines;
        uint256 time = block.timestamp - userData.lastClaim;
        uint256 l = userData.mines.length;
        uint256 total;

        for (uint256 i; i < l; i++) {
            total += userMines[i].production * (time / 1) * userMines[i].space;
        }
        userData.gems += (total * userData.bonus) / 100;
        totalGems += (total * userData.bonus) / 100;
        userData.lastClaim = uint32(block.timestamp);
    }

    function claimPrize() public {
        user storage userData = users[msg.sender];
        seasonData memory seasonInfo = seassonsPrizes[seasson - 1];
        require(userData.lastSeassonClaim < seasson);
        require(block.timestamp < claimeablePrizeDateLimit);
        userData.lastSeassonClaim = uint32(seasson);

        uint256 participateAmount = (userData.gems * 1000000) / seasonInfo.totalSeassonGems;
        require(participateAmount > 0);

        uint256 prizeToPay = (seasonInfo.totalSeassonPrizes * participateAmount) / 1000000;

        userData.gemsPerSeason[seasson] = userData.gems;
        userData.gems = 0;
        userData.lastClaim = uint32(block.timestamp);
        userData.lastSeassonClaim = uint32(seasson);
        userData.bonus += 10;
        delete userData.mines;
        currency.transfer(msg.sender, prizeToPay);
    }

    /**
     *       OWNER FUNCTIONS       **
     */
    function setCurveMultiplier(uint256 _curveMultiplier) public onlyOwner {
        curveMultiplier = _curveMultiplier;
    }

    function setMineBaseInfo(mineBase[] memory baseInfo, uint256 index) public onlyOwner {
        uint256 length = baseInfo.length + index;
        for (index; index < length; index++) {
            mineBaseInfo[index] = baseInfo[index];
        }
    }

    function setExpandPrice(uint256 _expandPrice) public onlyOwner {
        expandPrice = _expandPrice;
    }

    function startSeassonRewardPeriod(uint256 _claimeablePrizeDateLimit) public onlyOwner {
        require(_claimeablePrizeDateLimit > block.timestamp + 5 days, "Claim error");
        claimeablePrizeDateLimit = _claimeablePrizeDateLimit;
        seassonsPrizes[seasson] = seasonData(totalGems, currency.balanceOf(address(this)));
        seasson++;
    }

    //todo this dont work
    function getUpdatePrice(uint256 deep, uint256 workers) public view returns (uint256) {
        return mineBaseInfo[deep].baseCost * (curveMultiplier ** workers);
    }

    //todo this dont work
    function getMineProduction(uint256 deep, uint256 workers) public view returns (uint256) {
        return mineBaseInfo[deep].baseProduction * ((curveMultiplier ** workers) / 100);
    }

    function getUserMines(address _user) public view returns (mine[] memory) {
        return users[_user].mines;
    }

    function getUserProductionPerTime(address userAddress) public view returns (uint256) {
        user storage data = users[userAddress];
        mine[] memory userMines = data.mines;
        uint256 l = data.mines.length;
        uint256 total;

        for (uint256 i; i < l; i++) {
            total += userMines[i].production * userMines[i].space;
        }

        return total;
    }

    function getUserTotalProduction(address userAddress) public view returns (uint256) {
        user storage data = users[userAddress];
        require(data.player, "only  players");

        mine[] memory userMines = data.mines;
        uint256 time = block.timestamp - data.lastClaim;
        uint256 l = data.mines.length;
        uint256 total;

        for (uint256 i; i < l; i++) {
            total += userMines[i].production * (time / 1) * userMines[i].space;
        }

        return total;
    }

    // Deposit some amount of an ERC20 token from the caller
    // into this contract using Permit2.
    function depositERC20(
        ISignatureTransfer.PermitTransferFrom memory permit,
        ISignatureTransfer.SignatureTransferDetails calldata transferDetails,
        bytes calldata signature,
        address from
    ) internal {
        permit2.permitTransferFrom(permit, transferDetails, from, signature);
    }
}
