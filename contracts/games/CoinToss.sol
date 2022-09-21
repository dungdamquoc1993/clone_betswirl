
////// SPDX-License-Identifier-FLATTEN-SUPPRESS-WARNING: MIT
// OpenZeppelin Contracts (last updated v4.7.0) (utils/Address.sol)

pragma solidity ^0.8.1;
// SPDX-License-Identifier: UNLICENSED
import "./Game.sol";

contract CoinToss is Game {
    struct FullCoinTossBet {
        Bet bet;
        CoinTossBet coinTossBet;
    }

    struct CoinTossBet {
        bool face;
        bool rolled;
    }

    mapping(uint256 => CoinTossBet) public coinTossBets;

    event PlaceBet(
        uint256 id,
        address indexed user,
        address indexed token,
        uint256 amount,
        uint256 vrfCost,
        bool face
    );

    event Roll(
        uint256 id,
        address indexed user,
        address indexed token,
        uint256 amount,
        bool face,
        bool rolled,
        uint256 payout
    );

    constructor(
        address bankAddress,
        address chainlinkCoordinatorAddress,
        address LINK_ETH_feedAddress
    ) Game(bankAddress, chainlinkCoordinatorAddress, 1, LINK_ETH_feedAddress) {}

    function _getPayout(uint256 betAmount) private pure returns (uint256) {
        return betAmount * 2;
    }

    function wager(
        bool face,
        address token,
        uint256 tokenAmount
    ) external payable whenNotPaused {
        Bet memory bet = _newBet(
            token,
            tokenAmount,
            _getPayout(10000)
        );

        coinTossBets[bet.id].face = face;

        emit PlaceBet(bet.id, bet.user, bet.token, bet.amount, bet.vrfCost, face);
    }

    function fulfillRandomWords(uint256 id, uint256[] memory randomWords)
        internal
        override
    {
        CoinTossBet storage coinTossBet = coinTossBets[id];
        Bet storage bet = bets[id];

        uint256 rolled = randomWords[0] % 2;

        bool[2] memory coinSides = [false, true];
        bool rolledCoinSide = coinSides[rolled];
        coinTossBet.rolled = rolledCoinSide;
        uint256 payout = _resolveBet(
            bet,
            rolledCoinSide == coinTossBet.face,
            _getPayout(bet.amount)
        );

        emit Roll(
            bet.id,
            bet.user,
            bet.token,
            bet.amount,
            coinTossBet.face,
            rolledCoinSide,
            payout
        );
    }

    function getLastUserBets(address user, uint256 dataLength)
        external
        view
        returns (FullCoinTossBet[] memory)
    {
        Bet[] memory lastBets = _getLastUserBets(user, dataLength);
        FullCoinTossBet[] memory lastCoinTossBets = new FullCoinTossBet[](
            lastBets.length
        );
        for (uint256 i; i < lastBets.length; i++) {
            lastCoinTossBets[i] = FullCoinTossBet(
                lastBets[i],
                coinTossBets[lastBets[i].id]
            );
        }
        return lastCoinTossBets;
    }
}