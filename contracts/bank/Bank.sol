// SPDX-License-Identifier: UNLICENSED
// import "../library/Address.sol";
// import "../library/String.sol";
// import "../openzepplin/Context.sol";
// import "../interface/IERC20Permit.sol";
pragma solidity ^0.8.0;
import "hardhat/console.sol";
import "../library/SafeERC20.sol";
import "../interface/IERC20.sol";
import "../interface/IERC20Metadata.sol";
import "../interface/IGame.sol";
import "../abstract/Multicall.sol";
import "../abstract/AccessControlEnumerable.sol";

contract Bank is AccessControlEnumerable, Multicall {
    using SafeERC20 for IERC20;

    enum UpkeepActions {
        DistributePartnerHouseEdge
    }

    struct HouseEdgeSplit {
        uint16 bank;
        uint16 dividend;
        uint16 partner;
        uint16 treasury;
        uint16 team;
        uint256 dividendAmount;
        uint256 partnerAmount;
        uint256 treasuryAmount;
        uint256 teamAmount;
    }

    struct Token {
        bool allowed;
        bool paused;
        uint16 balanceRisk;
        uint64 VRFSubId;
        address partner;
        uint256 minBetAmount;
        uint256 minPartnerTransferAmount;
        HouseEdgeSplit houseEdgeSplit;
    }

    struct TokenMetadata {
        uint8 decimals;
        address tokenAddress;
        string name;
        string symbol;
        Token token;
    }

    uint8 private _tokensCount;

    address public immutable treasury;

    address public teamWallet;

    bytes32 public constant GAME_ROLE = keccak256("GAME_ROLE");

    bytes32 public constant SWIRLMASTER_ROLE = keccak256("SWIRLMASTER_ROLE");

    mapping(address => Token) public tokens;

    mapping(uint8 => address) private _tokensList;

    event SetTeamWallet(address teamWallet);

    event AddToken(address token);

    event SetBalanceRisk(address indexed token, uint16 balanceRisk);

    event SetAllowedToken(address indexed token, bool allowed);

    event SetTokenMinBetAmount(address indexed token, uint256 minBetAmount);

    event SetTokenVRFSubId(address indexed token, uint64 subId);

    event SetPausedToken(address indexed token, bool paused);

    event SetMinPartnerTransferAmount(
        address indexed token,
        uint256 minPartnerTransferAmount
    );

    event SetTokenPartner(address indexed token, address partner);

    event Deposit(address indexed token, uint256 amount);

    event Withdraw(address indexed token, uint256 amount);

    event SetTokenHouseEdgeSplit(
        address indexed token,
        uint16 bank,
        uint16 dividend,
        uint16 partner,
        uint16 treasury,
        uint16 team
    );
    event HouseEdgeDistribution(
        address indexed token,
        uint256 treasuryAmount,
        uint256 teamAmount
    );
    event HouseEdgePartnerDistribution(
        address indexed token,
        uint256 partnerAmount
    );
    event HarvestDividend(address indexed token, uint256 amount);

    event AllocateHouseEdgeAmount(
        address indexed token,
        uint256 bank,
        uint256 dividend,
        uint256 partner,
        uint256 treasury,
        uint256 team
    );
    event Payout(address indexed token, uint256 newBalance, uint256 profit);

    event CashIn(address indexed token, uint256 newBalance, uint256 amount);

    error TokenExists();
    error WrongHouseEdgeSplit(uint16 splitSum);
    error AccessDenied();
    error WrongAddress();
    error TokenNotPaused();
    error TokenHasPendingBets();

    modifier onlyTokenOwner(bytes32 role, address token) {
        address partner = tokens[token].partner;
        if (partner == address(0)) {
            // owner of contract
            _checkRole(role, msg.sender);
        } else if (msg.sender != partner) {
            // partner
            revert AccessDenied();
        }
        _;
    }

    constructor(address treasuryAddress, address teamWalletAddress) {
        if (treasuryAddress == address(0)) {
            revert WrongAddress();
        }

        treasury = treasuryAddress;

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);

        setTeamWallet(teamWalletAddress);
    }

    function _safeTransfer(
        address user,
        address token,
        uint256 amount
    ) private {
        if (_isGasToken(token)) {
            payable(user).transfer(amount);
        } else {
            IERC20(token).safeTransfer(user, amount);
        }
    }

    function _isGasToken(address token) private pure returns (bool) {
        return token == address(0);
    }

    function deposit(address token, uint256 amount)
        external
        payable
        onlyTokenOwner(DEFAULT_ADMIN_ROLE, token)
    {
        if (_isGasToken(token)) {
            amount = msg.value;
        } else {
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        }
        emit Deposit(token, amount);
    }

    function withdraw(address token, uint256 amount)
        public
        onlyTokenOwner(DEFAULT_ADMIN_ROLE, token)
    {
        uint256 balance = getBalance(token);
        if (balance != 0) {
            if (!tokens[token].paused) {
                revert TokenNotPaused();
            }

            uint256 roleMemberCount = getRoleMemberCount(GAME_ROLE);
            for (uint256 i; i < roleMemberCount; i++) {
                if (IGame(getRoleMember(GAME_ROLE, i)).hasPendingBets(token)) {
                    revert TokenHasPendingBets();
                }
            }
        }

        if (amount > balance) {
            amount = balance;
        }
        _safeTransfer(msg.sender, token, amount);
        emit Withdraw(token, amount);
    }

    function setBalanceRisk(address token, uint16 balanceRisk)
        external
        onlyTokenOwner(DEFAULT_ADMIN_ROLE, token)
    {
        tokens[token].balanceRisk = balanceRisk;
        emit SetBalanceRisk(token, balanceRisk);
    }

    function addToken(address token) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_tokensCount != 0) {
            for (uint8 i; i < _tokensCount; i++) {
                if (_tokensList[i] == token) {
                    revert TokenExists();
                }
            }
        }
        _tokensList[_tokensCount] = token;
        _tokensCount += 1;
        emit AddToken(token);
    }

    function setAllowedToken(address token, bool allowed)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        tokens[token].allowed = allowed;
        emit SetAllowedToken(token, allowed);
    }

    function setPausedToken(address token, bool paused)
        external
        onlyTokenOwner(DEFAULT_ADMIN_ROLE, token)
    {
        tokens[token].paused = paused;
        emit SetPausedToken(token, paused);
    }

    function setHouseEdgeSplit(
        address token,
        uint16 bank,
        uint16 dividend,
        uint16 partner,
        uint16 _treasury,
        uint16 team
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint16 splitSum = bank + dividend + team + partner + _treasury;
        if (splitSum != 10000) {
            revert WrongHouseEdgeSplit(splitSum);
        }

        HouseEdgeSplit storage tokenHouseEdge = tokens[token].houseEdgeSplit;
        tokenHouseEdge.bank = bank;
        tokenHouseEdge.dividend = dividend;
        tokenHouseEdge.partner = partner;
        tokenHouseEdge.treasury = _treasury;
        tokenHouseEdge.team = team;

        emit SetTokenHouseEdgeSplit(
            token,
            bank,
            dividend,
            partner,
            _treasury,
            team
        );
    }

    function setTokenMinBetAmount(address token, uint256 tokenMinBetAmount)
        external
        onlyTokenOwner(DEFAULT_ADMIN_ROLE, token)
    {
        tokens[token].minBetAmount = tokenMinBetAmount;
        emit SetTokenMinBetAmount(token, tokenMinBetAmount);
    }

    function setTokenVRFSubId(address token, uint64 subId)
        external
        onlyTokenOwner(DEFAULT_ADMIN_ROLE, token)
    {
        tokens[token].VRFSubId = subId;
        emit SetTokenVRFSubId(token, subId);
    }

    function payout(
        address payable user,
        address token,
        uint256 profit,
        uint256 fees
    ) external payable onlyRole(GAME_ROLE) {
        // Splits the house edge fees and allocates them as dividends, to the partner, the bank, the treasury, and team.
        {
            HouseEdgeSplit storage tokenHouseEdge = tokens[token]
                .houseEdgeSplit;

            uint256 partnerAmount;
            if (tokenHouseEdge.partner != 0) {
                partnerAmount = ((fees * tokenHouseEdge.partner) / 10000);
                tokenHouseEdge.partnerAmount += partnerAmount;
            }

            uint256 dividendAmount = (fees * tokenHouseEdge.dividend) / 10000;
            tokenHouseEdge.dividendAmount += dividendAmount;

            // The bank also get allocated a share of the house edge.
            uint256 bankAmount = (fees * tokenHouseEdge.bank) / 10000;

            uint256 treasuryAmount = (fees * tokenHouseEdge.treasury) / 10000;
            tokenHouseEdge.treasuryAmount += treasuryAmount;

            uint256 teamAmount = (fees * tokenHouseEdge.team) / 10000;
            tokenHouseEdge.teamAmount += teamAmount;

            emit AllocateHouseEdgeAmount(
                token,
                bankAmount,
                dividendAmount,
                partnerAmount,
                treasuryAmount,
                teamAmount
            );
        }

        // Pay the user
        _safeTransfer(user, token, profit);
        emit Payout(token, getBalance(token), profit);
    }

    function cashIn(address tokenAddress, uint256 amount)
        external
        payable
        onlyRole(GAME_ROLE)
    {
        emit CashIn(
            tokenAddress,
            getBalance(tokenAddress),
            _isGasToken(tokenAddress) ? msg.value : amount
        );
    }

    function getTokens() external view returns (TokenMetadata[] memory) {
        TokenMetadata[] memory _tokens = new TokenMetadata[](_tokensCount);
        for (uint8 i; i < _tokensCount; i++) {
            address tokenAddress = _tokensList[i];
            Token memory token = tokens[tokenAddress];
            if (_isGasToken(tokenAddress)) {
                _tokens[i] = TokenMetadata({
                    decimals: 18,
                    tokenAddress: tokenAddress,
                    name: "ETH",
                    symbol: "ETH",
                    token: token
                });
            } else {
                IERC20Metadata erc20Metadata = IERC20Metadata(tokenAddress);
                _tokens[i] = TokenMetadata({
                    decimals: erc20Metadata.decimals(),
                    tokenAddress: tokenAddress,
                    name: erc20Metadata.name(),
                    symbol: erc20Metadata.symbol(),
                    token: token
                });
            }
        }
        return _tokens;
    }

    function getMinBetAmount(address token)
        external
        view
        returns (uint256 minBetAmount)
    {
        minBetAmount = tokens[token].minBetAmount;
        if (minBetAmount == 0) {
            minBetAmount = 10000;
        }
    }

    function getMaxBetAmount(address token, uint256 multiplier)
        external
        view
        returns (uint256)
    {
        return (getBalance(token) * tokens[token].balanceRisk) / multiplier;
    }

    function isAllowedToken(address tokenAddress) external view returns (bool) {
        Token memory token = tokens[tokenAddress];
        return token.allowed && !token.paused;
    }

    function getVRFSubId(address token) external view returns (uint64) {
        return tokens[token].VRFSubId;
    }

    function setTeamWallet(address _teamWallet)
        public
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (_teamWallet == address(0)) {
            revert WrongAddress();
        }
        teamWallet = _teamWallet;
        emit SetTeamWallet(teamWallet);
    }

    function withdrawHouseEdgeAmount(address tokenAddress) public {
        HouseEdgeSplit storage tokenHouseEdge = tokens[tokenAddress]
            .houseEdgeSplit;
        uint256 treasuryAmount = tokenHouseEdge.treasuryAmount;
        uint256 teamAmount = tokenHouseEdge.teamAmount;
        if (treasuryAmount != 0) {
            delete tokenHouseEdge.treasuryAmount;
            _safeTransfer(treasury, tokenAddress, treasuryAmount);
        }
        if (teamAmount != 0) {
            delete tokenHouseEdge.teamAmount;
            _safeTransfer(teamWallet, tokenAddress, teamAmount);
        }
        if (treasuryAmount != 0 || teamAmount != 0) {
            emit HouseEdgeDistribution(
                tokenAddress,
                treasuryAmount,
                teamAmount
            );
        }
    }

    function setTokenPartner(address token, address partner)
        external
        onlyTokenOwner(DEFAULT_ADMIN_ROLE, token)
    {
        uint256 roleMemberCount = getRoleMemberCount(GAME_ROLE);
        for (uint256 i; i < roleMemberCount; i++) {
            IGame(getRoleMember(GAME_ROLE, i)).withdrawTokensVRFFees(token);
        }
        withdrawPartnerAmount(token);
        withdraw(token, getBalance(token));
        tokens[token].partner = partner;
        emit SetTokenPartner(token, partner);
    }

    function setMinPartnerTransferAmount(
        address token,
        uint256 minPartnerTransferAmount
    ) external onlyTokenOwner(DEFAULT_ADMIN_ROLE, token) {
        tokens[token].minPartnerTransferAmount = minPartnerTransferAmount;
        emit SetMinPartnerTransferAmount(token, minPartnerTransferAmount);
    }

    function withdrawPartnerAmount(address tokenAddress) public {
        Token storage token = tokens[tokenAddress];
        uint256 partnerAmount = token.houseEdgeSplit.partnerAmount;
        if (partnerAmount != 0 && token.partner != address(0)) {
            delete token.houseEdgeSplit.partnerAmount;
            _safeTransfer(token.partner, tokenAddress, partnerAmount);
            emit HouseEdgePartnerDistribution(tokenAddress, partnerAmount);
        }
    }

    function getBalance(address token) public view returns (uint256) {
        uint256 balance;
        if (_isGasToken(token)) {
            balance = address(this).balance;
        } else {
            balance = IERC20(token).balanceOf(address(this));
        }
        HouseEdgeSplit memory tokenHouseEdgeSplit = tokens[token]
            .houseEdgeSplit;
        return
            balance -
            tokenHouseEdgeSplit.dividendAmount -
            tokenHouseEdgeSplit.partnerAmount -
            tokenHouseEdgeSplit.treasuryAmount -
            tokenHouseEdgeSplit.teamAmount;
    }
}

// Constructor => (address treasuryAddress, address teamWalletAddress) setup default role as DEFAULT_ADMIN_ROLE

// ROLE require
// Deposit => 						external onlyTokenOwner(DEFAULT_ADMIN_ROLE, token) => _checkRole(DEFAULT_ADMIN_ROLE, sender)
// Withdrawn => 					public onlyTokenOwner(DEFAULT_ADMIN_ROLE, token) => _checkRole(DEFAULT_ADMIN_ROLE, sender)

// addToken => 					    external onlyRole(DEFAULT_ADMIN_ROLE)

// setAllowedToken => 				external onlyRole(DEFAULT_ADMIN_ROLE)
// setPausedToken => 				external onlyTokenOwner(DEFAULT_ADMIN_ROLE, token) => _checkRole(DEFAULT_ADMIN_ROLE, sender) false
// setBalanceRisk => 				external onlyTokenOwner(DEFAULT_ADMIN_ROLE, token) => _checkRole(DEFAULT_ADMIN_ROLE, sender) 2
// setTokenVRFSubId => 			    external onlyTokenOwner(DEFAULT_ADMIN_ROLE, token) => _checkRole(DEFAULT_ADMIN_ROLE, sender)
// setTokenPartner => 				external onlyTokenOwner(DEFAULT_ADMIN_ROLE, token) => _checkRole(DEFAULT_ADMIN_ROLE, sender)
// setTokenMinBetAmount => 	    	external onlyTokenOwner(DEFAULT_ADMIN_ROLE, token) => _checkRole(DEFAULT_ADMIN_ROLE, sender)
// setMinPartnerTransferAmount =>  external onlyTokenOwner(DEFAULT_ADMIN_ROLE, token) => _checkRole(DEFAULT_ADMIN_ROLE, sender) 2

// setHouseEdgeSplit => 			external onlyRole(DEFAULT_ADMIN_ROLE)
// setTeamWallet => 				public onlyRole(DEFAULT_ADMIN_ROLE)

// payout => 						external onlyRole(GAME_ROLE)
// cashIn => 						external onlyRole(GAME_ROLE)
// harvest => 						external onlyRole(SWIRLMASTER_ROLE)

// _safeTransfer => private noRole
// _isGasToken => private noRole
// getDividends => external noRole
// getTokens => external noRole
// getMinBetAmount => external noRole
// getMaxBetAmount => external noRole
// getVRFSubId => external noRole
// getTokenOwner => external noRole

// withdrawHouseEdgeAmount => public noRole
// withdrawPartnerAmount => public noRole
// getBalance => public noRole

// performUpkeep => external noRole
// checkUpkeep => external noRole (Chainlink)

//
