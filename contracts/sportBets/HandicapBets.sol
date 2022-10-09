// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.1;
import "../library/SafeERC20.sol";
import "../interface/IERC20.sol";
import "./enums.sol";
import "./IVault.sol";
import "hardhat/console.sol";
import "../openzepplin/Ownable.sol";
import "../openzepplin/Pausable.sol";

contract HandicapBets is Ownable, Pausable {
    using SafeERC20 for IERC20;

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

    mapping(uint256 => HandicapBet) public handicapBets;

    uint256[] public handicapBetIds;

    uint256 handicapBetsCount;

    mapping(address => uint256[]) internal userHandicapBetIds;

    IVault public vault;

    event NewHandicapBet();
    event AcceptHandicapBet();

    error UnderMinBetAmount(uint256 minBetAmount);

    constructor(address _vault) {
        vault = IVault(_vault);
    }

    function setVault(address _vault) public onlyOwner {
        require(address(_vault) == address(0), "address invalid");
        vault = IVault(_vault);
    }

    function getLastHandicapBets(uint256 dataLength)
        public
        view
        returns (HandicapBet[] memory)
    {
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

    function newHandicapBet(
        bytes32 gameId,
        HomeAway _stronger,
        HomeAway _choosen,
        uint32 _odds,
        uint256 _betAmount,
        address _token
    ) public payable {
        IVault.GameCreate memory game = vault.getGameCreate(gameId);
        require(game.startTime > 0, "game are not yet create");
        require(
            game.startTime > block.timestamp,
            "this match has already began"
        );
        require(vault.isAllowedToken(_token) == true, "ForbiddenToken");

        if (_stronger != HomeAway.None && (_odds == 0 || _odds % 25 != 0)) {
            revert("odds invalid");
        } else if (_stronger == HomeAway.None && _odds != 0) {
            revert("odds invalid");
        }

        address user = msg.sender;
        IVault.Token memory token = vault.tokens(_token);
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
            IERC20(_token).safeTransferFrom(user, address(vault), _betAmount);
        } else {
            vault.cashIn{value: _betAmount}(_token, _betAmount);
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
        vault.addTokenFee(_token, _fee);

        emit NewHandicapBet();
    }

    function acceptHandicapBet(uint256 betId, HomeAway _choosen)
        public
        payable
    {
        address user = msg.sender;
        HandicapBet storage bet = handicapBets[betId];
        address tokenAddress = bet.handicapBetDetail.token;
        bool isGasToken = tokenAddress == address(0);
        uint256 _fee;
        IVault.GameCreate memory game = vault.getGameCreate(bet.gameId);
        require(
            game.startTime > block.timestamp,
            "this match has already began"
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
            }
            vault.cashIn{value: ((bet.handicapBetDetail.amount * 100) / 99)}(
                tokenAddress,
                ((bet.handicapBetDetail.amount * 100) / 99)
            );
        } else {
            IERC20(tokenAddress).safeTransferFrom(
                user,
                address(vault),
                ((bet.handicapBetDetail.amount * 100) / 99)
            );
        }
        _fee = bet.handicapBetDetail.amount / 99;

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
        bet.handicapBetDetail.fee += _fee;
        bet.acceptUser = payable(user);
        userHandicapBetIds[user].push(bet.id);
        vault.addTokenFee(tokenAddress, _fee);

        emit AcceptHandicapBet();
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
            vault.payout(proposeUser, bet.handicapBetDetail.token, payOut);
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
                    // did test
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
                winPayOut = (totalBetAmount * 2) / 4 - _feePerUser;
                losePayOut = (totalBetAmount * 2) / 4 - _feePerUser;
                _fee = _feePerUser * 2;
            }
        }
        vault.payout(loser, bet.handicapBetDetail.token, losePayOut);
        vault.payout(winner, bet.handicapBetDetail.token, winPayOut);
        vault.addTokenFee(bet.handicapBetDetail.token, _fee);
        bet.handicapBetDetail.fee += _fee;
        bet.resolved = true;
    }

    function resolveHandicapBet(uint256 betId) public {
        HandicapBet storage bet = handicapBets[betId];
        require(bet.resolved == false, "bet has already resolved");
        IVault.GameResolve memory gameResolved = vault.getGameResolve(
            bet.gameId
        );
        if (gameResolved.statusId == 11) {
            bet.matchDetail.homeScore = gameResolved.homeScore;
            bet.matchDetail.awayScore = gameResolved.awayScore;
            bet.matchDetail.status = MatchStatus.STATUS_FULL_TIME;
            _resolveFullTimeHandicapBet(betId);
        } else if (gameResolved.statusId == 15 || gameResolved.statusId == 2) {
            bet.matchDetail.status = MatchStatus.STATUS_CANCELED;
            vault.payout(
                bet.proposeUser,
                bet.handicapBetDetail.token,
                bet.handicapBetDetail.amount
            );
            if (bet.acceptUser != address(0)) {
                vault.payout(
                    bet.acceptUser,
                    bet.handicapBetDetail.token,
                    bet.handicapBetDetail.amount
                );
            }
        } else {
            revert(
                "match has not resolve yet. resolve match before resolve bet"
            );
        }
    }
}
