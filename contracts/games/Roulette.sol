// SPDX-License-Identifier: UNLICENSED
import "./Game.sol";
import "hardhat/console.sol";

pragma solidity ^0.8.1;

/// @title EqualBet's Roulette game
/// @author Neo
contract Roulette is Game {
    
    struct FullRouletteBet {
        Bet bet;
        RouletteBet rouletteBet;
    }
    
    struct RouletteBet {
        uint40 numbers;
        uint8 rolled;
    }

    uint8 private constant MODULO = 37;
    uint256 private constant POPCNT_MULT =
        0x0000000000002000000000100000000008000000000400000000020000000001;
    uint256 private constant POPCNT_MASK =
        0x0001041041041041041041041041041041041041041041041041041041041041;
    uint256 private constant POPCNT_MODULO = 0x3F;

    mapping(uint256 => RouletteBet) public rouletteBets;

    event PlaceBet(
        uint256 id,
        address indexed user,
        address indexed token,
        uint40 numbers
    );

    event Roll(
        uint256 id,
        address indexed user,
        address indexed token,
        uint256 amount,
        uint40 numbers,
        uint8 rolled,
        uint256 payout
    );

    error NumbersNotInRange();

    constructor(
        address bankAddress,
        address chainlinkCoordinatorAddress,
        address LINK_ETH_feedAddress
    ) Game(bankAddress, chainlinkCoordinatorAddress, 1, LINK_ETH_feedAddress) {}

    function _getPayout(uint256 betAmount, uint40 numbers)
        private
        pure
        returns (uint256)
    {
        return
            (betAmount * MODULO) /
            (((numbers * POPCNT_MULT) & POPCNT_MASK) % POPCNT_MODULO);
    }

    function wager(
        uint40 numbers,
        address token,
        uint256 tokenAmount
    ) external payable whenNotPaused {
        if (numbers == 0 || numbers >= 2**MODULO - 1) {
            revert NumbersNotInRange();
        }

        Bet memory bet = _newBet(
            token,
            tokenAmount,
            _getPayout(10000, numbers)
        );

        rouletteBets[bet.id].numbers = numbers;

        emit PlaceBet(bet.id, bet.user, bet.token, numbers);
    }

    function fulfillRandomWords(uint256 id, uint256[] memory randomWords)
        internal
        override
    {
        RouletteBet storage rouletteBet = rouletteBets[id];
        Bet storage bet = bets[id];

        uint8 rolled = uint8(randomWords[0] % MODULO);
        rouletteBet.rolled = rolled;
        uint256 payout = _resolveBet(
            bet,
            (2**rolled) & rouletteBet.numbers != 0,
            _getPayout(bet.amount, rouletteBet.numbers)
        );

        emit Roll(
            bet.id,
            bet.user,
            bet.token,
            bet.amount,
            rouletteBet.numbers,
            rolled,
            payout
        );
    }

    function getLastUserBets(address user, uint256 dataLength)
        external
        view
        returns (FullRouletteBet[] memory)
    {
        Bet[] memory lastBets = _getLastUserBets(user, dataLength);
        FullRouletteBet[] memory lastRouletteBets = new FullRouletteBet[](
            lastBets.length
        );
        for (uint256 i; i < lastBets.length; i++) {
            lastRouletteBets[i] = FullRouletteBet(
                lastBets[i],
                rouletteBets[lastBets[i].id]
            );
        }
        return lastRouletteBets;
    }
}
