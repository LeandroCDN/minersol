import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { expect } from "chai";
import hre from "hardhat";

describe("RaceGame", function () {
  async function deployRaceGameFixture() {
    const [owner, player1, player2, player3, player4, player5, player6, player7, player8, player9, player10] = await hre.ethers.getSigners();

    const RaceGame = await hre.ethers.getContractFactory("RaceGame");
    const raceGame = await RaceGame.deploy();
    const players = [player1, player2, player3, player4, player5, player6, player7, player8, player9, player10];
    return { raceGame, owner, player1, player2, player3, players };
  }

  describe("Ticket Buying", function () {
    it("Should allow players to buy tickets", async function () {
      const { raceGame, player1 } = await loadFixture(deployRaceGameFixture);
      
      await raceGame.connect(player1).buyTicket(5);
      const playerInfo = await raceGame.vPlayerInfo(player1.address);
      
      expect(playerInfo.numbers[0]).to.equal(5);
      expect(playerInfo.numbers[1]).to.equal(6);
    });

    it("Should prevent buying the same ticket twice", async function () {
      const { raceGame, player1 } = await loadFixture(deployRaceGameFixture);
      
      await raceGame.connect(player1).buyTicket(5);
      await expect(raceGame.connect(player1).buyTicket(5)).to.be.revertedWith("no allowed");
    });
  });

  describe("Race Mechanics", function () {
    it("Should start a race and generate winners", async function () {
      const { raceGame, players} = await loadFixture(deployRaceGameFixture);
      
      // Compra de boletos
      for (let i = 0; i < 10; i++) {
			 // Reusar jugadores si son menos de 20
				await raceGame.connect(players[i]).buyTicket(i*2);
				
      }
      await raceGame.startRace(123);
      
      const raceDetails = await raceGame.vRace(0);
			console.log(await raceDetails);
			console.log(await raceDetails.winnerPositions);
      expect(await raceDetails.winnerPositions.length).to.equal(20);
    });

    it("Should allow claiming points after race", async function () {
      const { raceGame, players} = await loadFixture(deployRaceGameFixture);
      
      // Compra de boletos
      for (let i = 0; i < 10; i++) {
			 // Reusar jugadores si son menos de 20
				await raceGame.connect(players[i]).buyTicket(i*2);
				
      }
      await raceGame.startRace(123);
      
      const raceDetails = await raceGame.vRace(0);
			const winnerAddress = raceDetails.race[Number(raceDetails.winnerPositions[0])];
			let playerInfo = await raceGame.vPlayerInfo(winnerAddress);
			console.log(playerInfo);
			const winner = players.find((player) => player.address === winnerAddress);
			if (winner) {
				await raceGame.connect(winner).claim();
			} else {
				console.error(`Could not find player with address ${winnerAddress}`);
			}
      playerInfo = await raceGame.vPlayerInfo(winnerAddress);
      expect(playerInfo.points).to.equal(500);
      // expect(playerInfo.unclaimedPoints).to.equal(0);
    });
  });
});