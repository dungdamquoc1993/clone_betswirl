import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { BaseContract, Contract, ContractFactory } from "ethers";
import { parseUnits } from "ethers/lib/utils";
import { ethers, waffle } from "hardhat";

// addToken
// setAllowedToken
// setPausedToken
// setBalanceRisk
// setTokenMinBetAmount
// setHouseEdgeSplit
// setTokenVRFSubId

const ADMIN_ROLE = ethers.utils.hexZeroPad(ethers.utils.hexlify(0x00), 32);
const GAME_ROLE = ethers.utils.keccak256(ethers.utils.toUtf8Bytes("GAME_ROLE"));
const GAS_TOKEN_ADDRESS = "0x0000000000000000000000000000000000000000";
const ADDRESS_0 = "0x0000000000000000000000000000000000000000"

describe("apply new casino model", () => {
  let tx;
  let equalBetContract: Contract, betTokenContract: Contract;
  const provider = waffle.provider;
  let b0: SignerWithAddress,
    b1: SignerWithAddress,
    b2: SignerWithAddress,
    b3: SignerWithAddress;
  beforeEach(async () => {
    const [a0, a1, a2, a3] = await ethers.getSigners();
    [b0, b1, b2, b3] = [a0, a1, a2, a3];

    const betFactory = await ethers.getContractFactory("EqualBetsToken");
    betTokenContract = await betFactory.deploy();
    const equalBetCasFactory = await ethers.getContractFactory("EqualBets");
    equalBetContract = await equalBetCasFactory.deploy(
      "0x326C977E6efc84E512bB9C30f76E30c160eD06FB",
      "0xB9756312523826A566e222a34793E414A81c88E1",
      "0x3662303964333762323834663436353562623531306634393465646331313166",
      parseUnits("0.1", 18)
    );
    betTokenContract.mint(a0.address, parseUnits("1000", 18))
  });
  it("test new handicap bet by equaBetToken", async () => {
    const startTime = Math.round((new Date().getTime() + 3600000) / 1000)
    await equalBetContract.addToken(betTokenContract.address);
    await equalBetContract.setTokenMinBetAmount(betTokenContract.address, parseUnits("10", 18))
    await equalBetContract.setTokenMaxBetAmount(betTokenContract.address, parseUnits("100", 18))
    await equalBetContract.testFulfillGamesCreate(
      ["0x3100000000000000000000000000000000000000000000000000000000000000"],
      [startTime],
      ["hn"],
      ["hcm"]
    );
    await betTokenContract.approve(equalBetContract.address, parseUnits("1000", 18))
    // make 4 bet
    await equalBetContract.newHandicapBet(
      "0x3100000000000000000000000000000000000000000000000000000000000000",
      0,
      0,
      0,
      parseUnits("10", 18),
      betTokenContract.address
    );
    expect((await equalBetContract.getLastUserHandicapBets(10, b0.address))[0].handicapBetDetail.token).equal(betTokenContract.address)
    expect(((await equalBetContract.getLastUserHandicapBets(10, b0.address))[0].handicapBetDetail.amount)/1e18).equal(9.9)
    expect((await equalBetContract.getLastUserHandicapBets(10, b0.address))[0].handicapBetDetail.odds).equal(0)
    expect(((await equalBetContract.getLastUserHandicapBets(10, b0.address))[0].handicapBetDetail.fee)/1e18).equal(0.1)
    expect((await equalBetContract.getLastUserHandicapBets(10, b0.address))[0].matchDetail.stronger).equal(0)
    expect((await equalBetContract.getLastUserHandicapBets(10, b0.address))[0].matchDetail.homeChoosen).equal(ADDRESS_0)
    expect((await equalBetContract.getLastUserHandicapBets(10, b0.address))[0].matchDetail.awayChoosen).equal(ADDRESS_0)

    // await equalBetContract.newHandicapBet(
    //     "0x3100000000000000000000000000000000000000000000000000000000000000",
    //     1,
    //     1,
    //     25,
    //     parseUnits("10", 18),
    //     betTokenContract.address
    //   );
    //   expect((await equalBetContract.getLastUserHandicapBets(10, b0.address))[1].handicapBetDetail.token).equal(betTokenContract.address)
    //   expect(((await equalBetContract.getLastUserHandicapBets(10, b0.address))[1].handicapBetDetail.amount)/1e18).equal(9.9)
    //   expect((await equalBetContract.getLastUserHandicapBets(10, b0.address))[1].handicapBetDetail.odds).equal(25)
    //   expect(((await equalBetContract.getLastUserHandicapBets(10, b0.address))[1].handicapBetDetail.fee)/1e18).equal(0.1)
    //   expect((await equalBetContract.getLastUserHandicapBets(10, b0.address))[1].matchDetail.stronger).equal(1)
    //   expect((await equalBetContract.getLastUserHandicapBets(10, b0.address))[1].matchDetail.homeChoosen).equal(b0.address)
    //   expect((await equalBetContract.getLastUserHandicapBets(10, b0.address))[1].matchDetail.awayChoosen).equal(ADDRESS_0)

    //   await equalBetContract.newHandicapBet(
    //     "0x3100000000000000000000000000000000000000000000000000000000000000",
    //     1,
    //     1,
    //     25,
    //     parseUnits("10", 18),
    //     betTokenContract.address
    //   );
    //   expect((await equalBetContract.getLastUserHandicapBets(10, b0.address))[2].handicapBetDetail.token).equal(betTokenContract.address)
    //   expect(((await equalBetContract.getLastUserHandicapBets(10, b0.address))[2].handicapBetDetail.amount)/1e18).equal(9.9)
    //   expect((await equalBetContract.getLastUserHandicapBets(10, b0.address))[2].handicapBetDetail.odds).equal(25)
    //   expect(((await equalBetContract.getLastUserHandicapBets(10, b0.address))[2].handicapBetDetail.fee)/1e18).equal(0.1)
    //   expect((await equalBetContract.getLastUserHandicapBets(10, b0.address))[2].matchDetail.stronger).equal(1)
    //   expect((await equalBetContract.getLastUserHandicapBets(10, b0.address))[2].matchDetail.homeChoosen).equal(b0.address)
    //   expect((await equalBetContract.getLastUserHandicapBets(10, b0.address))[2].matchDetail.awayChoosen).equal(ADDRESS_0)
    
    //   await equalBetContract.newHandicapBet(
    //     "0x3100000000000000000000000000000000000000000000000000000000000000",
    //     1,
    //     1,
    //     25,
    //     parseUnits("10", 18),
    //     betTokenContract.address
    //   );
    //   expect((await equalBetContract.getLastUserHandicapBets(10, b0.address))[3].handicapBetDetail.token).equal(betTokenContract.address)
    //   expect(((await equalBetContract.getLastUserHandicapBets(10, b0.address))[3].handicapBetDetail.amount)/1e18).equal(9.9)
    //   expect((await equalBetContract.getLastUserHandicapBets(10, b0.address))[3].handicapBetDetail.odds).equal(25)
    //   expect(((await equalBetContract.getLastUserHandicapBets(10, b0.address))[3].handicapBetDetail.fee)/1e18).equal(0.1)
    //   expect((await equalBetContract.getLastUserHandicapBets(10, b0.address))[3].matchDetail.stronger).equal(1)
    //   expect((await equalBetContract.getLastUserHandicapBets(10, b0.address))[3].matchDetail.homeChoosen).equal(b0.address)
    //   expect((await equalBetContract.getLastUserHandicapBets(10, b0.address))[3].matchDetail.awayChoosen).equal(ADDRESS_0)
    

  });


});
