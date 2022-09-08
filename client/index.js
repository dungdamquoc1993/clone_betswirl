//set up require 
// addToken
// setAllowedToken
// setPausedToken
// setBalanceRisk
// setTokenVRFSubId
// setTokenMinBetAmount
// setHouseEdgeSplit

const { ethers } = require("ethers");
const { parseUnits } = require("ethers/lib/utils");
const {GOERLI_API, BankConfig, RouletteConfig } = require('./utils/constant')
const {PRIV_KEY} = require("./privKey")


console.log(PRIV_KEY)

// const provider = new ethers.providers.JsonRpcProvider(GOERLI_API)

// function getContractWithSignKey(privKey, abiAndAddress) {
//     const wallet = new ethers.Wallet(privKey, provider)
//     const contract = new ethers.Contract(abiAndAddress.contractAddress, abiAndAddress.contractABI, provider)
//     return contract.connect(wallet)
// }
