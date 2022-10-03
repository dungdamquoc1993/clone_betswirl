import { ethers } from "hardhat";
import "@nomiclabs/hardhat-etherscan";

async function main() {
  const [priv_key] = await ethers.getSigners();
  const bankFactory = await ethers.getContractFactory("Bank");
  const bankContract = await bankFactory
    .connect(priv_key)
    .deploy("0xfbC25FE9A4aE6654462678c4D622E56997325e0C", "0xBc456a297b8cDc49E9F28548CF43a127b99D237d");
  await bankContract.deployed();
  console.log("bank contract address is:", bankContract.address);
  // bank address 0x9C56f9CE846C1cCa0621F483279b294FB39A3389
  // treasureWallet 0xfbC25FE9A4aE6654462678c4D622E56997325e0C
  // teamWallet 0xBc456a297b8cDc49E9F28548CF43a127b99D237d

  const rouletteFactory = await ethers.getContractFactory("Roulette");
  const rouletteContract = await rouletteFactory
    .connect(priv_key)
    .deploy(bankContract.address, "0x2Ca8E0C643bDe4C2E08ab1fA0da3401AdAD7734D", "0xb4c4a493AB6356497713A78FFA6c60FB53517c63");
    await rouletteContract.deployed();
    console.log("roulette contract is: ", rouletteContract.address);
  // roulette address 0xB89364e6853C8EF59160E4B4458b65224640CCAa
}


main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});


  // const bankContract = await bankFactory.deploy(unlockTime, { value: lockedAmount });
