// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract RaceGame {
    address public owner;
    uint256 constant MAX_PLAYERS = 10;
    uint256 constant NUMBERS_RANGE = 20;
    uint256 constant TICKET_COST = 1;
    uint public currentRace;
    uint public ownerPoints;
    
    // Estructura para representar a un jugador
    struct Player {
        uint points;
        bool pendingReward;
        uint raceIdReward;
        uint[] racesIds;
        uint unclaimedPoints;
        uint256[] numbers;
    }

    struct Race {
        address[20] race;
        uint8[20] winnerPositions;
        uint8 sponsors;
        bool[3] claimed;
    }

    mapping(uint raceId => Race) private races;
    mapping(address userAddress => Player) private playerInfo;

    function buyTicket(uint number) public {
        require(number < NUMBERS_RANGE, "overflow");
        require(races[currentRace].race[number] == address(0), "no allowed");
        require(!playerInfo[msg.sender].pendingReward, "pendin reward");
       
        races[currentRace].race[number] = msg.sender;
        races[currentRace].race[number+1] = msg.sender;

        playerInfo[msg.sender].numbers.push(number);
        playerInfo[msg.sender].numbers.push(number+1);
        playerInfo[msg.sender].racesIds.push(currentRace); // TODO una sola ves! 
        races[currentRace].sponsors++;
        
    }

    function startRace(uint seed) public {
        uint8[20] memory winnerPositions = generateWinners(seed);
        require(winnerPositions.length <= NUMBERS_RANGE, "overflow");
        races[currentRace].winnerPositions = winnerPositions;
        address user;
        for(uint i = 0; i < 3; i++){
            user = races[currentRace].race[winnerPositions[i]];

            playerInfo[user].pendingReward = true;
            playerInfo[user].raceIdReward = currentRace;
            if(i == 0) playerInfo[user].unclaimedPoints +=500;
            if(i == 1) playerInfo[user].unclaimedPoints +=300;
            if(i == 2) playerInfo[user].unclaimedPoints +=100;
        }

        for(uint i; i <NUMBERS_RANGE; i++){
           delete playerInfo[races[currentRace].race[i]].numbers;
        }
        ownerPoints = 100;
        currentRace++;
    }

    function claim() public {
        playerInfo[msg.sender].points += playerInfo[msg.sender].unclaimedPoints;
        playerInfo[msg.sender].unclaimedPoints = 0;
    }   

    function vRace(uint id) public view returns(Race memory){
        return races[id];
    }
    function vPlayerInfo(address user) public view returns(Player memory){
        return playerInfo[user];
    }

    function generateWinners(uint seed) public view returns (uint8[20] memory) {
        uint8[20] memory numbers;

        // Initialize the array with numbers from 0 to 19
        for (uint8 i = 0; i < 20; i++) {
            numbers[i] = i;
        }
        uint j;
        // Fisher-Yates Shuffle
        for (uint i = 19; i > 0; i--) {
            seed = uint(keccak256(abi.encode(
                seed, 
                block.timestamp, 
                block.prevrandao, 
                blockhash(block.number - 1),
                j
            ))); 
            j = seed % (i + 1); // Use modulo to generate a random index
            
            // Swap elements
            uint8 temp = numbers[i];
            numbers[i] = numbers[j];
            numbers[j] = temp;
            
            // Update seed to create a new pseudo-random value
        }

        return numbers;
    }
}