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
require('dotenv').config()

const owner_key = process.env.PRIV_KEY
console.log(owner_key ? true : false)

// const provider = new ethers.providers.JsonRpcProvider(GOERLI_API)

// function getContractWithSignKey(privKey, abiAndAddress) {
//     const wallet = new ethers.Wallet(privKey, provider)
//     const contract = new ethers.Contract(abiAndAddress.contractAddress, abiAndAddress.contractABI, provider)
//     return contract.connect(wallet)
// }
