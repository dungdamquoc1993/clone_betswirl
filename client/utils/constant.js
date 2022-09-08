
const BankJson = require('./Bank.json')
const Roulette = require('./Roulette.json')
// bank address 0x9C56f9CE846C1cCa0621F483279b294FB39A3389
// roulette address 0xB89364e6853C8EF59160E4B4458b65224640CCAa
const PRIV_KEY = "232f567845d6c965ba1212522ca590cf0bf7473df0b02f67d227be7ab91b8ad2"

const BankConfig = {
    contractABI: BankJson.abi,
    contractAddress: '0x9C56f9CE846C1cCa0621F483279b294FB39A3389'
}

const RouletteConfig = {
    contractABI: Roulette.abi,
    contractAddress: '0xB89364e6853C8EF59160E4B4458b65224640CCAa'
}

const GOERLI_API = 'https://goerli.infura.io/v3/8bf322110b8c4fbf87055c7fd3981adf'

module.exports = {
    GOERLI_API, BankConfig, RouletteConfig, PRIV_KEY
}
