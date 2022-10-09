// import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
// import { expect } from "chai";
// import { BaseContract, Contract, ContractFactory } from "ethers";
// import { parseUnits } from "ethers/lib/utils";
// import { ethers, waffle } from "hardhat";

// const ADMIN_ROLE = ethers.utils.hexZeroPad(ethers.utils.hexlify(0x00), 32);
// const GAME_ROLE = ethers.utils.keccak256(ethers.utils.toUtf8Bytes("GAME_ROLE"));
// const GAS_TOKEN_ADDRESS = "0x0000000000000000000000000000000000000000";
// const ADDRESS_0 = "0x0000000000000000000000000000000000000000";

// describe("apply new casino model", () => {
//   let tx;
//   let vaultContract: Contract,
//     betTokenContract: Contract,
//     handicapBetContract: Contract;
//   const provider = waffle.provider;
//   let b0: SignerWithAddress,
//     b1: SignerWithAddress,
//     b2: SignerWithAddress,
//     b3: SignerWithAddress;
//   beforeEach(async () => {
//     const [a0, a1, a2, a3] = await ethers.getSigners();
//     [b0, b1, b2, b3] = [a0, a1, a2, a3];

//     const betFactory = await ethers.getContractFactory("EqualBetsToken");
//     betTokenContract = await betFactory.deploy();
//     const equalBetCasFactory = await ethers.getContractFactory("Vault");
//     vaultContract = await equalBetCasFactory.deploy(
//       "0x326C977E6efc84E512bB9C30f76E30c160eD06FB",
//       "0xB9756312523826A566e222a34793E414A81c88E1",
//       "0x3662303964333762323834663436353562623531306634393465646331313166",
//       parseUnits("0.1", 18)
//     );
//     const handicapBetFactory = await ethers.getContractFactory("HandicapBets");
//     handicapBetContract = await handicapBetFactory.deploy(
//       vaultContract.address
//     );

//     await vaultContract.grantRole(GAME_ROLE, handicapBetContract.address);

//     betTokenContract.mint(b0.address, parseUnits("1000", 18));
//     betTokenContract.mint(b1.address, parseUnits("1000", 18));

//     const startTime = Math.round((new Date().getTime() + 3600000) / 1000);
//     await vaultContract.addToken(betTokenContract.address);
//     await vaultContract.setTokenMinBetAmount(
//       betTokenContract.address,
//       parseUnits("10", 18)
//     );
//     await vaultContract.setTokenMaxBetAmount(
//       betTokenContract.address,
//       parseUnits("100", 18)
//     );

//     await vaultContract.addToken(GAS_TOKEN_ADDRESS);
//     await vaultContract.setTokenMinBetAmount(
//       GAS_TOKEN_ADDRESS,
//       parseUnits,
//       "10",
//       18
//     );
//     await vaultContract.setTokenMaxBetAmount(
//       GAS_TOKEN_ADDRESS,
//       parseUnits,
//       "100",
//       18
//     );

//     await vaultContract.testFulfillGamesCreate(
//       ["0x3100000000000000000000000000000000000000000000000000000000000000"],
//       [startTime],
//       ["hn"],
//       ["hcm"]
//     );

//     await betTokenContract
//       .connect(b0)
//       .approve(handicapBetContract.address, parseUnits("1000", 18));
//     await betTokenContract
//       .connect(b1)
//       .approve(handicapBetContract.address, parseUnits("1000", 18));
//   });

//   it("stronger home odds 75", async () => {
//     await handicapBetContract.newHandicapBet(
//       "0x3100000000000000000000000000000000000000000000000000000000000000",
//       0, // stronger
//       0, // choosen
//       0, // odds
//       parseUnits("10", 18),
//       betTokenContract.address
//     );
//     await vaultContract.testFulfillGamesResolve(
//       ["0x3100000000000000000000000000000000000000000000000000000000000000"],
//       [0],
//       [0],
//       [11]
//     );

//     const betId = parseInt(
//       (await handicapBetContract.getLastHandicapBets(10))[0].id
//     );
//     await handicapBetContract.connect(b1).acceptHandicapBet(betId, 1);
//     await handicapBetContract.resolveHandicapBet(betId);
//     console.log(
//       "away: ",
//       (await betTokenContract.balanceOf(b0.address)) / 1e18
//     );
//     console.log(
//       "home: ",
//       (await betTokenContract.balanceOf(b1.address)) / 1e18
//     );
//     console.log(
//       (await betTokenContract.balanceOf(vaultContract.address)) / 1e18
//     );
//   });
// });
