// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.1;

interface IVault {
    struct GameCreate {
        bytes32 gameId;
        uint256 startTime;
        string homeTeam;
        string awayTeam;
    }

    struct GameResolve {
        bytes32 gameId;
        uint8 homeScore;
        uint8 awayScore;
        uint8 statusId;
    }

    struct Token {
        bool allowed;
        uint256 minBetAmount;
        uint256 maxBetAmount;
    }

    // uint256 public _tokensCount;
    function _tokensCount() external view returns (uint256);

    // mapping(uint256 => address) public _tokensList;
    function _tokensList(uint256 index) external view returns (address);

    // mapping(address => Token) public tokens;
    function tokens(address token) external view returns (Token memory);

    // function increaseTokenPendingCount(address _token) external;

    // function decreaseTokenPendingCount(address _token) external;

    function addTokenFee(address _token, uint256 _fee) external;

    // mapping(bytes32 => GameCreate) public gamesCreate;
    function getGameCreate(bytes32 gameId)
        external
        view
        returns (GameCreate memory);

    // bytes32[] public gameCreateIds;
    function gameCreateIds(uint256 index) external view returns (bytes32);

    // mapping(bytes32 => GameResolve) public gamesResolve;
    function getGameResolve(bytes32 gameId)
        external
        view
        returns (GameResolve memory);

    // bytes32[] public gameResolveIds;
    function gameResolveIds(uint256 index) external view returns (bytes32);

    // bytes32 public jobId;
    function jobId() external view returns (bytes32);

    // uint256 public fee;
    function fee() external view returns (uint256);

    function isAllowedToken(address tokenAddress) external view returns (bool);

    function payout(
        address user,
        address token,
        uint256 amount
    ) external payable;

    function cashIn(
        address _token,
        uint256 amount
    ) external payable;
}
