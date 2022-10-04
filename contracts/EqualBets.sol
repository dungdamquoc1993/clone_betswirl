// SPDX-License-Identifier: UNLICENSED
import "@chainlink/contracts/src/v0.8/ChainlinkClient.sol";
import "./library/SafeERC20.sol";
import "./interface/IERC20.sol";
import "./enums.sol";
import "hardhat/console.sol";

pragma solidity ^0.8.1;

contract EqualBets is ChainlinkClient {
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

    struct MatchDetail {
        HomeAway stronger;
        address homeChoosen;
        address awayChoosen;
        uint8 homeScore;
        uint8 awayScore;
        MatchStatus status;
    }

    struct HandicatBetDetail {
        address token;
        uint256 amount;
        uint32 odds;
        uint256 fee;
    }

    struct HandicapBet {
        uint256 id;
        bytes32 gameId;
        bool resolved;
        address payable proposeUser;
        address payable acceptUser;
        MatchDetail matchDetail;
        HandicatBetDetail handicapBetDetail;
    }

    struct Token {
        bool allowed;
        uint64 pendingCount;
        uint256 minBetAmount;
        uint256 maxBetAmount;
    }

    uint256 private _tokensCount;

    mapping(uint256 => address) private _tokensList;

    mapping(address => Token) public tokens;

    mapping(uint256 => HandicapBet) public handicapBets;

    uint256[] public handicapBetIds;

    uint256 handicapBetsCount;

    mapping(address => uint256[]) internal userHandicapBetIds;

    mapping(bytes32 => GameCreate) public gamesCreate;

    bytes32[] public gameCreateIds;

    mapping(bytes32 => GameResolve) public gamesResolve;

    bytes32[] public gameResolveIds;

    bytes32 private jobId;
    uint256 private fee;
    bytes32 public requestId;

    event NewBet();
    event AcceptBet();
    event AddToken(address token);
    event SetTokenMinBetAmount(address token, uint256 tokenMinBetAmount);
    event SetTokenMaxBetAmount(address token, uint256 tokenMaxBetAmount);

    error InvalidLinkWeiPrice(int256 linkWei);
    error WrongGasValueToCoverFee();
    error ForbiddenToken();
    error UnderMinBetAmount(uint256 minBetAmount);
    error TokenExists();

    constructor(
        address _link,
        address _oracle,
        bytes32 _jobId,
        uint256 _fee
    ) {
        setChainlinkToken(_link);
        setChainlinkOracle(_oracle);
        jobId = _jobId;
        fee = _fee;
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

    function setTokenMinBetAmount(address token, uint256 tokenMinBetAmount)
        external
    {
        tokens[token].minBetAmount = tokenMinBetAmount;
        emit SetTokenMinBetAmount(token, tokenMinBetAmount);
    }

    function setTokenMaxBetAmount(address token, uint256 tokenMaxBetAmount)
        external
    {
        tokens[token].maxBetAmount = tokenMaxBetAmount;
        emit SetTokenMaxBetAmount(token, tokenMaxBetAmount);
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

    function getLastHandicapBets(uint256 dataLength)
        public
        view
        returns (HandicapBet[] memory)
    {
        // mapping(uint256 => HandicapBet) public handicapBets;
        // uint256[] public handicapBetIds;
        // uint256 handicapBetsCount;

        uint256 betsLength = handicapBetsCount;
        if (betsLength < dataLength) {
            dataLength = betsLength;
        }
        HandicapBet[] memory bets = new HandicapBet[](dataLength);
        if (dataLength != 0) {
            uint256 betIndex;
            for (uint256 i = betsLength; i > betsLength - dataLength; i--) {
                bets[betIndex] = handicapBets[handicapBetIds[i - 1]];
                betIndex++;
            }
        }
        return bets;
    }

    function getLastUserHandicapBets(uint256 dataLength, address user)
        public
        view
        returns (HandicapBet[] memory)
    {
        uint256 userBetsLength = userHandicapBetIds[user].length;
        if (userBetsLength < dataLength) {
            dataLength = userBetsLength;
        }
        HandicapBet[] memory bets = new HandicapBet[](dataLength);
        if (dataLength != 0) {
            uint256 betIndex;
            for (
                uint256 i = userBetsLength;
                i > userBetsLength - dataLength;
                i--
            ) {
                bets[betIndex] = handicapBets[userHandicapBetIds[user][i - 1]];
                betIndex++;
            }
        }
        return bets;
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

    function requestGames(uint256 _sportId, uint256 _date) external {
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
    ) public returns (bytes32) {
        Chainlink.Request memory req = buildOperatorRequest(
            jobId,
            this.fulfillGamesResolve.selector
        );
        req.addUint("date", _date);
        req.add("market", "resolve");
        req.addUint("sportId", _sportId);
        req.addStringArray("statusIds", _statusIds);
        req.addStringArray("gameIds", _gameIds);
        bytes32 id = sendOperatorRequest(req, fee);
        return id;
    }

    function newHandicapBet(
        bytes32 gameId,
        HomeAway _stronger,
        HomeAway _choosen,
        uint32 _odds,
        uint256 _betAmount,
        address _token
    ) public payable {
        GameCreate storage game = gamesCreate[gameId];
        require(
            game.startTime + 5400 > block.timestamp,
            "this match has already finish"
        );
        if (_stronger != HomeAway.None && (_odds == 0 || _odds % 25 != 0)) {
            revert("odds invalid");
        } else if (_stronger == HomeAway.None && _odds != 0) {
            revert("odds invalid");
        }
        if (!(game.startTime > 0)) {
            revert("game are not yet create");
        }
        if (isAllowedToken(_token) == false) {
            revert ForbiddenToken();
        }
        address user = msg.sender;
        Token storage token = tokens[_token];
        bool isGasToken = _token == address(0);

        if (isGasToken) {
            require(msg.value == _betAmount, "invalid bet amount");
        }

        {
            // capped min max bet
            if (_betAmount < token.minBetAmount) {
                revert UnderMinBetAmount(token.minBetAmount);
            }

            if (_betAmount > token.maxBetAmount) {
                if (isGasToken) {
                    payable(user).transfer(_betAmount - token.maxBetAmount);
                }
                _betAmount = token.maxBetAmount;
            }
        }

        if (!isGasToken) {
            IERC20(_token).safeTransferFrom(user, address(this), _betAmount);
        }

        uint256 _fee = (_betAmount * 1) / 100;
        _betAmount = _betAmount - _fee;
        HandicatBetDetail memory _handicapBetDetail = HandicatBetDetail({
            token: _token,
            amount: _betAmount,
            odds: _odds,
            fee: _fee
        });

        address _homeChoosen = _choosen == HomeAway.HomeTeam
            ? user
            : address(0);
        address _awayChoosen = _choosen == HomeAway.AwayTeam
            ? user
            : address(0);

        MatchDetail memory _matchDetail = MatchDetail({
            stronger: _stronger,
            homeChoosen: _homeChoosen,
            awayChoosen: _awayChoosen,
            homeScore: 0,
            awayScore: 0,
            status: MatchStatus.STATUS_NONE
        });

        HandicapBet memory newBet = HandicapBet({
            id: handicapBetsCount,
            gameId: game.gameId,
            resolved: false,
            proposeUser: payable(user),
            acceptUser: payable(address(0)),
            matchDetail: _matchDetail,
            handicapBetDetail: _handicapBetDetail
        });

        handicapBets[newBet.id] = newBet;
        handicapBetIds.push(newBet.id);
        handicapBetsCount++;
        userHandicapBetIds[user].push(newBet.id);

        emit NewBet();
    }

    function acceptHandicapBet(uint256 betId, HomeAway _choosen)
        public
        payable
    {
        address user = msg.sender;
        HandicapBet storage bet = handicapBets[betId];
        address tokenAddress = bet.handicapBetDetail.token;
        bool isGasToken = tokenAddress == address(0);

        GameCreate storage game = gamesCreate[bet.gameId];
        require(
            game.startTime + 5400 > block.timestamp,
            "this match has already finish"
        );
        require(
            bet.acceptUser == address(0),
            "the bet is already taken by other user"
        );

        require(user != bet.proposeUser, "can not accept your own bet");
        require(_choosen != HomeAway.None, "choosen is invalid");
        if (isGasToken) {
            require(
                msg.value >= ((bet.handicapBetDetail.amount * 100) / 99),
                "not enough token for bet"
            );
            if (msg.value > ((bet.handicapBetDetail.amount * 100) / 99)) {
                payable(user).transfer(
                    msg.value - ((bet.handicapBetDetail.amount * 100) / 99)
                );
                uint256 _fee = bet.handicapBetDetail.amount / 99;
                bet.handicapBetDetail.fee += _fee;
            }
        } else {
            IERC20(tokenAddress).safeTransferFrom(
                user,
                address(this),
                ((bet.handicapBetDetail.amount * 100) / 99)
            );
            uint256 _fee = bet.handicapBetDetail.amount / 99;
            bet.handicapBetDetail.fee += _fee;
        }

        if (
            (_choosen == HomeAway.HomeTeam &&
                bet.matchDetail.homeChoosen != address(0)) ||
            (_choosen == HomeAway.AwayTeam &&
                bet.matchDetail.awayChoosen != address(0))
        ) {
            revert("choosen an existing option");
        }

        address _homeChoosen;
        address _awayChoosen;

        if (
            bet.matchDetail.homeChoosen != address(0) ||
            bet.matchDetail.awayChoosen != address(0)
        ) {
            _homeChoosen = bet.matchDetail.homeChoosen != address(0)
                ? bet.matchDetail.homeChoosen
                : user;
            _awayChoosen = bet.matchDetail.awayChoosen != address(0)
                ? bet.matchDetail.awayChoosen
                : user;
        } else {
            _homeChoosen = _choosen == HomeAway.HomeTeam
                ? user
                : bet.proposeUser;
            _awayChoosen = _choosen == HomeAway.AwayTeam
                ? user
                : bet.proposeUser;
        }
        bet.matchDetail.homeChoosen = _homeChoosen;
        bet.matchDetail.awayChoosen = _awayChoosen;

        bet.acceptUser = payable(user);
        userHandicapBetIds[user].push(bet.id);

        emit AcceptBet();
    }

    function _resolveFullTimeHandicapBet(uint256 betId) private {
        HandicapBet storage bet = handicapBets[betId];
        if (bet.matchDetail.status != MatchStatus.STATUS_FULL_TIME) {
            revert("match status is invalid");
        }
        if (
            bet.acceptUser == address(0) &&
            bet.matchDetail.status == MatchStatus.STATUS_FULL_TIME
        ) {
            address proposeUser = bet.proposeUser;
            uint256 payOut = bet.handicapBetDetail.amount;
            _safeTransfer(proposeUser, bet.handicapBetDetail.token, payOut);
            return;
        }
        uint32 homeScore = bet.matchDetail.homeScore;
        uint32 awayScore = bet.matchDetail.awayScore;
        HomeAway stronger = bet.matchDetail.stronger;
        uint32 odds = bet.handicapBetDetail.odds;
        uint32 strongerScore;
        uint32 weakerScore;
        address winner;
        address loser;
        uint256 winPayOut;
        uint256 losePayOut;
        uint256 _fee;
        uint256 totalBetAmount;
        if (stronger == HomeAway.HomeTeam) {
            strongerScore = homeScore * 100;
            weakerScore = awayScore * 100 + odds;
            if (strongerScore > weakerScore) {
                if (strongerScore - weakerScore == 25) {
                    // chấp 3/4
                    // chossen stronger win half money
                    // choosen weaker lose half money
                    winner = bet.matchDetail.homeChoosen;
                    loser = bet.matchDetail.awayChoosen;
                    totalBetAmount = bet.handicapBetDetail.amount * 2;
                    _fee = (bet.handicapBetDetail.amount * 2) / 100;
                    losePayOut = (totalBetAmount * 1) / 4;
                    winPayOut = (totalBetAmount * 3) / 4 - _fee;
                } else if (strongerScore - weakerScore > 25) {
                    // chossen stronger win all money
                    // choosen weaker lose all money
                    winner = bet.matchDetail.homeChoosen;
                    loser = bet.matchDetail.awayChoosen;
                    totalBetAmount = bet.handicapBetDetail.amount * 2;
                    _fee = (bet.handicapBetDetail.amount * 2) / 100;
                    losePayOut = 0;
                    winPayOut = totalBetAmount - _fee;
                }
            } else if (strongerScore < weakerScore) {
                if (weakerScore - strongerScore == 25) {
                    // did test
                    // chấp 1/4
                    // choosen weaker win half money
                    // choosen stronger lose half money
                    winner = bet.matchDetail.awayChoosen;
                    loser = bet.matchDetail.homeChoosen;
                    totalBetAmount = bet.handicapBetDetail.amount * 2;
                    _fee = (bet.handicapBetDetail.amount * 2) / 100;
                    losePayOut = (totalBetAmount * 1) / 4;
                    winPayOut = (totalBetAmount * 3) / 4 - _fee;
                } else if (weakerScore - strongerScore > 25) {
                    // choosen weaker win all money
                    // choosen stronger lose all money
                    winner = bet.matchDetail.awayChoosen;
                    loser = bet.matchDetail.homeChoosen;
                    totalBetAmount = bet.handicapBetDetail.amount * 2;
                    _fee = (bet.handicapBetDetail.amount * 2) / 100;
                    losePayOut = 0;
                    winPayOut = totalBetAmount - _fee;
                }
            } else if (strongerScore == weakerScore) {
                // choosen stronger loose all money
                // choosen weaker win all money
                winner = bet.matchDetail.awayChoosen;
                loser = bet.matchDetail.homeChoosen;
                totalBetAmount = bet.handicapBetDetail.amount * 2;
                _fee = (bet.handicapBetDetail.amount * 2) / 100;
                losePayOut = 0;
                winPayOut = totalBetAmount - _fee;
            }
        } else if (stronger == HomeAway.AwayTeam) {
            strongerScore = awayScore * 100;
            weakerScore = homeScore * 100 + odds;
            if (strongerScore > weakerScore) {
                if (strongerScore - weakerScore == 25) {
                    // chấp 3/4
                    // chossen stronger win half money
                    // choosen weaker lose half money
                    winner = bet.matchDetail.awayChoosen;
                    loser = bet.matchDetail.homeChoosen;
                    totalBetAmount = bet.handicapBetDetail.amount * 2;
                    _fee = (bet.handicapBetDetail.amount * 2) / 100;
                    losePayOut = (totalBetAmount * 1) / 4;
                    winPayOut = (totalBetAmount * 3) / 4 - _fee;
                } else if (strongerScore - weakerScore > 25) {
                    //
                    // chossen stronger win all money
                    // choosen weaker lose all money
                    winner = bet.matchDetail.awayChoosen;
                    loser = bet.matchDetail.homeChoosen;
                    totalBetAmount = bet.handicapBetDetail.amount * 2;
                    _fee = (bet.handicapBetDetail.amount * 2) / 100;
                    losePayOut = 0;
                    winPayOut = totalBetAmount - _fee;
                }
            } else if (strongerScore < weakerScore) {
                if (weakerScore - strongerScore == 25) {
                    // chấp 1/4
                    // choosen weaker win half money
                    // choosen stronger lose half money
                    winner = bet.matchDetail.homeChoosen;
                    loser = bet.matchDetail.awayChoosen;
                    totalBetAmount = bet.handicapBetDetail.amount * 2;
                    _fee = (bet.handicapBetDetail.amount * 2) / 100;
                    losePayOut = (totalBetAmount * 1) / 4;
                    winPayOut = (totalBetAmount * 3) / 4 - _fee;
                } else if (weakerScore - strongerScore > 25) {
                    // choosen weaker win all money
                    // choosen stronger lose all money
                    winner = bet.matchDetail.homeChoosen;
                    loser = bet.matchDetail.awayChoosen;
                    totalBetAmount = bet.handicapBetDetail.amount * 2;
                    _fee = (bet.handicapBetDetail.amount * 2) / 100;
                    losePayOut = 0;
                    winPayOut = totalBetAmount - _fee;
                }
            } else if (strongerScore == weakerScore) {
                // choosen stronger loose all money
                // choosen weaker win all money
                winner = bet.matchDetail.homeChoosen;
                loser = bet.matchDetail.awayChoosen;
                totalBetAmount = bet.handicapBetDetail.amount * 2;
                _fee = (bet.handicapBetDetail.amount * 2) / 100;
                losePayOut = 0;
                winPayOut = totalBetAmount - _fee;
            }
        } else {
            if (homeScore > awayScore) {
                // stronger win all money
                // weaker lose all money
                winner = bet.matchDetail.homeChoosen;
                loser = bet.matchDetail.awayChoosen;
                totalBetAmount = bet.handicapBetDetail.amount * 2;
                _fee = (bet.handicapBetDetail.amount * 2) / 100;
                losePayOut = 0;
                winPayOut = totalBetAmount - _fee;
            } else if (homeScore < awayScore) {
                // stronger lose all money
                // weaker win all money
                winner = bet.matchDetail.awayChoosen;
                loser = bet.matchDetail.homeChoosen;
                totalBetAmount = bet.handicapBetDetail.amount * 2;
                _fee = (bet.handicapBetDetail.amount * 2) / 100;
                losePayOut = 0;
                winPayOut = totalBetAmount - _fee;
            } else {
                // even money back to user
                winner = bet.proposeUser;
                loser = bet.acceptUser;
                totalBetAmount = bet.handicapBetDetail.amount * 2;
                uint256 _feePerUser = (bet.handicapBetDetail.amount * 1) / 100;
                winPayOut = totalBetAmount * 2 /4 - _feePerUser;
                losePayOut = totalBetAmount * 2 /4 - _feePerUser;
                _fee = _feePerUser * 2;
            }
        }
        _safeTransfer(loser, bet.handicapBetDetail.token, losePayOut);
        _safeTransfer(winner, bet.handicapBetDetail.token, winPayOut);
        bet.handicapBetDetail.fee += _fee;
        bet.resolved = true;
    }

    function resolveHandicapBet(uint256 betId) public {
        HandicapBet storage bet = handicapBets[betId];
        // GameCreate storage gameCreated = gamesCreate[bet.gameId];
        // if (block.timestamp < gameCreated.startTime + 7200) {
        //     revert("match not finish yet");
        // }
        GameResolve storage gameResolved = gamesResolve[bet.gameId];

        if (gameResolved.statusId == 11) {
            bet.matchDetail.homeScore = gameResolved.homeScore;
            bet.matchDetail.awayScore = gameResolved.awayScore;
            bet.matchDetail.status = MatchStatus.STATUS_FULL_TIME;
            _resolveFullTimeHandicapBet(betId);
        } else {
            revert(
                "match has not resolve yet. resolve match before resolve bet"
            );
        }
    }
}
