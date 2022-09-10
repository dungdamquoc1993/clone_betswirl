import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { Contract, ContractFactory } from "ethers";
import { parseUnits } from "ethers/lib/utils";
import { ethers } from "hardhat";

const ADMIN_ROLE = ethers.utils.hexZeroPad(ethers.utils.hexlify(0x00), 32);
const GAME_ROLE = ethers.utils.keccak256(ethers.utils.toUtf8Bytes("GAME_ROLE"));
const GAS_TOKEN_ADDRESS = "0x0000000000000000000000000000000000000000";
// addToken
// setAllowedToken
// setPausedToken
// setBalanceRisk
// setTokenMinBetAmount
// setHouseEdgeSplit
// setTokenVRFSubId
describe("Casino", async () => {
  beforeEach(async () => {
    const [b0, b1, b2] = await ethers.getSigners();

    const bankFactory = await ethers.getContractFactory("Bank");
    const bankContract = await bankFactory.deploy(b1.address, b2.address);
    await bankContract.deployed();

    const gameFactory = await ethers.getContractFactory("Roulette");
    const gameContract = await gameFactory.deploy(
      bankContract.address,
      "0x2Ca8E0C643bDe4C2E08ab1fA0da3401AdAD7734D",
      "0xb4c4a493AB6356497713A78FFA6c60FB53517c63"
    );
    await gameContract.deployed();

    await bankContract.addToken(GAS_TOKEN_ADDRESS);
    await bankContract.setAllowedToken(GAS_TOKEN_ADDRESS, true);
    await bankContract.setPausedToken(GAS_TOKEN_ADDRESS, false);
    await bankContract.setBalanceRisk(GAS_TOKEN_ADDRESS, 1000);
    await bankContract.setTokenMinBetAmount(
      GAS_TOKEN_ADDRESS,
      parseUnits("0.1", 18)
    );
    await bankContract.setMinPartnerTransferAmount(
      GAS_TOKEN_ADDRESS,
      parseUnits("1", 18)
    );
    await bankContract.setHouseEdgeSplit(
      GAS_TOKEN_ADDRESS,
      2000,
      2000,
      2000,
      2000,
      2000
    );
    await bankContract.setTokenVRFSubId(GAS_TOKEN_ADDRESS, 1220);
    await gameContract.setHouseEdge(GAS_TOKEN_ADDRESS, 400);
    await gameContract.setVRFCallbackGasLimit(GAS_TOKEN_ADDRESS, 100000);
    await gameContract.setChainlinkConfig(3, "0x79d3d8832d904592c0bf9818b621522c988bb8b0c05cdc3b15aea1b6e8db0c15");
    console.log(await gameContract.testVRFCost(GAS_TOKEN_ADDRESS))
  
  });
  it("some thing wrong", async () => {});
});
