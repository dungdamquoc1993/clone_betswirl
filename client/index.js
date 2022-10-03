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
const { GOERLI_API, BankConfig, RouletteConfig, GAME_ROLE } = require('./utils/constant')
const { PRIV_KEY0 } = require("./privKey")

const provider = new ethers.providers.JsonRpcProvider(GOERLI_API)

function getContractWithSignKey(privKey, abiAndAddress) {
    const wallet = new ethers.Wallet(privKey, provider)
    const contract = new ethers.Contract(abiAndAddress.contractAddress, abiAndAddress.contractABI, provider)
    return contract.connect(wallet)
}

const addToken = async (tokenAddress) => {
    const bankContract = getContractWithSignKey(PRIV_KEY0, BankConfig)
    await bankContract.addToken(tokenAddress);
}

const setAllowedToken = async (tokenAddress, allowed) => {
    const bankContract = getContractWithSignKey(PRIV_KEY0, BankConfig)
    await bankContract.setAllowedToken(
        tokenAddress,
        allowed // true
    );
}
const setPausedToken = async (tokenAddress, isPaused) => {
    const bankContract = getContractWithSignKey(PRIV_KEY0, BankConfig)
    await bankContract.setPausedToken(
        tokenAddress,
        isPaused // false
    );
}
const setBalanceRisk = async (tokenAddress, balanceRiskRate) => {
    const bankContract = getContractWithSignKey(PRIV_KEY0, BankConfig)
    await bankContract.setBalanceRisk(
        tokenAddress,
        balanceRiskRate // 1000
    );
}
const setTokenMinBetAmount = async (tokenAddress, minBetAmount) => {
    const bankContract = getContractWithSignKey(PRIV_KEY0, BankConfig)
    await bankContract.setTokenMinBetAmount(
        tokenAddress,
        minBetAmount // parseUnits("0.1", 18)
    );
}
const setMinPartnerTransferAmount = async (tokenAddress, minPartnerTransferAmount) => {
    const bankContract = getContractWithSignKey(PRIV_KEY0, BankConfig)
    await bankContract.setMinPartnerTransferAmount(
        tokenAddress,
        minPartnerTransferAmount // parseUnits("1", 18)
    )
}
const setHouseEdgeSplit = async (tokenAddress, bank, dividend, partner, treasury, team) => {
    const bankContract = getContractWithSignKey(PRIV_KEY0, BankConfig)
    await bankContract.setHouseEdgeSplit(
        tokenAddress,
        bank, // 2000
        dividend, // 2000
        partner, // 2000
        treasury, // 2000
        team, // 2000
    );
}
const setTokenVRFSubId = async (tokenAddress, vrfSubId) => {
    const bankContract = getContractWithSignKey(PRIV_KEY0, BankConfig)
    await bankContract.setTokenVRFSubId(
        tokenAddress,
        vrfSubId // 1220
    )
}
const deposit = async (tokenAddress, amount) => {
    const bankContract = getContractWithSignKey(PRIV_KEY0, BankConfig)
    const deposit = await bankContract.deposit(tokenAddress, parseUnits(amount.toString(), 18), { value: parseUnits(amount.toString, 18) })
    await deposit.wait()
}
const withdraw = async (tokenAddress, amount) => {
    const bankContract = getContractWithSignKey(PRIV_KEY0, BankConfig)
    const withdraw = await bankContract.withdraw(tokenAddress, parseUnits(amount.toString(), 18))
    await withdraw.wait()
}
const getBalance = async (tokenAddress) => {
    const bankContract = getContractWithSignKey(PRIV_KEY0, BankConfig)
    return (await bankContract.getBalance(tokenAddress)) / 1e18
}

const setGameRole = async (gameAddress) => {
    const bankContract = getContractWithSignKey(PRIV_KEY0, BankConfig)
    await bankContract.grantRole(GAME_ROLE, gameAddress)
}
const setGameHouseEdge = async (tokenAddress, houseEdgeRate) => {
    const rouletteContract = getContractWithSignKey(PRIV_KEY0, RouletteConfig)
    await rouletteContract.setHouseEdge(tokenAddress, houseEdgeRate)
}
const setGameVRFCallbackGasLimit = async (tokenAddress, vrfCallbackGasLimit) => {
    const rouletteContract = getContractWithSignKey(PRIV_KEY0, RouletteConfig)
    await rouletteContract.setVRFCallbackGasLimit(tokenAddress, vrfCallbackGasLimit)
}
const setGameChainLinkConfig = async (requestConfirmations, keyHash) => {
    const rouletteContract = getContractWithSignKey(PRIV_KEY0, RouletteConfig)
    await rouletteContract.setChainlinkConfig(requestConfirmations, keyHash)
}

async function setUp(
    tokenAddress,
    allowed,
    isPaused,
    balanceRiskRate,
    minBetAmount,
    minPartnerTransferAmount,
    bank, dividend, partner, treasury, team,
    vrfSubId) {
    await addToken(tokenAddress)
    await setAllowedToken(tokenAddress, allowed)
    await setPausedToken(tokenAddress, isPaused)
    await setBalanceRisk(tokenAddress, balanceRiskRate)
    await setTokenMinBetAmount(tokenAddress, minBetAmount)
    await setMinPartnerTransferAmount(tokenAddress, minPartnerTransferAmount)
    await setHouseEdgeSplit(tokenAddress, bank, dividend, partner, treasury, team)
    await setTokenVRFSubId(tokenAddress, vrfSubId)
}

async function main() {
    const gameContract = getContractWithSignKey(PRIV_KEY0, RouletteConfig)
    const bankContract = getContractWithSignKey(PRIV_KEY0, BankConfig)
    const tokenAddress = "0x0000000000000000000000000000000000000000"
    const maxBetAmount = await bankContract.getMaxBetAmount(tokenAddress, 185000)
    const minBetAmount = await bankContract.getMinBetAmount(tokenAddress)
    const wager = await gameContract.wager(36, tokenAddress, parseUnits("0.001025436969223264", 18), {value: parseUnits("0.01025436969223264", 18)})
    await wager.wait()
    console.log(await gameContract.getLastUserBets("0x59772e95C77Dd1575fB916DACDFabEF688cc7971", 4))
}

main()