import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { BaseContract, Contract, ContractFactory } from "ethers";
import { parseUnits } from "ethers/lib/utils";
import { ethers, waffle } from "hardhat";

const ADMIN_ROLE = ethers.utils.hexZeroPad(ethers.utils.hexlify(0x00), 32);
const GAME_ROLE = ethers.utils.keccak256(ethers.utils.toUtf8Bytes("GAME_ROLE"));
const GAS_TOKEN_ADDRESS = "0x0000000000000000000000000000000000000000";
const ADDRESS_0 = "0x0000000000000000000000000000000000000000";

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
    betTokenContract.mint(b0.address, parseUnits("1000", 18));
    betTokenContract.mint(b1.address, parseUnits("1000", 18));
  });

  it("test accept bet by gasToken with stronger", async () => {
    const startTime = Math.round((new Date().getTime() + 60 * 60 * 1000) / 1000);
    await equalBetContract.addToken(GAS_TOKEN_ADDRESS);
    await equalBetContract.setTokenMinBetAmount(
      GAS_TOKEN_ADDRESS,
      parseUnits("10", 18)
    );
    await equalBetContract.setTokenMaxBetAmount(
      GAS_TOKEN_ADDRESS,
      parseUnits("100", 18)
    );
    await equalBetContract.testFulfillGamesCreate(
      ["0x3100000000000000000000000000000000000000000000000000000000000000"],
      [startTime],
      ["hn"],
      ["hcm"]
    );
    await equalBetContract.newHandicapBet(
      "0x3100000000000000000000000000000000000000000000000000000000000000",
      2, // stronger
      0, // choosen
      25, // odds
      parseUnits("10", 18),
      GAS_TOKEN_ADDRESS,
      { value: parseUnits("10", 18) }
    );
 
    const betId = parseInt((await equalBetContract.getLastHandicapBets(10))[0].id)
    await equalBetContract.connect(b1).acceptHandicapBet(betId, 1, {value: parseUnits("1000", 18)})
    expect((await equalBetContract.handicapBets(betId)).proposeUser).equal(b0.address)
    expect((await equalBetContract.handicapBets(betId)).acceptUser).equal(b1.address)
    expect((await equalBetContract.handicapBets(betId)).matchDetail.homeChoosen).equal(b1.address)
    expect((await equalBetContract.handicapBets(betId)).matchDetail.awayChoosen).equal(b0.address)
    expect((await equalBetContract.handicapBets(betId)).handicapBetDetail.amount).equal(parseUnits("9.9", 18))
    expect((await equalBetContract.handicapBets(betId)).handicapBetDetail.token).equal(GAS_TOKEN_ADDRESS)
    expect((await equalBetContract.handicapBets(betId)).handicapBetDetail.odds).equal(25)
    expect((await equalBetContract.handicapBets(betId)).matchDetail.stronger).equal(2)
    expect((await provider.getBalance(equalBetContract.address))).equal(parseUnits("20", 18))
        

  });
});
