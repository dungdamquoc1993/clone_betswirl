// SPDX-License-Identifier: UNLICENSED
import "@chainlink/contracts/src/v0.8/ChainlinkClient.sol";
import "../abstract/AccessControlEnumerable.sol";
import "../library/SafeERC20.sol";
import "../interface/IERC20.sol";
import "./enums.sol";
import "hardhat/console.sol";
import "../openzepplin/Ownable.sol";
import "../openzepplin/Pausable.sol";

pragma solidity ^0.8.1;

contract Vault is ChainlinkClient, AccessControlEnumerable, Ownable, Pausable {
    using Chainlink for Chainlink.Request;
    using SafeERC20 for IERC20;

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
        uint256 pendingCount;
        uint256 minBetAmount;
        uint256 maxBetAmount;
        uint256 fee;
    }

    uint256 public _tokensCount;

    mapping(uint256 => address) public _tokensList;

    mapping(address => Token) public tokens;

    mapping(bytes32 => GameCreate) public gamesCreate;

    bytes32[] public gameCreateIds;

    mapping(bytes32 => GameResolve) public gamesResolve;

    bytes32[] public gameResolveIds;

    bytes32 public jobId;
    uint256 public fee;
    bytes32 public constant GAME_ROLE = keccak256("GAME_ROLE");

    event NewOverUnderBet();
    event AcceptOverUnderBet();
    event AddToken(address token);
    event SetTokenMinBetAmount(address token, uint256 tokenMinBetAmount);
    event SetTokenMaxBetAmount(address token, uint256 tokenMaxBetAmount);
    event CashIn(address token, uint256 betAmount);

    error ForbiddenToken();
    error UnderMinBetAmount(uint256 minBetAmount);
    error TokenExists();

    constructor(
        address _link,
        address _oracle,
        bytes32 _jobId,
        uint256 _fee
    ) {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        setChainlinkToken(_link);
        setChainlinkOracle(_oracle);
        jobId = _jobId;
        fee = _fee;
    }

    function pause() external onlyOwner {
        if (paused()) {
            _unpause();
        } else {
            _pause();
        }
    }

    function _safeTransfer(
        address user,
        address token,
        uint256 amount
    ) private {
        bool isGasToken = token == address(0);
        if (isGasToken) {
            payable(user).transfer(amount);
        } else {
            IERC20(token).safeTransfer(user, amount);
        }
    }

    function addToken(address token) public {
        if (_tokensCount != 0) {
            for (uint8 i; i < _tokensCount; i++) {
                if (_tokensList[i] == token) {
                    revert TokenExists();
                }
            }
        }
        _tokensList[_tokensCount] = token;
        _tokensCount += 1;
        tokens[token].allowed = true;
        emit AddToken(token);
    }

    // function increaseTokenPendingCount(address _token)
    //     external
    //     onlyRole(GAME_ROLE)
    // {
    //     Token storage token = tokens[_token];
    //     token.pendingCount++;
    // }

    // function decreaseTokenPendingCount(address _token)
    //     external
    //     onlyRole(GAME_ROLE)
    // {
    //     Token storage token = tokens[_token];
    //     token.pendingCount--;
    // }

    function setOracleFee(uint256 _fee) public onlyRole(DEFAULT_ADMIN_ROLE) {
        fee = _fee;
    }

    function setOracleJobId(bytes32 _jobId)
        public
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        jobId = _jobId;
    }

    function setTokenMinBetAmount(address token, uint256 tokenMinBetAmount)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        tokens[token].minBetAmount = tokenMinBetAmount;
        emit SetTokenMinBetAmount(token, tokenMinBetAmount);
    }

    function setTokenMaxBetAmount(address token, uint256 tokenMaxBetAmount)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        tokens[token].maxBetAmount = tokenMaxBetAmount;
        emit SetTokenMaxBetAmount(token, tokenMaxBetAmount);
    }

    function getBalance(address token) public view returns (uint256) {
        uint256 tokenFee = tokens[token].fee;
        uint256 balance;
        bool isGasToken = token == address(0);
        if (isGasToken) {
            balance = address(this).balance - tokenFee;
        } else {
            balance = IERC20(token).balanceOf(address(this)) - tokenFee;
        }
        return balance;
    }

    function isAllowedToken(address tokenAddress) public view returns (bool) {
        Token memory token = tokens[tokenAddress];
        return token.allowed == true;
    }

    function getGameCreate(bytes32 gameId)
        public
        view
        returns (GameCreate memory)
    {
        return gamesCreate[gameId];
    }

    function getGameResolve(bytes32 gameId)
        public
        view
        returns (GameResolve memory)
    {
        return gamesResolve[gameId];
    }

    function getLastGamesCreate(uint256 dataLength)
        public
        view
        returns (GameCreate[] memory)
    {
        uint256 gamesLength = gameCreateIds.length;
        if (gamesLength < dataLength) {
            dataLength = gamesLength;
        }
        GameCreate[] memory games = new GameCreate[](dataLength);
        if (dataLength != 0) {
            uint256 gameIndex;
            for (uint256 i = gamesLength; i > gamesLength - dataLength; i--) {
                games[gameIndex] = gamesCreate[gameCreateIds[i - 1]];
                gameIndex++;
            }
        }
        return games;
    }

    function withdawBetFee(address _token)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        Token storage token = tokens[_token];
        uint256 _fees = token.fee;
        _safeTransfer(msg.sender, _token, _fees);
        delete token.fee;
    }

    // onlyRole(GAME_ROLE)
    function payout(
        address user,
        address token,
        uint256 amount
    ) external payable onlyRole(GAME_ROLE) {
        _safeTransfer(user, token, amount);
    }

    function cashIn(
        address _token,
        uint256 amount
    ) external payable onlyRole(GAME_ROLE) {
        bool isGasToken = _token == address(0);
        emit CashIn(
            _token,
            isGasToken ? msg.value : amount
        );
    }

    function addTokenFee(address _token, uint256 _fee)
        external
        onlyRole(GAME_ROLE)
    {
        Token storage token = tokens[_token];
        token.fee += _fee;
    }

    // test fulfill game create
    function testFulfillGamesCreate(
        bytes32[] memory _gameIds,
        uint256[] memory _startTime,
        string[] memory _homeTeam,
        string[] memory _awayTeam
    ) public {
        uint256 gamesLength = _gameIds.length;
        for (uint256 i = 0; i < gamesLength; i++) {
            GameCreate memory game = GameCreate({
                gameId: _gameIds[i],
                startTime: _startTime[i],
                homeTeam: _homeTeam[i],
                awayTeam: _awayTeam[i]
            });
            if (!(gamesCreate[game.gameId].startTime > 0)) {
                gamesCreate[game.gameId] = game;
                gameCreateIds.push(game.gameId);
            }
        }
    }

    function fulfillGamesCreate(bytes32 _requestId, bytes[] memory _games)
        public
        recordChainlinkFulfillment(_requestId)
    {
        uint256 gamesLength = _games.length;
        for (uint256 i = 0; i < gamesLength; i++) {
            GameCreate memory game = abi.decode(_games[i], (GameCreate));
            if (!(gamesCreate[game.gameId].startTime > 0)) {
                gamesCreate[game.gameId] = game;
                gameCreateIds.push(game.gameId);
            }
        }
    }

    function requestGames(uint256 _sportId, uint256 _date)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        Chainlink.Request memory req = buildOperatorRequest(
            jobId,
            this.fulfillGamesCreate.selector
        );
        req.addUint("date", _date);
        req.add("market", "create");
        req.addUint("sportId", _sportId);
        sendOperatorRequest(req, fee);
    }

    // test full fil game Resolve
    function testFulfillGamesResolve(
        bytes32[] memory _gameIds,
        uint8[] memory _homeScore,
        uint8[] memory _awayScore,
        uint8[] memory _statusId
    ) public {
        uint256 gamesLength = _gameIds.length;
        for (uint256 i = 0; i < gamesLength; i++) {
            GameResolve memory game = GameResolve({
                gameId: _gameIds[i],
                homeScore: _homeScore[i],
                awayScore: _awayScore[i],
                statusId: _statusId[i]
            });
            if (!(gamesResolve[game.gameId].statusId > 0)) {
                gamesResolve[game.gameId] = game;
                gameResolveIds.push(game.gameId);
            }
        }
    }

    function fulfillGamesResolve(bytes32 _requestId, bytes[] memory _games)
        public
        recordChainlinkFulfillment(_requestId)
    {
        uint256 gamesLength = _games.length;
        for (uint256 i = 0; i < gamesLength; i++) {
            GameResolve memory game = abi.decode(_games[i], (GameResolve));
            if (!(gamesResolve[game.gameId].statusId > 0)) {
                gamesResolve[game.gameId] = game;
                gameResolveIds.push(game.gameId);
            }
        }
    }

    function requestGamesResolve(
        uint256 _sportId,
        uint256 _date,
        string[] calldata _statusIds,
        string[] calldata _gameIds
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        Chainlink.Request memory req = buildOperatorRequest(
            jobId,
            this.fulfillGamesResolve.selector
        );
        req.addUint("date", _date);
        req.add("market", "resolve");
        req.addUint("sportId", _sportId);
        req.addStringArray("statusIds", _statusIds);
        req.addStringArray("gameIds", _gameIds);
        sendOperatorRequest(req, fee);
    }
}
