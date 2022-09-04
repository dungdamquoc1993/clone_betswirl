import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { Contract, ContractFactory } from "ethers";
import { parseUnits } from "ethers/lib/utils";
import { ethers } from "hardhat";

const oracleResponse = ethers.utils.hexZeroPad(ethers.utils.hexlify(0), 32)

describe("Casino", async () => {
  beforeEach( async () => {
    const [b0, b1, b2, b3] = await ethers.getSigners()
    const factory = await ethers.getContractFactory("Bank");
    const bankContract = await factory.deploy(b0.address, b1.address)
    await bankContract.deployed();
    await bankContract.connect(b1).withdraw("0xd73812a2e5d57bbeA5Ef7A142D78DA1c383A345f", 10000)

  })
  it("Accesscontroll", async () => {

  });
  //   it("Not allow you to propose a zero wei bet", async () => {
  //     let f = await ethers.getContractFactory("Casino")
  //     let c = await f.deploy()

  //     try {
  //       let tx = await c.proposeBet(hashA)
  //       await tx.wait()
  //       // If we get here, it's a fail
  //       expect("this").to.equal("fail")
  //     } catch(err) {
  //       expect(interpretErr(err)).to
  //         .match(/you need to actually bet something/)

  //     }
  //   })   // it "Not allow you to bet zero wei"

  //   it("Not allow you to accept a bet that doesn't exist", async () => {
  //     let f = await ethers.getContractFactory("Casino")
  //     let c = await f.deploy()

  //     try {
  //       let tx = await c.acceptBet(hashA, valBwin, {value: 10})
  //       await tx.wait()
  //       expect("this").to.equal("fail")
  //     } catch (err) {
  //         expect(interpretErr(err)).to
  //           .match(/Nobody made that bet/)
  //     }
  //   })   // it "Not allow you to accept a bet that doesn't exist"

  //   it("Allow you to propose and accept bets", async () => {
  //     let f = await ethers.getContractFactory("Casino")
  //     let c = await f.deploy()

  //     let tx = await c.proposeBet(2, {value: 10})
  //     let rcpt = await tx.wait()
  //     expect(rcpt.events[0].event).to.equal("BetProposed")
  //     tx = await c.acceptBet(2, valBwin, {value: 10})
  //     rcpt = await tx.wait()
  //     expect(rcpt.events[0].event).to.equal("BetAccepted")
  //   })   // it "Allow you to accept a bet"

  //   it("Not allow you to accept an already accepted bet", async () => {
  //     let f = await ethers.getContractFactory("Casino")
  //     let c = await f.deploy()

  //     let tx = await c.proposeBet(hashA, {value: 10})
  //     let rcpt = await tx.wait()
  //     expect(rcpt.events[0].event).to.equal("BetProposed")
  //     tx = await c.acceptBet(hashA, valBwin, {value: 10})
  //     rcpt = await tx.wait()
  //     expect(rcpt.events[0].event).to.equal("BetAccepted")
  //     try {
  //       tx = await c.acceptBet(hashA, valBwin, {value: 10})
  //       rcpt = await tx.wait()
  //       expect("this").to.equal("fail")
  //     } catch (err) {
  //         expect(interpretErr(err)).to
  //           .match(/Bet has already been accepted/)
  //     }
  //   })   // it "Not allow you to accept an already accepted bet"

  //   it("Not allow you to accept with the wrong amount", async () => {
  //     let f = await ethers.getContractFactory("Casino")
  //     let c = await f.deploy()

  //     let tx = await c.proposeBet(hashA, {value: 10})
  //     let rcpt = await tx.wait()
  //     expect(rcpt.events[0].event).to.equal("BetProposed")
  //     try {
  //       tx = await c.acceptBet(hashA, valBwin, {value: 11})
  //       rcpt = await tx.wait()
  //       expect("this").to.equal("fail")
  //     } catch (err) {
  //         expect(interpretErr(err)).to
  //           .match(/Need to bet the same amount as sideA/)
  //     }
  //   })   // it "Not allow you to accept with the wrong amount"

  //   it("Not allow you to reveal with wrong value", async () => {
  //     let f = await ethers.getContractFactory("Casino")
  //     let c = await f.deploy()

  //     let tx = await c.proposeBet(hashA, {value: 10})
  //     let rcpt = await tx.wait()
  //     expect(rcpt.events[0].event).to.equal("BetProposed")
  //     tx = await c.acceptBet(hashA, valBwin, {value: 10})
  //     rcpt = await tx.wait()
  //     expect(rcpt.events[0].event).to.equal("BetAccepted")
  //     try {
  //       tx = await c.reveal(valBwin)
  //       rcpt = await tx.wait()
  //       expect("this").to.equal("fail")
  //     } catch (err) {
  //         expect(interpretErr(err)).to
  //           .match(/Not a bet you placed or wrong value/)
  //     }
  //   })   // it "Not allow you to accept an already accepted bet"

  //   it("Not allow you to reveal before bet is accepted", async () => {
  //     let f = await ethers.getContractFactory("Casino")
  //     let c = await f.deploy()

  //     let tx = await c.proposeBet(hashA, {value: 10})
  //     let rcpt = await tx.wait()
  //     expect(rcpt.events[0].event).to.equal("BetProposed")
  //     try {
  //       tx = await c.reveal(valA)
  //       rcpt = await tx.wait()
  //       expect("this").to.equal("fail")
  //     } catch (err) {
  //         expect(interpretErr(err)).to
  //           .match(/Bet has not been accepted yet/)
  //     }
  //   })   // it "Not allow you to reveal before bet is accepted"

  // it("Work all the way through (B wins)", async () => {
  //   let signer = await ethers.getSigners();
  //   let f = await ethers.getContractFactory("Casino");
  //   let cA = await f.deploy();
  //   let cB = cA.connect(signer[1]);
  //   const hashA = ethers.utils.keccak256(randomA)

  //   let tx = await cA.proposeBet(hashA, {value: 1e10})
  //   let rcpt = await tx.wait()
  //   expect(rcpt.events[0].event).to.equal("BetProposed")

  //   tx = await cB.acceptBet(hashA, valBwin, {value: 1e10})
  //   rcpt = await tx.wait()
  //   expect(rcpt.events[0].event).to.equal("BetAccepted")

  //   let preBalanceB = await ethers.provider.getBalance(signer[1].address);
  //   tx = await cA.reveal(randomA)
  //   rcpt = await tx.wait()
  //   expect(rcpt.events[0].event).to.equal("BetSettled")
  //   let postBalanceB = await ethers.provider.getBalance(signer[1].address)
  //   let deltaB = postBalanceB.sub(preBalanceB)
  //   console.log(deltaB)
  //   expect(deltaB.toNumber()).to.equal(2e10)
  // }); // it "Work all the way through (B wins)"

  // it("Work all the way through (A wins)", async () => {
  //   let signer = await ethers.getSigners()
  //   let f = await ethers.getContractFactory("Casino")
  //   let cA = await f.deploy()
  //   let cB = cA.connect(signer[1])

  //   let tx = await cA.proposeBet(hashA, {value: 1e10})
  //   let rcpt = await tx.wait()
  //   expect(rcpt.events[0].event).to.equal("BetProposed")

  //   tx = await cB.acceptBet(hashA, valBlose, {value: 1e10})
  //   rcpt = await tx.wait()
  //   expect(rcpt.events[0].event).to.equal("BetAccepted")

  //   // A sends the transaction, so the change due to the
  //   // bet will only be clearly visible in B
  //   let preBalanceB = await ethers.provider.getBalance(signer[1].address)
  //   tx = await cA.reveal(valA)
  //   rcpt = await tx.wait()
  //   expect(rcpt.events[0].event).to.equal("BetSettled")
  //   let postBalanceB = await ethers.provider.getBalance(signer[1].address)
  //   let deltaB = postBalanceB.sub(preBalanceB)
  //   expect(deltaB.toNumber()).to.equal(0)
  // })   // it "Work all the way through (A wins)"
}); // describe("Casino")
