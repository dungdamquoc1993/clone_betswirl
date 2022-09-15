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

describe("apply new casino model", () => {
  let tx;
  let bankContract: Contract,
    equalBetTokenContract: Contract,
    contractBankLPTokenOfGasToken: Contract,
    contractBankLPTokenOfERC20: Contract;
  const BankLPTokenArtifacts = require("../artifacts/contracts/BankLPToken.sol/BankLPToken.json");
  const provider = waffle.provider;
  let b0: SignerWithAddress,
    b1: SignerWithAddress,
    b2: SignerWithAddress,
    b3: SignerWithAddress;
  beforeEach(async () => {
    const [a0, a1, a2, a3] = await ethers.getSigners();
    [b0, b1, b2, b3] = [a0, a1, a2, a3];

    const equalBetFactory = await ethers.getContractFactory("EqualBetsToken");
    equalBetTokenContract = await equalBetFactory.deploy();

    const bankFactory = await ethers.getContractFactory("Bank");
    bankContract = await bankFactory.deploy(
      b1.address,
      b2.address,
      parseUnits("10", 18),
      b0.address,
      equalBetTokenContract.address
    );

    await equalBetTokenContract.transferOwnership(bankContract.address);
    await bankContract.setStartBlock(8);

    await bankContract.addToken(GAS_TOKEN_ADDRESS, 1000);
    await bankContract.setAllowedToken(GAS_TOKEN_ADDRESS, true);
    await bankContract.setPausedToken(GAS_TOKEN_ADDRESS, false);
    await bankContract.setLpTokenPerToken(GAS_TOKEN_ADDRESS, 10); // block 8
    const BankLPTokenOfGasAddress = await bankContract.getLpTokenAddress(
      bankContract.address,
      GAS_TOKEN_ADDRESS
    );
    contractBankLPTokenOfGasToken = await ethers.getContractAt(
      BankLPTokenArtifacts.abi,
      BankLPTokenOfGasAddress
    );
    await contractBankLPTokenOfGasToken
      .connect(b1)
      .approve(bankContract.address, parseUnits("100000"));
    await contractBankLPTokenOfGasToken
      .connect(b2)
      .approve(bankContract.address, parseUnits("100000"));
    await contractBankLPTokenOfGasToken
      .connect(b3)
      .approve(bankContract.address, parseUnits("100000"));
  });

  // it("deposit by 3 user walk through 400 block", async () => {
  //   await bankContract.addToken(GAS_TOKEN_ADDRESS, 1000);
  //   await bankContract.setAllowedToken(GAS_TOKEN_ADDRESS, true);
  //   await bankContract.setPausedToken(GAS_TOKEN_ADDRESS, false);
  //   await bankContract.setLpTokenPerToken(GAS_TOKEN_ADDRESS, 10); // block 8
  //   const BankLPTokenOfGasAddress = await bankContract.getLpTokenAddress(
  //     bankContract.address,
  //     GAS_TOKEN_ADDRESS
  //   );
  //   contractBankLPTokenOfGasToken = await ethers.getContractAt(
  //     BankLPTokenArtifacts.abi,
  //     BankLPTokenOfGasAddress
  //   );

  //   tx = await bankContract.connect(b1).deposit(0, parseUnits("10", 18), {
  //     value: parseUnits("10", 18),
  //   });
  //   console.log("After b1 first deposit");
  //   console.log("block number: ", tx.blockNumber);
  //   await userBalInfo(true, false, false);

  //   await skipBlock(99);
  //   console.log();

  //   tx = await bankContract.connect(b1).deposit(0, parseUnits("10", 18), {
  //     value: parseUnits("10", 18),
  //   });
  //   console.log("After skip 99 block and b1 second deposit");
  //   console.log("block number: ", tx.blockNumber);
  //   await userBalInfo(true, false, false);

  //   await skipBlock(99);
  //   console.log();

  //   tx = await bankContract
  //     .connect(b2)
  //     .deposit(0, parseUnits("10", 18), { value: parseUnits("10", 18) });
  //   console.log("After skip 99 block and b2 second deposit");
  //   console.log("block number: ", tx.blockNumber);
  //   await userBalInfo(true, true, false);

  //   await skipBlock(99);
  //   console.log();

  //   tx = await bankContract
  //     .connect(b3)
  //     .deposit(0, parseUnits("10", 18), { value: parseUnits("10", 18) });
  //   console.log("After skip 99 block and b3 second deposit");
  //   console.log("block number: ", tx.blockNumber);
  //   await userBalInfo(true, true, true);

  //   await skipBlock(100);
  //   console.log();
  //   console.log("After skip 100 block");
  //   await userBalInfo(true, true, true);

  //   async function userBalInfo(
  //     printB1: boolean,
  //     printB2: boolean,
  //     printB3: boolean
  //   ) {
  //     if (printB1) {
  //       console.log(
  //         "b1 eth balance: ",
  //         parseFloat((await provider.getBalance(b1.address)).toString()) / 1e18
  //       );
  //       console.log(
  //         "b1 EBET pending amount: ",
  //         parseInt((await bankContract.pendingEBet(0, b1.address)).toString()) /
  //           1e18
  //       );
  //       console.log(
  //         "b1 EBET balance: ",
  //         (await equalBetTokenContract.balanceOf(b1.address)) / 1e18
  //       );
  //       console.log(
  //         "b1 bankLPTokenOfGas amount: ",
  //         (await contractBankLPTokenOfGasToken.balanceOf(b1.address)) / 1e18
  //       );
  //     }
  //     console.log();
  //     if (printB2) {
  //       console.log(
  //         "b2 eth balance: ",
  //         parseFloat((await provider.getBalance(b2.address)).toString()) / 1e18
  //       );
  //       console.log(
  //         "b2 EBET pending amount: ",
  //         parseInt((await bankContract.pendingEBet(0, b2.address)).toString()) /
  //           1e18
  //       );
  //       console.log(
  //         "b2 EBET balance: ",
  //         (await equalBetTokenContract.balanceOf(b2.address)) / 1e18
  //       );
  //       console.log(
  //         "b2 bankLPTokenOfGas amount: ",
  //         (await contractBankLPTokenOfGasToken.balanceOf(b2.address)) / 1e18
  //       );
  //     }
  //     console.log();
  //     if (printB3) {
  //       console.log(
  //         "b3 eth balance: ",
  //         parseFloat((await provider.getBalance(b3.address)).toString()) / 1e18
  //       );
  //       console.log(
  //         "b3 EBET pending amount: ",
  //         parseInt((await bankContract.pendingEBet(0, b3.address)).toString()) /
  //           1e18
  //       );
  //       console.log(
  //         "b3 EBET balance: ",
  //         (await equalBetTokenContract.balanceOf(b3.address)) / 1e18
  //       );
  //       console.log(
  //         "b3 bankLPTokenOfGas amount: ",
  //         (await contractBankLPTokenOfGasToken.balanceOf(b3.address)) / 1e18
  //       );
  //     }
  //   }
  // });

  it("deposit and withdraw and claim reward by 3 user", async () => {
    tx = await bankContract.connect(b1).deposit(0, parseUnits("20", 18), {
      value: parseUnits("20", 18),
    });
    await skipBlock(99);

    tx = await bankContract.connect(b2).deposit(0, parseUnits("10", 18), {
      value: parseUnits("10", 18),
    });
    await skipBlock(99);

    tx = await bankContract.connect(b3).deposit(0, parseUnits("10", 18), {
      value: parseUnits("10", 18),
    });
    await skipBlock(99);

    tx = await bankContract.getTokenForFree(
      GAS_TOKEN_ADDRESS,
      b0.address,
      parseUnits("30", 18)
    );
    
    tx = await bankContract.connect(b2).claimReward(0, parseUnits("1333.3333333333333", 18))
    console.log();
    console.log("block number: ", tx.blockNumber);
    await userBalInfo(true, true, true);

    async function userBalInfo(
      printB1: boolean,
      printB2: boolean,
      printB3: boolean
    ) {
      if (printB1) {
        console.log(
          "b1 eth balance: ",
          parseFloat((await provider.getBalance(b1.address)).toString()) / 1e18
        );
        console.log(
          "b1 EBET pending amount: ",
          parseInt((await bankContract.pendingEBet(0, b1.address)).toString()) /
            1e18
        );
        console.log(
          "b1 EBET balance: ",
          (await equalBetTokenContract.balanceOf(b1.address)) / 1e18
        );
        console.log(
          "b1 bankLPTokenOfGas amount: ",
          (await contractBankLPTokenOfGasToken.balanceOf(b1.address)) / 1e18
        );
      }
      console.log();
      if (printB2) {
        console.log(
          "b2 eth balance: ",
          parseFloat((await provider.getBalance(b2.address)).toString()) / 1e18
        );
        console.log(
          "b2 EBET pending amount: ",
          parseInt((await bankContract.pendingEBet(0, b2.address)).toString()) /
            1e18
        );
        console.log(
          "b2 EBET balance: ",
          (await equalBetTokenContract.balanceOf(b2.address)) / 1e18
        );
        console.log(
          "b2 bankLPTokenOfGas amount: ",
          (await contractBankLPTokenOfGasToken.balanceOf(b2.address)) / 1e18
        );
      }
      console.log();
      if (printB3) {
        console.log(
          "b3 eth balance: ",
          parseFloat((await provider.getBalance(b3.address)).toString()) / 1e18
        );
        console.log(
          "b3 EBET pending amount: ",
          parseInt((await bankContract.pendingEBet(0, b3.address)).toString()) /
            1e18
        );
        console.log(
          "b3 EBET balance: ",
          (await equalBetTokenContract.balanceOf(b3.address)) / 1e18
        );
        console.log(
          "b3 bankLPTokenOfGas amount: ",
          (await contractBankLPTokenOfGasToken.balanceOf(b3.address)) / 1e18
        );
      }
    }
  });
  async function skipBlock(blocks: number) {
    for (let i = 0; i < blocks; i++) {
      await bankContract.setAllowedToken(GAS_TOKEN_ADDRESS, true);
    }
  }
});

// console.log(ethers.utils.keccak256(BankLPTokenArtifacts.bytecode));

// const BankLPTokenArtifacts = await ethers.getContractFactory("BankLPToken");
// console.log(ethers.utils.keccak256(BankLPTokenArtifacts.bytecode));
// const BankLPTokenArtifacts = await ethers.getContractFactory("BankLPToken");
// console.log(ethers.utils.keccak256(BankLPTokenArtifacts.bytecode));

// it("deposit and withdraw GasToken", async () => {
//   await bankContract.addToken(GAS_TOKEN_ADDRESS);
//   await bankContract.setAllowedToken(GAS_TOKEN_ADDRESS, true);
//   await bankContract.setPausedToken(GAS_TOKEN_ADDRESS, false);
//   await bankContract.setLpTokenPerToken(GAS_TOKEN_ADDRESS, 1000);
//   const BankLPTokenOfGasAddress = await bankContract.getLpTokenAddress(
//     bankContract.address,
//     GAS_TOKEN_ADDRESS
//   );
//   contractBankLPTokenOfGasToken = await ethers.getContractAt(
//     BankLPTokenArtifacts.abi,
//     BankLPTokenOfGasAddress
//   );
//   console.log("Before deposit");
//   console.log(
//     "b0 balance eth",
//     parseFloat((await provider.getBalance(b0.address)).toString()) / 1e18
//   );
//   console.log(
//     "b0 LP balance",
//     (await contractBankLPTokenOfGasToken.balanceOf(b0.address)) / 1e18
//   );
//   console.log(
//     "b1 balance eth",
//     parseFloat((await provider.getBalance(b1.address)).toString()) / 1e18
//   );
//   console.log(
//     "b1 LP balance",
//     (await contractBankLPTokenOfGasToken.balanceOf(b1.address)) / 1e18
//   );

//   await bankContract
//     .connect(b0)
//     .deposit(GAS_TOKEN_ADDRESS, b0.address, parseUnits("10", 18), {
//       value: parseUnits("10", 18),
//     });
//   await bankContract
//     .connect(b1)
//     .deposit(GAS_TOKEN_ADDRESS, b1.address, parseUnits("5", 18), {
//       value: parseUnits("5", 18),
//     });

//   console.log();
//   console.log("After deposit b0, b1");

//   console.log(
//     "b0 balance eth",
//     parseFloat((await provider.getBalance(b0.address)).toString()) / 1e18
//   );
//   console.log(
//     "b0 LP balance",
//     (await contractBankLPTokenOfGasToken.balanceOf(b0.address)) / 1e18
//   );
//   console.log(
//     "b1 balance eth",
//     parseFloat((await provider.getBalance(b1.address)).toString()) / 1e18
//   );
//   console.log(
//     "b1 LP balance",
//     (await contractBankLPTokenOfGasToken.balanceOf(b1.address)) / 1e18
//   );

//   await bankContract.getTokenForFree(
//     GAS_TOKEN_ADDRESS,
//     b2.address,
//     parseUnits("5", 18)
//   );

//   await contractBankLPTokenOfGasToken
//     .connect(b0)
//     .approve(bankContract.address, parseUnits("10000", 18));
//   await bankContract
//     .connect(b0)
//     .withdraw(GAS_TOKEN_ADDRESS, b0.address, parseUnits("10000", 18));

//   console.log();
//   console.log("After b0 withdraw ");
//   console.log(
//     "b0 balance eth",
//     parseFloat((await provider.getBalance(b0.address)).toString()) / 1e18
//   );
//   console.log(
//     "b0 LP balance",
//     (await contractBankLPTokenOfGasToken.balanceOf(b0.address)) / 1e18
//   );
//   console.log(
//     "b1 balance eth",
//     parseFloat((await provider.getBalance(b1.address)).toString()) / 1e18
//   );
//   console.log(
//     "b1 LP balance",
//     (await contractBankLPTokenOfGasToken.balanceOf(b1.address)) / 1e18
//   );

//   await contractBankLPTokenOfGasToken.connect(b1).approve(
//     bankContract.address,
//     parseUnits("10000", 18)
//   );
//   await bankContract
//     .connect(b1)
//     .withdraw(
//       GAS_TOKEN_ADDRESS,
//       b1.address,
//       parseUnits("5000", 18)
//     );

//   console.log();
//   console.log("After b1 withdraw ");
//   console.log(
//     "b0 balance eth",
//     parseFloat((await provider.getBalance(b0.address)).toString()) / 1e18
//   );
//   console.log(
//     "b0 LP balance",
//     (await contractBankLPTokenOfGasToken.balanceOf(b0.address)) / 1e18
//   );
//   console.log(
//     "b1 balance eth",
//     parseFloat((await provider.getBalance(b1.address)).toString()) / 1e18
//   );
//   console.log(
//     "b1 LP balance",
//     (await contractBankLPTokenOfGasToken.balanceOf(b1.address)) / 1e18
//   );
// });
