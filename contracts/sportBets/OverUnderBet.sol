// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.1;
import "../library/SafeERC20.sol";
import "../interface/IERC20.sol";
import "./enums.sol";
import "./IVault.sol";
import "../openzepplin/Ownable.sol";
import "../openzepplin/Pausable.sol";

contract OverUnderBets is Ownable, Pausable {
    using SafeERC20 for IERC20;

    struct MatchDetail {
        address overChoosen;
        address underChoosen;
        uint8 homeScore;
        uint8 awayScore;
        MatchStatus status;
    }

    struct OverUnderBetDetail {
        address token;
        uint256 amount;
        uint32 odds;
        uint256 fee;
    }

    struct OverUnderBet {
        uint256 id;
        bytes32 gameId;
        bool resolved;
        address payable proposeUser;
        address payable acceptUser;
        MatchDetail matchDetail;
        OverUnderBetDetail overUnderBetDetail;
    }

    struct Token {
        uint64 pendingCount;
    }

    mapping(uint256 => OverUnderBet) public overUnderBets;

    uint256[] public overUnderBetIds;

    uint256 overUnderBetsCount;

    mapping(address => uint256[]) internal userOverUnderBetIds;

    mapping(address => Token) public tokens;

    IVault public vault;

    event NewOverUnderBet();
    event AccepOverUnderBet();

    error UnderMinBetAmount(uint256 minBetAmount);

    constructor(address _vault) {
        vault = IVault(_vault);
    }

    function setVault(address _vault) public onlyOwner {
        require(address(_vault) == address(0), "address invalid");
        vault = IVault(_vault);
    }

    function getLastOverUnderBets(uint256 dataLength)
        public
        view
        returns (OverUnderBet[] memory)
    {
        uint256 betsLength = overUnderBetsCount;
        if (betsLength < dataLength) {
            dataLength = betsLength;
        }
        OverUnderBet[] memory bets = new OverUnderBet[](dataLength);
        if (dataLength != 0) {
            uint256 betIndex;
            for (uint256 i = betsLength; i > betsLength - dataLength; i--) {
                bets[betIndex] = overUnderBets[overUnderBetIds[i - 1]];
                betIndex++;
            }
        }
        return bets;
    }

    function getLastUserOverUnderBets(uint256 dataLength, address user)
        public
        view
        returns (OverUnderBet[] memory)
    {
        uint256 userBetsLength = userOverUnderBetIds[user].length;
        if (userBetsLength < dataLength) {
            dataLength = userBetsLength;
        }
        OverUnderBet[] memory bets = new OverUnderBet[](dataLength);
        if (dataLength != 0) {
            uint256 betIndex;
            for (
                uint256 i = userBetsLength;
                i > userBetsLength - dataLength;
                i--
            ) {
                bets[betIndex] = overUnderBets[
                    userOverUnderBetIds[user][i - 1]
                ];
                betIndex++;
            }
        }
        return bets;
    }

    function newOverUnderBet(
        bytes32 gameId,
        OverUnder _choosen,
        uint32 _odds,
        uint256 _betAmount,
        address _token
    ) public payable {
        IVault.GameCreate memory game = vault.getGameCreate(gameId);
        require(game.startTime > 0, "game are not yet create");
        require(
            game.startTime > block.timestamp,
            "this match has already finish"
        );
        if (_odds == 0 || _odds % 25 != 0) {
            revert("odds invalid");
        }
        require(vault.isAllowedToken(_token) == true, "ForbiddenToken");

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
        OverUnderBetDetail memory _overUnderBetDetail = OverUnderBetDetail({
            token: _token,
            amount: _betAmount,
            odds: _odds,
            fee: _fee
        });

        address _overChoosen = _choosen == OverUnder.Over ? user : address(0);
        address _underChoosen = _choosen == OverUnder.Under ? user : address(0);

        MatchDetail memory _matchDetail = MatchDetail({
            overChoosen: _overChoosen,
            underChoosen: _underChoosen,
            homeScore: 0,
            awayScore: 0,
            status: MatchStatus.STATUS_NONE
        });

        OverUnderBet memory newBet = OverUnderBet({
            id: overUnderBetsCount,
            gameId: game.gameId,
            resolved: false,
            proposeUser: payable(user),
            acceptUser: payable(address(0)),
            matchDetail: _matchDetail,
            overUnderBetDetail: _overUnderBetDetail
        });

        overUnderBets[newBet.id] = newBet;
        overUnderBetIds.push(newBet.id);
        overUnderBetsCount++;
        userOverUnderBetIds[user].push(newBet.id);
        vault.addTokenFee(_token, _fee);

        emit NewOverUnderBet();
    }

    function acceptOverUnderBet(uint256 betId, OverUnder _choosen)
        public
        payable
    {
        address user = msg.sender;
        OverUnderBet storage bet = overUnderBets[betId];
        address tokenAddress = bet.overUnderBetDetail.token;
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
        require(_choosen != OverUnder.None, "choosen is invalid");

        if (isGasToken) {
            require(
                msg.value >= ((bet.overUnderBetDetail.amount * 100) / 99),
                "not enough token for bet"
            );
            if (msg.value > ((bet.overUnderBetDetail.amount * 100) / 99)) {
                payable(user).transfer(
                    msg.value - ((bet.overUnderBetDetail.amount * 100) / 99)
                );
            }
            vault.cashIn{value: ((bet.overUnderBetDetail.amount * 100) / 99)}(
                tokenAddress,
                ((bet.overUnderBetDetail.amount * 100) / 99)
            );
        } else {
            IERC20(tokenAddress).safeTransferFrom(
                user,
                address(vault),
                ((bet.overUnderBetDetail.amount * 100) / 99)
            );
        }
        _fee = bet.overUnderBetDetail.amount / 99;

        if (
            (_choosen == OverUnder.Over &&
                bet.matchDetail.overChoosen != address(0)) ||
            (_choosen == OverUnder.Under &&
                bet.matchDetail.underChoosen != address(0))
        ) {
            revert("choosen an existing option");
        }

        address _overChoosen;
        address _underChoosen;
        if (
            bet.matchDetail.overChoosen != address(0) ||
            bet.matchDetail.underChoosen != address(0)
        ) {
            _overChoosen = bet.matchDetail.overChoosen != address(0)
                ? bet.matchDetail.overChoosen
                : user;
            _underChoosen = bet.matchDetail.underChoosen != address(0)
                ? bet.matchDetail.underChoosen
                : user;
        } else {
            _overChoosen = _choosen == OverUnder.Over ? user : bet.proposeUser;
            _underChoosen = _choosen == OverUnder.Under
                ? user
                : bet.proposeUser;
        }
        bet.matchDetail.overChoosen = _overChoosen;
        bet.matchDetail.underChoosen = _underChoosen;
        bet.acceptUser = payable(user);
        userOverUnderBetIds[user].push(bet.id);
        bet.overUnderBetDetail.fee += _fee;
        vault.addTokenFee(tokenAddress, _fee);

        emit AccepOverUnderBet();
    }

    function _resolveFullTimeOverUnderBet(uint256 betId) private {
        OverUnderBet storage bet = overUnderBets[betId];
        if (bet.matchDetail.status != MatchStatus.STATUS_FULL_TIME) {
            revert("match status is invalid");
        }
        if (
            bet.acceptUser == address(0) &&
            bet.matchDetail.status == MatchStatus.STATUS_FULL_TIME
        ) {
            address proposeUser = bet.proposeUser;
            uint256 payOut = bet.overUnderBetDetail.amount;
            vault.payout(proposeUser, bet.overUnderBetDetail.token, payOut);
            bet.resolved = true;
            return;
        }
        address winner;
        address loser;
        uint256 winPayOut;
        uint256 losePayOut;
        uint256 _fee;
        uint256 totalBetAmount;
        uint8 totalScore = (bet.matchDetail.homeScore +
            bet.matchDetail.awayScore) * 100;
        uint32 odds = bet.overUnderBetDetail.odds;
        if (totalScore > odds) {
            if (totalScore - odds > 25) {
                // overChoosen win all money
                // underChoosen lose all money
                winner = bet.matchDetail.overChoosen;
                loser = bet.matchDetail.underChoosen;
                totalBetAmount = bet.overUnderBetDetail.amount * 2;
                _fee = (bet.overUnderBetDetail.amount * 2) / 100;
                losePayOut = 0;
                winPayOut = totalBetAmount - _fee;
            } else if (totalScore - odds == 25) {
                // overChoosen win half money
                // under Choosen lose half money
                winner = bet.matchDetail.overChoosen;
                loser = bet.matchDetail.underChoosen;
                totalBetAmount = bet.overUnderBetDetail.amount * 2;
                _fee = (bet.overUnderBetDetail.amount * 2) / 100;
                losePayOut = (totalBetAmount * 1) / 4;
                winPayOut = (totalBetAmount * 3) / 4 - _fee;
            }
        } else if (totalScore < odds) {
            if (odds - totalScore > 25) {
                // overChoosen lose all money
                // underChoosen win all money
                winner = bet.matchDetail.underChoosen;
                loser = bet.matchDetail.overChoosen;
                totalBetAmount = bet.overUnderBetDetail.amount * 2;
                _fee = (bet.overUnderBetDetail.amount * 2) / 100;
                losePayOut = 0;
                winPayOut = totalBetAmount - _fee;
            } else if (odds - totalScore == 25) {
                // overChoosen lose half money
                // underChoosen win half money
                winner = bet.matchDetail.underChoosen;
                loser = bet.matchDetail.overChoosen;
                totalBetAmount = bet.overUnderBetDetail.amount * 2;
                _fee = (bet.overUnderBetDetail.amount * 2) / 100;
                losePayOut = (totalBetAmount * 1) / 4;
                winPayOut = (totalBetAmount * 3) / 4 - _fee;
            }
        } else {
            // money back to overChoosen
            // money back to underChoosen
            winner = bet.proposeUser;
            loser = bet.acceptUser;
            totalBetAmount = bet.overUnderBetDetail.amount * 2;
            uint256 _feePerUser = (bet.overUnderBetDetail.amount * 1) / 100;
            winPayOut = (totalBetAmount * 2) / 4 - _feePerUser;
            losePayOut = (totalBetAmount * 2) / 4 - _feePerUser;
            _fee = _feePerUser * 2;
        }
        vault.payout(loser, bet.overUnderBetDetail.token, losePayOut);
        vault.payout(winner, bet.overUnderBetDetail.token, winPayOut);
        bet.overUnderBetDetail.fee += _fee;
        bet.resolved = true;
    }

    function resolveOverUnderBet(uint256 betId) public {
        OverUnderBet storage bet = overUnderBets[betId];
        require(bet.resolved == false, "bet has already resolved");
        IVault.GameCreate memory gameCreated = vault.getGameCreate(bet.gameId);
        IVault.GameResolve memory gameResolved = vault.getGameResolve(
            bet.gameId
        );
        if (gameResolved.statusId == 11) {
            bet.matchDetail.homeScore = gameResolved.homeScore;
            bet.matchDetail.awayScore = gameResolved.awayScore;
            bet.matchDetail.status = MatchStatus.STATUS_FULL_TIME;
            _resolveFullTimeOverUnderBet(betId);
        } else if (
            gameResolved.statusId == 0 &&
            block.timestamp > gameCreated.startTime + (12 * 60 * 60)
        ) {
            vault.payout(
                bet.proposeUser,
                bet.overUnderBetDetail.token,
                bet.overUnderBetDetail.amount
            );
            if (bet.acceptUser != address(0)) {
                vault.payout(
                    bet.acceptUser,
                    bet.overUnderBetDetail.token,
                    bet.overUnderBetDetail.amount
                );
            }
            bet.resolved = true;
        } else {
            revert(
                "match has not resolve yet. resolve match before resolve bet"
            );
        }
    }
}
