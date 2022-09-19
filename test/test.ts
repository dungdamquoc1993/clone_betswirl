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
  let betContract: Contract;
  beforeEach(async () => {
    const [a0, a1, a2, a3] = await ethers.getSigners();
    [b0, b1, b2, b3] = [a0, a1, a2, a3];

    const equalBetFactory = await ethers.getContractFactory("EqualBetsToken");
    equalBetTokenContract = await equalBetFactory.deploy();

    const betFactory = await ethers.getContractFactory("EqualBetsToken");
    betContract = await betFactory.deploy();

    const bankFactory = await ethers.getContractFactory("Bank");
    bankContract = await bankFactory.deploy(
      parseUnits("10", 18),
      b0.address,
      equalBetTokenContract.address,
      8
    );

    await equalBetTokenContract.transferOwnership(bankContract.address);

    await bankContract.addToken(GAS_TOKEN_ADDRESS, 1000, parseUnits("10", 18));
    await bankContract.setAllowedToken(GAS_TOKEN_ADDRESS, true);
    await bankContract.setPausedToken(GAS_TOKEN_ADDRESS, false);
    const BankLPTokenOfGasAddress = await bankContract.getLpTokenAddress(
      bankContract.address,
      GAS_TOKEN_ADDRESS
    );
    contractBankLPTokenOfGasToken = await ethers.getContractAt(
      BankLPTokenArtifacts.abi,
      BankLPTokenOfGasAddress
    );
    const BankLPTokenOfEbetAddress = await bankContract.getLpTokenAddress(
      bankContract.address,
      equalBetTokenContract.address
    );
    contractBankLPTokenOfERC20 = await ethers.getContractAt(
      BankLPTokenArtifacts.abi,
      BankLPTokenOfEbetAddress
    );
  });

  it("test deposit and withdraw check LP balacnce", async () => {
    await bankContract.addToken(
      equalBetTokenContract.address,
      0,
      parseUnits("1", 18)
    );
    await equalBetTokenContract.mint(b1.address, parseUnits("100", 18));
    await equalBetTokenContract.mint(b2.address, parseUnits("100", 18));
    await equalBetTokenContract.mint(b3.address, parseUnits("100", 18));
    await equalBetTokenContract
      .connect(b1)
      .approve(bankContract.address, parseUnits("100", 18));
    await equalBetTokenContract
      .connect(b2)
      .approve(bankContract.address, parseUnits("100", 18));
    await equalBetTokenContract
      .connect(b3)
      .approve(bankContract.address, parseUnits("100", 18));

    await bankContract.connect(b1).deposit(1, parseUnits("10", 18));
    await bankContract.connect(b2).deposit(1, parseUnits("10", 18));
    await bankContract.connect(b3).deposit(1, parseUnits("10", 18));
    
    await skipBlock(100)
    
    await contractBankLPTokenOfERC20.connect(b1).approve(bankContract.address, parseUnits("100", 18))
    await contractBankLPTokenOfERC20.connect(b2).approve(bankContract.address, parseUnits("100", 18))
    await contractBankLPTokenOfERC20.connect(b3).approve(bankContract.address, parseUnits("100", 18))
    
    await bankContract.connect(b1).withdraw(1, parseUnits("10", 18))
    await bankContract.connect(b2).withdraw(1, parseUnits("10", 18))
    await bankContract.connect(b3).withdraw(1, parseUnits("10", 18))


    await showUser("b1", b1.address);
    console.log()
    await showUser("b2", b2.address);
    console.log()
    await showUser("b3", b3.address);
    console.log()
    console.log(
      (await equalBetTokenContract.balanceOf(bankContract.address)) / 1e18
    );

    async function showUser(userName: string, userAddress: string) {
      console.log(
        `${userName}, eth balance: `,
        parseFloat((await provider.getBalance(userAddress)).toString()) / 1e18
      );
      console.log(
        `${userName}, EBet balance: `,
        parseFloat(
          (await equalBetTokenContract.balanceOf(userAddress)).toString()
        ) / 1e18
      );
      console.log(
        `${userName}, bank LP Token amount: `,
        (await contractBankLPTokenOfERC20.balanceOf(userAddress)) / 1e18
      );
    }
    async function skipBlock(blocks: number) {
      for (let i = 0; i < blocks; i++) {
        await bankContract.setAllowedToken(GAS_TOKEN_ADDRESS, true);
      }
    }
  });
});
