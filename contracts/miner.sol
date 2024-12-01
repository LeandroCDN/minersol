// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.22;

// import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ISignatureTransfer} from "./interfaces/ISignatureTransfer.sol";

contract Miner {
    struct mineBase{
        uint baseProduction;
        uint baseCost;
    }

    struct mine{
        uint workers;
        uint space;
        uint production;
    }

    struct user{
        uint gems;
        uint lastClaim;
        uint bonus;
        
        mine[] mines;
        uint nonce;
        string name;
        bool player;
    }

    ISignatureTransfer public permit2 = ISignatureTransfer(0x000000000022D473030F116dDEE9F6B43aC78BA3);

    //uint totalGems;
    uint public baseCost = 1;
    uint public initialGems = 100;
    uint public initialBonus = 100;
    uint public expandBonus = 2;
    uint public maxExpandLevel = 5;
    uint public curveMultiplier = 115; // 1.15
   
    mapping(address => user)  public users;
    mapping(uint => mineBase)  public mineBaseInfo;

    function start(string memory name) public{
        user storage userData = users[msg.sender];
        require(!userData.player, "only non players");
        userData.player = true;
        userData.gems =  initialGems;
        userData.name = name;
        userData.bonus =  initialBonus;
        userData.lastClaim = block.timestamp;
        mine memory newMine;
        userData.mines.push(newMine); // id 0
    }

    function unlockDeep(uint deep) public {
        require(deep > 0, "no zero");
        user storage userData = users[msg.sender];
        require(userData.player, "only players");
        require(deep == userData.mines.length, "deep unlocked");

        if(deep != 1){
            require(userData.mines[deep-1].workers > 0, "Need previuos mine unlocked");
        }
        uint updatePrice = getUpdatePrice(deep,0);
        require(userData.gems >= updatePrice, "no gems");
        userData.gems -= updatePrice;
        mine memory newMine;
        userData.mines.push(newMine);
        userData.mines[deep].workers = 1;
       
        userData.mines[deep].space = 1;
        userData.mines[deep].production = getMineProduction(deep, 1);
    }

    function updateMiner(uint deep) public {
        user storage userData = users[msg.sender];
        require(deep < userData.mines.length, "no mine here");
        require(userData.player, "only players");
        
        uint updatePrice = getUpdatePrice(deep,userData.mines[deep].workers);
        require(userData.gems >= updatePrice, "no gems");
        userData.gems -= updatePrice;
        claim(msg.sender);
        userData.mines[deep].workers +=1;
        userData.mines[deep].production = getMineProduction(deep, userData.mines[deep].workers +=1);
    }
    function expand(uint deep) public{
        user storage data = users[msg.sender];
        require(deep < data.mines.length, "no mine here");
        require(data.player, "only players");
        require( data.mines[deep].space < maxExpandLevel, "Expand limit");
        data.mines[deep].space += expandBonus;
    }
    
    function claim(address userAddress)public {
        user storage data = users[userAddress];
        require(data.player, "only  players");

        mine[] memory userMines =  data.mines;
        uint time = block.timestamp - data.lastClaim;
        uint l = data.mines.length;
        uint total;

        for(uint i; i < l; i++){
            total += userMines[i].production * ( time / 1) * userMines[i].space;
        }
        // aplied bonus
        data.gems += total;
        data.lastClaim = block.timestamp;
    }

    function getUpdatePrice(uint deep, uint workers) public view returns(uint){
        return mineBaseInfo[deep].baseCost * (curveMultiplier ** workers); 
    }

    function getMineProduction(uint deep, uint workers) public view returns(uint){
        return mineBaseInfo[deep].baseProduction * (curveMultiplier ** workers); 
    }

    function getUserMines(address _user) public view returns(mine[] memory){
        return users[_user].mines;
    }

    function getUserProductionPerTime(address userAddress) public view returns(uint){
        user storage data = users[userAddress];
        mine[] memory userMines =  data.mines;
        uint l = data.mines.length;
        uint total;

        for(uint i; i < l; i++){
            total += userMines[i].production * userMines[i].space;
        }
       
        return total;
    }

    function getUserTotalProduction(address userAddress) public view returns(uint){
        user storage data = users[userAddress];
        require(data.player, "only  players");

        mine[] memory userMines =  data.mines;
        uint time = block.timestamp - data.lastClaim;
        uint l = data.mines.length;
        uint total;

        for(uint i; i < l; i++){
            total += userMines[i].production * ( time / 1) * userMines[i].space;
        }
        
        return total;
    }
    
    // Deposit some amount of an ERC20 token from the caller
    // into this contract using Permit2.
    function depositERC20(
        ISignatureTransfer.PermitTransferFrom memory permit,
        ISignatureTransfer.SignatureTransferDetails calldata transferDetails,
        bytes calldata signature
    ) external {
        permit2.permitTransferFrom(permit, transferDetails, msg.sender , signature);
    }

}